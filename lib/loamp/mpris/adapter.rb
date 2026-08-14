# frozen_string_literal: true

module Loamp
  module Mpris
    # MPRIS semantics on top of Player, with no D-Bus in sight.
    #
    # Every translation the spec asks for lives here: seconds to microseconds,
    # 0-100 volume to a 0.0-1.0 double, :off/:all/:one to None/Playlist/Track,
    # and a track to the metadata map. Keeping it free of GIO means the whole
    # protocol surface can be tested without a session bus.
    class Adapter
      class UnknownMember < StandardError
      end

      IDENTITY = 'LOAMP'
      DESKTOP_ENTRY = 'loamp'

      URI_SCHEMES = %w[file http https].freeze
      MIME_TYPES = %w[
        audio/mpeg audio/flac audio/ogg audio/opus audio/mp4 audio/aac
        audio/x-wav audio/x-ms-wma audio/x-aiff
      ].freeze

      PLAYBACK_STATUS = { playing: 'Playing', paused: 'Paused', stopped: 'Stopped' }.freeze
      LOOP_STATUS = { off: 'None', all: 'Playlist', one: 'Track' }.freeze
      REPEAT_MODE = LOOP_STATUS.invert.freeze

      # Signatures for the metadata map. Types matter here: a client reading
      # mpris:length expects an int64 and will not coerce a string into one.
      METADATA_SIGNATURES = {
        'mpris:trackid' => 'o',
        'mpris:length' => 'x',
        'mpris:artUrl' => 's',
        'xesam:title' => 's',
        'xesam:album' => 's',
        'xesam:artist' => 'as',
        'xesam:albumArtist' => 'as',
        'xesam:genre' => 'as',
        'xesam:composer' => 'as',
        'xesam:comment' => 'as',
        'xesam:trackNumber' => 'i',
        'xesam:discNumber' => 'i',
        'xesam:contentCreated' => 's',
        'xesam:url' => 's',
      }.freeze

      ROOT_PROPERTIES = {
        'CanQuit' => 'b',
        'CanRaise' => 'b',
        'HasTrackList' => 'b',
        'Identity' => 's',
        'DesktopEntry' => 's',
        'SupportedUriSchemes' => 'as',
        'SupportedMimeTypes' => 'as',
      }.freeze

      PLAYER_PROPERTIES = {
        'PlaybackStatus' => 's',
        'LoopStatus' => 's',
        'Rate' => 'd',
        'Shuffle' => 'b',
        'Metadata' => Variant::DICTIONARY,
        'Volume' => 'd',
        'Position' => 'x',
        'MinimumRate' => 'd',
        'MaximumRate' => 'd',
        'CanGoNext' => 'b',
        'CanGoPrevious' => 'b',
        'CanPlay' => 'b',
        'CanPause' => 'b',
        'CanSeek' => 'b',
        'CanControl' => 'b',
      }.freeze

      SIGNATURES = { ROOT_INTERFACE => ROOT_PROPERTIES,
                     PLAYER_INTERFACE => PLAYER_PROPERTIES }.freeze

      # Properties worth re-announcing when the track changes. Position is
      # deliberately absent — the spec says to use the Seeked signal for that.
      TRACK_CHANGE_PROPERTIES = %w[Metadata CanGoNext CanGoPrevious CanPlay CanSeek].freeze
      STATE_CHANGE_PROPERTIES = %w[PlaybackStatus CanGoNext CanGoPrevious CanPlay CanSeek].freeze

      attr_reader :player, :art_cache

      def initialize(player, art_cache: ArtCache.new)
        @player = player
        @art_cache = art_cache
        # Identity, not equality: two tracks of the same file are still two
        # tracks as far as a client following the playlist is concerned.
        @track_ids = {}.compare_by_identity
        @next_track_id = 0
        @callbacks = {}
      end

      # Raise and Quit are the window's business, not the player's.
      def on_raise(&block)
        @callbacks[:raise] = block
      end

      def on_quit(&block)
        @callbacks[:quit] = block
      end

      # --- Methods -----------------------------------------------------------

      def invoke(interface, member, arguments = [])
        case interface
        when ROOT_INTERFACE then invoke_root(member)
        when PLAYER_INTERFACE then invoke_player(member, arguments)
        else raise UnknownMember, "unknown interface #{interface}"
        end
      end

      # --- Properties --------------------------------------------------------

      def signature(interface, name)
        SIGNATURES.dig(interface, name)
      end

      def property(interface, name)
        unless signature(interface, name)
          raise UnknownMember, "unknown property #{interface}.#{name}"
        end

        case interface
        when ROOT_INTERFACE then root_property(name)
        else player_property(name)
        end
      end

      def properties(interface, names = nil)
        names ||= SIGNATURES.fetch(interface, {}).keys
        names.to_h { |name| [name, property(interface, name)] }
      end

      def writable?(interface, name)
        interface == PLAYER_INTERFACE && %w[LoopStatus Rate Shuffle Volume].include?(name)
      end

      # Writing an unsupported value is not an error in MPRIS; the player is
      # expected to ignore it and leave the property as it was.
      def set_property(interface, name, value)
        return false unless writable?(interface, name)

        case name
        when 'LoopStatus' then apply_loop_status(value)
        when 'Shuffle' then @player.shuffle = value
        when 'Volume' then apply_volume(value)
        when 'Rate' then nil # single rate supported; silently ignored
        end

        true
      end

      # --- Metadata ----------------------------------------------------------

      def metadata(track = @player.current_track)
        return { 'mpris:trackid' => ['o', NO_TRACK] } unless track

        {
          'mpris:trackid' => ['o', track_id(track)],
          'mpris:length' => ['x', length_of(track)],
          'mpris:artUrl' => ['s', @art_cache.url_for(track)],
          'xesam:url' => ['s', FileUri.for(track.file_path)],
          'xesam:title' => ['s', track.title || track.to_s],
          'xesam:album' => ['s', track.album],
          'xesam:artist' => ['as', list(track.artist)],
          'xesam:albumArtist' => ['as', list(track.album_artist)],
          'xesam:genre' => ['as', list(track.genre)],
          'xesam:composer' => ['as', list(track.composer)],
          'xesam:comment' => ['as', list(track.comment)],
          'xesam:trackNumber' => ['i', track.track_number],
          'xesam:discNumber' => ['i', track.disc_number],
          'xesam:contentCreated' => ['s', track.year && format('%04d-01-01T00:00:00Z', track.year)],
        }
      end

      # A track needs a stable object path for as long as it is the one
      # playing, and a different one once it is not, so clients can tell that
      # the track actually changed.
      def track_id(track)
        return NO_TRACK unless track

        @track_ids[track] ||= begin
          @next_track_id += 1
          "#{TRACK_PATH_PREFIX}#{@next_track_id}"
        end
      end

      def position_microseconds
        Mpris.seconds_to_microseconds(@player.position)
      end

      private

      def invoke_root(member)
        case member
        when 'Raise' then @callbacks[:raise]&.call
        when 'Quit' then @callbacks[:quit]&.call
        else raise UnknownMember, "unknown method #{ROOT_INTERFACE}.#{member}"
        end
      end

      def invoke_player(member, arguments)
        case member
        when 'Play' then @player.play
        when 'Pause' then @player.pause
        when 'PlayPause' then @player.play_pause
        when 'Stop' then @player.stop
        when 'Next' then @player.next_track
        when 'Previous' then @player.previous_track
        when 'Seek' then seek_by(arguments[0])
        when 'SetPosition' then set_position(arguments[0], arguments[1])
        when 'OpenUri' then open_uri(arguments[0])
        else raise UnknownMember, "unknown method #{PLAYER_INTERFACE}.#{member}"
        end
      end

      # Seek is relative, and running off the end of a track means the next
      # one rather than an error.
      def seek_by(offset_microseconds)
        return unless can_seek?

        target = @player.position + Mpris.microseconds_to_seconds(offset_microseconds)
        return @player.next_track if target > @player.duration

        @player.seek([target, 0.0].max)
      end

      def set_position(requested_id, position_microseconds)
        return unless can_seek?
        return unless requested_id.to_s == track_id(@player.current_track)

        seconds = Mpris.microseconds_to_seconds(position_microseconds)
        return if seconds.negative? || seconds > @player.duration

        @player.seek(seconds)
      end

      def open_uri(uri)
        path = FileUri.to_path(uri)
        return unless path && File.file?(path)

        playlist = @player.playlist
        playlist.add_track(path)
        playlist.set_current_track(playlist.size - 1)
        @player.play
      end

      def root_property(name)
        case name
        when 'CanQuit' then ['b', true]
        when 'CanRaise' then ['b', !@callbacks[:raise].nil?]
        when 'HasTrackList' then ['b', false]
        when 'Identity' then ['s', IDENTITY]
        when 'DesktopEntry' then ['s', DESKTOP_ENTRY]
        when 'SupportedUriSchemes' then ['as', URI_SCHEMES]
        when 'SupportedMimeTypes' then ['as', MIME_TYPES]
        end
      end

      def player_property(name)
        case name
        when 'PlaybackStatus' then ['s', PLAYBACK_STATUS.fetch(@player.state, 'Stopped')]
        when 'LoopStatus' then ['s', LOOP_STATUS.fetch(@player.repeat_mode, 'None')]
        when 'Rate', 'MinimumRate', 'MaximumRate' then ['d', 1.0]
        when 'Shuffle' then ['b', @player.shuffle?]
        when 'Metadata' then [Variant::DICTIONARY, metadata]
        when 'Volume' then ['d', @player.volume / 100.0]
        when 'Position' then ['x', position_microseconds]
        else capability(name)
        end
      end

      def capability(name)
        case name
        when 'CanGoNext' then ['b', step_available?(:next_index)]
        when 'CanGoPrevious' then ['b', step_available?(:previous_index)]
        when 'CanPlay' then ['b', !@player.playlist.empty?]
        when 'CanSeek' then ['b', can_seek?]
        when 'CanPause', 'CanControl' then ['b', true]
        end
      end

      def step_available?(query)
        playlist = @player.playlist
        return false if playlist.empty?

        !playlist.public_send(query, wrap: @player.repeat_mode == :all).nil?
      end

      def can_seek?
        !@player.stopped? && @player.duration.positive?
      end

      def apply_loop_status(value)
        mode = REPEAT_MODE[value.to_s]
        @player.repeat_mode = mode if mode
      end

      def apply_volume(value)
        @player.volume = (value.to_f.clamp(0.0, 1.0) * 100).round
      end

      def length_of(track)
        seconds = @player.current_track.equal?(track) ? @player.duration : track.duration.to_f
        seconds.positive? ? Mpris.seconds_to_microseconds(seconds) : nil
      end

      # Tags hold one string; MPRIS wants a list, and an empty one is better
      # expressed by leaving the key out altogether.
      def list(value)
        text = value.to_s.strip
        text.empty? ? nil : [text]
      end
    end
  end
end
