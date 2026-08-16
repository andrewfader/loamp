# frozen_string_literal: true

require 'gst'

module Loamp
  # Audio playback backed by a real GStreamer pipeline.
  #
  # Everything the player needs from the audio layer lives here: accurate
  # position and duration queries, flushing seeks, perceptual volume, and
  # notifications for end-of-stream, errors, and the gapless hand-off point.
  #
  # Bus messages are drained by #pump rather than a bus watch, so the engine
  # works identically inside the GTK main loop and in a bare test process.
  class AudioEngine
    include VisualizerPresetControls

    # GStreamer works in nanoseconds; the rest of the app works in seconds.
    NANOS_PER_SECOND = 1_000_000_000.0

    SEEK_FLAGS = Gst::SeekFlags::FLUSH | Gst::SeekFlags::ACCURATE

    FILTER_SINK = <<~PIPELINE.split.join(' ').freeze
      audioconvert ! tee name=loamp-rg-tee
      loamp-rg-tee. ! queue ! rgvolume name=loamp-replaygain ! rglimiter
        ! input-selector name=loamp-rg-selector
      loamp-rg-tee. ! queue ! loamp-rg-selector.
      loamp-rg-selector. ! equalizer-10bands name=loamp-equalizer
        ! audioconvert ! autoaudiosink
    PIPELINE

    EQ_PRESETS = {
      flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      classical: [0, 0, 0, 0, 0, 0, -4, -4, -4, -6],
      club: [0, 0, 4, 3, 3, 3, 2, 0, 0, 0],
      dance: [5, 4, 1, 0, 0, -3, -4, -4, 0, 0],
      pop: [-1, 2, 4, 4, 1, -1, -1, -1, -1, -1],
      rock: [4, 2, -2, -4, -2, 2, 4, 5, 5, 5],
      bass: [6, 5, 4, 2, 0, -1, -2, -3, -3, -3],
      treble: [-3, -3, -3, -1, 1, 3, 5, 6, 6, 6],
    }.freeze

    attr_reader :uri, :volume, :replaygain_mode, :eq_preset

    def initialize(audio_sink: nil, settings: PlaybackSettings.new)
      # Requiring 'gst' initializes GStreamer; an explicit Gst.init is neither
      # needed nor callable from ruby-gnome.
      @pipeline = Gst::ElementFactory.make('playbin3', 'loamp-playbin')
      raise 'GStreamer playbin3 element is unavailable' unless @pipeline

      @bus = @pipeline.bus
      @uri = nil
      @volume = 100
      @callbacks = Hash.new { |_hash, _key| ->(*) {} }
      @errors_seen = 0
      @end_of_stream_count = 0
      @stream_start_count = 0
      @settings = settings

      attach_audio_sink(audio_sink || FILTER_SINK)
      self.replaygain_mode = @settings.replaygain_mode
      self.eq_preset = @settings.eq_preset
      connect_about_to_finish
      apply_volume
    end

    # --- Callback registration -------------------------------------------

    def on_end_of_stream(&block)
      @callbacks[:end_of_stream] = block
    end

    def on_error(&block)
      @callbacks[:error] = block
    end

    def on_about_to_finish(&block)
      @callbacks[:about_to_finish] = block
    end

    def on_state_changed(&block)
      @callbacks[:state_changed] = block
    end

    # Fires when a stream actually begins playing. With gapless hand-off the
    # next track is queued well before it starts, so this is the moment the
    # rest of the app should consider the track changed.
    def on_stream_start(&block)
      @callbacks[:stream_start] = block
    end

    # Live streams use ICY/GStreamer tags to change the displayed song without
    # changing URI. The callback receives a small symbol-keyed metadata hash.
    def on_stream_metadata(&block)
      @callbacks[:stream_metadata] = block
    end

    # --- Transport --------------------------------------------------------

    def load(location)
      stop
      @uri = to_uri(location)
      @pipeline.set_property('uri', @uri)
      @uri
    end

    # Hands the next track to playbin during about-to-finish so the pipeline
    # never tears down between tracks. This is what makes playback gapless.
    def queue_next(location)
      return nil unless location

      @uri = to_uri(location)
      @pipeline.set_property('uri', @uri)
      @uri
    end

    def play
      return unless @uri

      change_state(Gst::State::PLAYING)
    end

    def pause
      return unless playing?

      change_state(Gst::State::PAUSED)
    end

    def stop
      change_state(Gst::State::NULL)
    end

    def seek(seconds)
      return unless @uri && !stopped?

      target = [seconds.to_f, 0.0].max
      target = [target, duration].min if duration.positive?

      @pipeline.seek_simple(Gst::Format::TIME, SEEK_FLAGS, (target * NANOS_PER_SECOND).round)
      settle
    end

    # Disconnecting before dropping the pipeline matters: about-to-finish is
    # emitted from GStreamer's streaming thread, and letting it fire into a
    # torn-down engine is a segfault rather than an exception.
    def shutdown
      stop
      @pipeline&.signal_handler_disconnect(@about_to_finish_id) if @about_to_finish_id
      @about_to_finish_id = nil
      @pipeline = nil
      @bus = nil
    end

    # --- State ------------------------------------------------------------

    def state
      return :stopped unless @pipeline

      case @pipeline.get_state(0)[1]
      when Gst::State::PLAYING then :playing
      when Gst::State::PAUSED then :paused
      else :stopped
      end
    end

    def playing? = state == :playing
    def paused? = state == :paused
    def stopped? = state == :stopped

    def position
      query_time(:query_position)
    end

    def duration
      query_time(:query_duration)
    end

    # --- Volume -----------------------------------------------------------

    def volume=(level)
      @volume = level.to_i.clamp(0, 100)
      apply_volume
      @volume
    end

    # The linear amplitude actually handed to GStreamer, exposed for testing
    # and for anything that needs the underlying scale.
    def raw_volume
      @pipeline ? @pipeline.get_property('volume') : 0.0
    end

    def enable_visualizer
      @visualizer ||= Visualizer.new
      return nil unless @pipeline && @visualizer.attach(@pipeline)

      @visualizer.paintable
    end

    def disable_visualizer
      @visualizer&.detach(@pipeline)
    end

    def visualizer_name = (@visualizer ||= Visualizer.new).name
    def visualizer_presets = (@visualizer ||= Visualizer.new).presets

    def muted?
      @pipeline ? @pipeline.get_property('mute') : false
    end

    def muted=(value)
      @pipeline&.set_property('mute', value ? true : false)
      value
    end

    # --- Playback processing ---------------------------------------------

    def replaygain_mode=(mode)
      candidate = mode.to_sym
      return unless PlaybackSettings::REPLAYGAIN_MODES.include?(candidate)

      @replaygain_mode = candidate
      if @replaygain_selector
        pad = @replaygain_selector.get_static_pad(candidate == :off ? 'sink_1' : 'sink_0')
        @replaygain_selector.set_property('active-pad', pad) if pad
      end
      @replaygain&.set_property('album-mode', candidate == :album)
      @replaygain&.set_property('fallback-gain', 0.0)
      @replaygain&.set_property('headroom', 0.0)
      persist_processing_settings
    end

    def eq_preset=(name)
      candidate = name.to_s.downcase.tr(' ', '_').to_sym
      gains = EQ_PRESETS[candidate]
      return unless gains

      @eq_preset = candidate
      gains.each_with_index { |gain, index| @equalizer&.set_property("band#{index}", gain.to_f) }
      persist_processing_settings
    end

    def crossfade_seconds = @settings.crossfade_seconds

    def crossfade_seconds=(seconds)
      @settings.crossfade_seconds = seconds
      @settings.save
    end

    # --- Bus draining ------------------------------------------------------

    # Processes every pending bus message. Safe to call as often as you like;
    # the GTK app calls it on a timer, tests call it directly.
    def pump
      return unless @bus

      while (message = @bus.pop)
        handle_message(message)
      end
    end

    def wait_for_state(target, timeout: 5)
      wait_until(timeout) { state == target }
    end

    def wait_for_end_of_stream(timeout: 10)
      seen = @end_of_stream_count
      wait_until(timeout) { @end_of_stream_count > seen }
    end

    def wait_for_error(timeout: 5)
      seen = @errors_seen
      wait_until(timeout) { @errors_seen > seen }
    end

    def wait_until_stream_starts(count: 1, timeout: 10)
      wait_until(timeout) { @stream_start_count >= count }
    end

    private

    def handle_message(message)
      case message.type
      when Gst::MessageType::EOS then handle_end_of_stream
      when Gst::MessageType::ERROR then handle_error(message)
      when Gst::MessageType::STATE_CHANGED then handle_state_changed(message)
      when Gst::MessageType::STREAM_START then handle_stream_start
      when Gst::MessageType::TAG then handle_tags(message)
      end
    end

    def handle_tags(message)
      tags = message.parse_tag
      metadata = {
        title: tag_value(tags, 'title'),
        artist: tag_value(tags, 'artist'),
        album: tag_value(tags, 'album'),
      }.compact
      @callbacks[:stream_metadata].call(metadata) unless metadata.empty?
    rescue StandardError
      nil
    end

    def tag_value(tags, name)
      value = tags.get_value_index(name, 0)
      text = value.to_s.strip
      text unless text.empty?
    rescue StandardError
      nil
    end

    def handle_stream_start
      @stream_start_count += 1
      @callbacks[:stream_start].call
    end

    def handle_end_of_stream
      @end_of_stream_count += 1
      stop
      @callbacks[:end_of_stream].call
    end

    def handle_error(message)
      error, debug = message.parse_error
      @errors_seen += 1
      stop
      @callbacks[:error].call(describe_error(error, debug))
    end

    # Only the pipeline's own transitions matter; child elements are noisy.
    def handle_state_changed(message)
      return unless message.src == @pipeline

      @callbacks[:state_changed].call(state)
    end

    def describe_error(error, debug)
      message = error.respond_to?(:message) ? error.message.to_s : error.to_s
      message = debug.to_s if message.empty?
      message.empty? ? 'Unknown playback error' : message
    end

    def change_state(gst_state)
      return unless @pipeline

      @pipeline.set_state(gst_state)
    end

    def query_time(query)
      return 0.0 unless @pipeline && @uri

      ok, nanoseconds = @pipeline.public_send(query, Gst::Format::TIME)
      return 0.0 unless ok && nanoseconds && nanoseconds >= 0

      nanoseconds / NANOS_PER_SECOND
    end

    # GStreamer's volume property is linear amplitude, which feels wrong to a
    # human ear. Cubic scaling is the curve GstStreamVolume uses for sliders.
    def apply_volume
      @pipeline&.set_property('volume', (@volume / 100.0)**3)
    end

    def attach_audio_sink(description)
      sink = build_sink(description)
      return unless sink

      @pipeline.set_property('audio-sink', sink)
      @replaygain = sink.get_by_name('loamp-replaygain') if sink.respond_to?(:get_by_name)
      @replaygain_selector = sink.get_by_name('loamp-rg-selector') if sink.respond_to?(:get_by_name)
      @equalizer = sink.get_by_name('loamp-equalizer') if sink.respond_to?(:get_by_name)
    end

    def persist_processing_settings
      return unless @settings

      @settings.replaygain_mode = @replaygain_mode if @replaygain_mode
      @settings.eq_preset = @eq_preset if @eq_preset
      @settings.save
    end

    def build_sink(description)
      return description if description.is_a?(Gst::Element)

      if description.to_s.include?(' ')
        Gst.parse_bin_from_description(description.to_s, true)
      else
        Gst::ElementFactory.make(description.to_s, 'loamp-audio-sink')
      end
    rescue StandardError
      nil
    end

    def connect_about_to_finish
      @about_to_finish_id = @pipeline.signal_connect('about-to-finish') do
        @callbacks&.[](:about_to_finish)&.call
      end
    end

    # A flushing seek completes asynchronously; waiting for the pipeline to
    # settle means the next position query reflects the seek.
    def settle
      @pipeline&.get_state(Gst::SECOND)
    end

    def to_uri(location)
      FileUri.for(location)
    end

    def wait_until(timeout)
      deadline = monotonic_now + timeout

      while monotonic_now < deadline
        pump
        return true if yield

        sleep 0.02
      end

      pump
      yield
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
