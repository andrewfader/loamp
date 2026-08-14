# frozen_string_literal: true

module Loamp
  # Playback control: owns the play order and drives the audio engine.
  #
  # The engine knows how to make sound; the player knows what should sound
  # next. Track advancement happens through the engine's gapless hand-off, so
  # one track flows into the next without the pipeline tearing down.
  class Player
    STATES = %i[stopped playing paused].freeze
    REPEAT_MODES = %i[off all one].freeze

    # Pressing previous late in a track restarts it, the way every jukebox
    # since the CD player has behaved.
    REWIND_THRESHOLD_SECONDS = 3

    attr_reader :playlist, :engine, :repeat_mode

    def initialize(playlist, engine: AudioEngine.new)
      @playlist = playlist
      @engine = engine
      @repeat_mode = :off
      @shuffle = false
      @pending_index = nil
      @callbacks = Hash.new { |hash, key| hash[key] = [] }

      connect_engine
    end

    # --- Callback registration -------------------------------------------
    #
    # Every registration is kept: the window, the transport controls, the
    # playlist and the MPRIS service all watch the same player, so a later
    # listener must not silently displace an earlier one.

    def on_state_changed(&block)
      @callbacks[:state_changed] << block
    end

    def on_position_changed(&block)
      @callbacks[:position_changed] << block
    end

    def on_track_changed(&block)
      @callbacks[:track_changed] << block
    end

    def on_error(&block)
      @callbacks[:error] << block
    end

    # A deliberate jump in the timeline, as opposed to the steady advance
    # reported by on_position_changed. MPRIS needs the distinction.
    def on_seeked(&block)
      @callbacks[:seeked] << block
    end

    def on_volume_changed(&block)
      @callbacks[:volume_changed] << block
    end

    def on_stream_metadata(&block)
      @callbacks[:stream_metadata] << block
    end

    # --- Transport --------------------------------------------------------

    def play
      return if playing?
      return resume if paused?

      start(current_track)
    end

    def pause
      @engine.pause if playing?
    end

    def stop
      @pending_index = nil
      @engine.stop
    end

    def play_pause
      playing? ? pause : play
    end

    def next_track
      advance_to(@playlist.next_index(wrap: repeat_all?))
    end

    def previous_track
      return seek(0) if restart_instead_of_skipping?

      advance_to(@playlist.previous_index(wrap: repeat_all?))
    end

    def seek(position)
      result = @engine.seek(position)
      publish(:seeked, @engine.position)
      result
    end

    # --- State ------------------------------------------------------------

    def state = @engine.state
    def playing? = @engine.playing?
    def paused? = @engine.paused?
    def stopped? = @engine.stopped?
    def position = @engine.position
    def current_track = @playlist.current_track

    # Prefer what the decoder reports, falling back to the tagged duration for
    # tracks that have not started playing yet.
    def duration
      live = @engine.duration
      live.positive? ? live : current_track&.duration.to_f
    end

    def repeat_mode=(mode)
      @repeat_mode = mode if REPEAT_MODES.include?(mode)
    end

    def shuffle?
      @shuffle
    end

    def shuffle=(enabled)
      @shuffle = ![nil, false, 0].include?(enabled)
      @shuffle ? @playlist.enable_shuffle : @playlist.disable_shuffle
    end

    # --- Volume -----------------------------------------------------------

    def volume = @engine.volume
    def muted? = @engine.muted?
    def set_volume(level) = (self.volume = level)

    def volume=(level)
      @engine.volume = level
      publish(:volume_changed, @engine.volume)
      level
    end

    def muted=(value)
      @engine.muted = value
      publish(:volume_changed, @engine.volume)
      value
    end

    def replaygain_mode = @engine.replaygain_mode

    def replaygain_mode=(mode)
      @engine.replaygain_mode = mode
    end

    def eq_preset = @engine.eq_preset

    def eq_preset=(preset)
      @engine.eq_preset = preset
    end

    def crossfade_seconds = @engine.crossfade_seconds

    def crossfade_seconds=(seconds)
      @engine.crossfade_seconds = seconds
    end

    # --- Notifications ----------------------------------------------------
    #
    # Push the current values out to listeners. A component that attaches after
    # playback has already started uses these to sync itself up.

    def notify_state_changed(new_state = state)
      publish(:state_changed, new_state)
    end

    def notify_position_changed(new_position = position, new_duration = duration)
      publish(:position_changed, new_position, new_duration)
    end

    def notify_track_changed(track = current_track)
      publish(:track_changed, track)
    end

    # Drives bus processing and position updates. The GTK app calls this on a
    # timer; tests call it directly.
    def tick
      @engine.pump
      publish(:position_changed, position, duration) if playing?
    end

    private

    # One listener raising must not stop the others from being told, or a
    # single broken observer takes the whole UI out of sync.
    def publish(event, *arguments)
      @callbacks[event].each do |callback|
        callback.call(*arguments)
      rescue StandardError => e
        warn "Loamp::Player #{event} listener failed: #{e.message}"
      end
    end

    def connect_engine
      @engine.on_state_changed { |state| publish(:state_changed, state) }
      @engine.on_error { |message| handle_error(message) }
      @engine.on_end_of_stream { publish(:state_changed, :stopped) }
      @engine.on_about_to_finish { queue_following_track }
      @engine.on_stream_start { commit_pending_track }
      @engine.on_stream_metadata { |metadata| publish(:stream_metadata, metadata) }
    end

    def start(track)
      return unless track

      @pending_index = nil
      @engine.load(track.file_path)
      @engine.play
      announce_track_change
    end

    def resume
      @engine.play
    end

    def advance_to(index)
      return stop unless index

      @playlist.set_current_track(index)
      start(current_track)
    end

    # Called from the engine's streaming thread as the current track runs out.
    # Keep it cheap: work out what follows and hand the URI over, then commit
    # the playlist cursor later when the track actually starts.
    def queue_following_track
      index = following_index
      return unless index

      track = @playlist[index]
      return unless track

      @pending_index = index
      @engine.queue_next(track.file_path)
    end

    def following_index
      return @playlist.current_index if @repeat_mode == :one

      @playlist.next_index(wrap: repeat_all?)
    end

    def commit_pending_track
      return unless @pending_index

      @playlist.set_current_track(@pending_index)
      @pending_index = nil
      announce_track_change
    end

    def announce_track_change
      publish(:track_changed, current_track)
    end

    def handle_error(message)
      @pending_index = nil
      publish(:error, message)
    end

    def repeat_all?
      @repeat_mode == :all
    end

    def restart_instead_of_skipping?
      !stopped? && position > REWIND_THRESHOLD_SECONDS
    end
  end
end
