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
      @consecutive_failures = 0
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

    # Shuffle or repeat changed, from any direction: the transport buttons,
    # a keyboard shortcut or an MPRIS client all need to agree afterwards.
    def on_options_changed(&block)
      @callbacks[:options_changed] << block
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

    # Starts the given queue entry from the top, whatever is playing now.
    # This is what activating a row means; #play alone would carry on with
    # the current track if one were already sounding.
    def play_index(index)
      return nil unless @playlist.set_current_track(index)

      start(current_track)
      current_track
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

      index = @playlist.previous_index(wrap: repeat_all?)
      # At the start of the first track, restart rather than stopping.
      return seek(0) unless index

      advance_to(index)
    end

    def seek(position)
      result = @engine.seek(position)
      now = @engine.position
      publish(:seeked, now)
      # A paused player gets no ticks, so the jump is reported here or the
      # readout stays where it was until playback resumes.
      publish(:position_changed, now, duration)
      result
    end

    # Lets go of the pipeline. Called once, when the application quits:
    # a GStreamer pipeline still running while Ruby tears itself down is a
    # crash at exit rather than a clean one.
    def shutdown
      @pending_index = nil
      @engine.shutdown if @engine.respond_to?(:shutdown)
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
      return unless REPEAT_MODES.include?(mode)

      @repeat_mode = mode
      publish(:options_changed)
    end

    def shuffle?
      @shuffle
    end

    def shuffle=(enabled)
      @shuffle = ![nil, false, 0].include?(enabled)
      @shuffle ? @playlist.enable_shuffle : @playlist.disable_shuffle
      publish(:options_changed)
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
    def publish(event, *)
      @callbacks[event].each do |callback|
        callback.call(*)
      rescue StandardError => e
        warn "Loamp::Player #{event} listener failed: #{e.message}"
      end
    end

    def connect_engine
      @engine.on_state_changed { |state| publish(:state_changed, state) }
      @engine.on_error { |message| handle_error(message) }
      # The engine announces its own return to stopped; nothing to add here.
      @engine.on_end_of_stream { @pending_index = nil }
      @engine.on_about_to_finish { queue_following_track }
      @engine.on_stream_start { stream_started }
      @engine.on_stream_metadata { |metadata| relay_stream_metadata(metadata) }
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

    def stream_started
      @consecutive_failures = 0
      commit_pending_track
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

    # A file that will not play is reported and then skipped, the way any
    # jukebox treats a scratched disc. One bad download must not end the
    # evening. Skipping stops once every entry has failed in a row, so a
    # queue of nothing but dead links does not spin forever.
    def handle_error(message)
      failed_index = @pending_index || @playlist.current_index
      @pending_index = nil
      publish(:error, message)
      skip_past_failure(failed_index)
    end

    def skip_past_failure(failed_index)
      return if @playlist.empty?

      @consecutive_failures += 1
      if @consecutive_failures >= @playlist.size
        @consecutive_failures = 0
        return
      end

      @playlist.set_current_track(failed_index)
      index = @playlist.next_index(wrap: repeat_all?)
      advance_to(index) if index
    end

    # Tags arriving on the pipeline only mean something for a live stream,
    # where they are the only way to learn what is playing. For a local file
    # they merely repeat what TagLib already read -- and with gapless
    # playback they arrive for the next track while this one is still
    # sounding, which put the wrong title on the pane for a second or two.
    def relay_stream_metadata(metadata)
      track = current_track
      return unless track.respond_to?(:remote?) && track.remote?

      publish(:stream_metadata, metadata)
    end

    def repeat_all?
      @repeat_mode == :all
    end

    def restart_instead_of_skipping?
      !stopped? && position > REWIND_THRESHOLD_SECONDS
    end
  end
end
