# frozen_string_literal: true

require 'gst'

module Loamp
  # Two playbin decoders bridged into one audiomixer. The next stream is
  # prerollled, then both run while their gains cross over.
  class CrossfadeEngine
    include VisualizerPresetControls

    NANOS_PER_SECOND = 1_000_000_000.0
    SEEK_FLAGS = Gst::SeekFlags::FLUSH | Gst::SeekFlags::ACCURATE

    attr_reader :uri, :volume, :crossfade_seconds, :replaygain_mode, :eq_preset, :visualizer_name

    def initialize(crossfade_seconds:, audio_sink: 'autoaudiosink', settings: PlaybackSettings.new)
      @crossfade_seconds = crossfade_seconds.to_f.clamp(0.1, 12)
      @settings = settings
      @players = Array.new(2) { |index| build_player(index) }
      @buses = @players.map(&:bus)
      @mixer = build_mixer(audio_sink)
      @fade_elements = Array.new(2) { |index| @mixer.get_by_name("loamp-fade-#{index}") }
      @visualizer_sink = @mixer.get_by_name('loamp-crossfade-visualizer')
      @visualizer_valve = @mixer.get_by_name('loamp-crossfade-visualizer-valve')
      @visualizer_element = @mixer.get_by_name('loamp-crossfade-visualizer-plugin')
      @active = 0
      @volume = 100
      @callbacks = Hash.new { |_hash, _key| ->(*) {} }
      @uri = nil
      self.replaygain_mode = settings.replaygain_mode
      self.eq_preset = settings.eq_preset
    end

    %i[end_of_stream error about_to_finish state_changed stream_start
       stream_metadata].each do |event|
      define_method("on_#{event}") { |&block| @callbacks[event] = block }
    end

    def load(location)
      stop
      @uri = FileUri.for(location)
      @players[@active].set_property('uri', @uri)
      @queued = false
      @requested_next = false
      @uri
    end

    def queue_next(location)
      return unless location

      @next_uri = FileUri.for(location)
      inactive.set_property('uri', @next_uri)
      inactive.set_state(Gst::State::PAUSED)
      @queued = true
      @next_uri
    end

    def play
      return unless @uri

      @mixer.set_state(Gst::State::PLAYING)
      current.set_state(Gst::State::PLAYING)
      @callbacks[:state_changed].call(:playing)
    end

    def pause
      current.set_state(Gst::State::PAUSED)
      inactive.set_state(Gst::State::PAUSED) if @fading
      @callbacks[:state_changed].call(:paused)
    end

    def stop
      @players&.each { |player| player.set_state(Gst::State::NULL) }
      @mixer&.set_state(Gst::State::NULL)
      @fading = false
      @callbacks&.[](:state_changed)&.call(:stopped)
    end

    def shutdown
      stop
      @players.clear
      @buses.clear
      @mixer = nil
    end

    def state
      return :stopped unless current

      case current.get_state(0)[1]
      when Gst::State::PLAYING then :playing
      when Gst::State::PAUSED then :paused
      else :stopped
      end
    end

    def playing? = state == :playing
    def paused? = state == :paused
    def stopped? = state == :stopped
    def position = query(current, :query_position)
    def duration = query(current, :query_duration)

    def seek(seconds)
      target = seconds.to_f.clamp(0, duration.positive? ? duration : Float::INFINITY)
      current.seek_simple(Gst::Format::TIME, SEEK_FLAGS, (target * NANOS_PER_SECOND).round)
    end

    def volume=(level)
      @volume = level.to_i.clamp(0, 100)
      apply_fade
    end

    def muted? = @muted == true

    def muted=(value)
      @muted = value == true
      apply_fade
    end

    def raw_volume = muted? ? 0.0 : master_gain

    def enable_visualizer
      return nil unless @visualizer_sink && @visualizer_valve

      @visualizer_valve.set_property('drop', false)
      @visualizer_sink.get_property('paintable')
    end

    def disable_visualizer
      @visualizer_valve&.set_property('drop', true)
    end

    def visualizer_presets
      @visualizer_presets ||= VisualizerPresets.new(@visualizer_element,
                                                    restart: method(:restart_visualizer))
    end


    def crossfade_seconds=(seconds)
      @crossfade_seconds = seconds.to_f.clamp(0.1, 12)
      @settings.crossfade_seconds = seconds
      @settings.save
    end

    def replaygain_mode=(mode)
      candidate = mode.to_sym
      return unless PlaybackSettings::REPLAYGAIN_MODES.include?(candidate)

      @replaygain_mode = candidate
      @players.each_with_index do |player, index|
        sink = player.get_property('audio-sink')
        selector = sink.get_by_name("loamp-crossfade-selector-#{index}")
        pad = selector.get_static_pad(candidate == :off ? 'sink_1' : 'sink_0')
        selector.set_property('active-pad', pad)
        element = sink.get_by_name("loamp-crossfade-rg-#{index}")
        element.set_property('album-mode', candidate == :album)
        element.set_property('headroom', 0.0)
      end
      save_settings
    end

    def eq_preset=(name)
      candidate = name.to_s.downcase.tr(' ', '_').to_sym
      gains = AudioEngine::EQ_PRESETS[candidate]
      return unless gains

      @eq_preset = candidate
      @players.each_with_index do |player, index|
        element = player.get_property('audio-sink').get_by_name("loamp-crossfade-eq-#{index}")
        gains.each_with_index { |gain, band| element.set_property("band#{band}", gain.to_f) }
      end
      save_settings
    end

    def pump
      drain_buses
      request_next_if_needed
      start_fade if @queued && !@fading && remaining <= @crossfade_seconds
      update_fade if @fading
    end

    private

    # The projectm element reads its preset at start-up, so a new one needs the
    # element bounced. The valve is shut first: with nothing flowing into it the
    # branch can go back to NULL and up again without disturbing playback.
    def restart_visualizer
      return false unless @visualizer_element && @visualizer_valve
      return false if @visualizer_valve.get_property('drop')

      @visualizer_valve.set_property('drop', true)
      @visualizer_element.set_state(Gst::State::NULL)
      @visualizer_element.sync_state_with_parent
      @visualizer_valve.set_property('drop', false)
      true
    rescue StandardError
      false
    end

    def build_player(index)
      Gst::ElementFactory.make('playbin3', "loamp-crossfade-player-#{index}").tap do |player|
        description = <<~PIPELINE.split.join(' ')
          audioconvert ! tee name=loamp-crossfade-tee-#{index}
          loamp-crossfade-tee-#{index}. ! queue
            ! rgvolume name=loamp-crossfade-rg-#{index} ! rglimiter
            ! input-selector name=loamp-crossfade-selector-#{index}
          loamp-crossfade-tee-#{index}. ! queue ! loamp-crossfade-selector-#{index}.
          loamp-crossfade-selector-#{index}.
            ! equalizer-10bands name=loamp-crossfade-eq-#{index}
          ! audioconvert ! interaudiosink channel=loamp-#{index}
        PIPELINE
        sink = Gst.parse_bin_from_description(description, true)
        player.set_property('audio-sink', sink)
      end
    end

    def build_mixer(audio_sink)
      description = <<~PIPELINE
        interaudiosrc channel=loamp-0 ! volume name=loamp-fade-0 ! audiomixer name=mix
        interaudiosrc channel=loamp-1 ! volume name=loamp-fade-1 ! mix.
        mix. ! tee name=loamp-crossfade-output
        loamp-crossfade-output. ! queue ! audioconvert ! #{audio_sink}
      PIPELINE
      description += visualizer_branch
      Gst.parse_launch(description.split.join(' '))
    end

    def visualizer_branch
      @visualizer_name = Visualizer::CANDIDATES.find do |name|
        Gst::ElementFactory.find(name)
      end
      sink_available = Gst::ElementFactory.find('gtk4paintablesink')
      return '' unless @visualizer_name && sink_available

      <<~PIPELINE
        loamp-crossfade-output. ! queue ! valve name=loamp-crossfade-visualizer-valve drop=true
          ! audioconvert ! #{@visualizer_name} name=loamp-crossfade-visualizer-plugin ! videoconvert
          ! video/x-raw(memory:SystemMemory),format=RGBA
          ! gtk4paintablesink name=loamp-crossfade-visualizer sync=false
      PIPELINE
    rescue StandardError
      ''
    end

    def current = @players[@active]
    def inactive = @players[1 - @active]

    def remaining
      length = duration
      length.positive? ? length - position : Float::INFINITY
    end

    def request_next_if_needed
      return if @requested_next || remaining > @crossfade_seconds + 2

      @requested_next = true
      @callbacks[:about_to_finish].call
    end

    def start_fade
      @fading = true
      @fade_started = monotonic_now
      inactive.set_state(Gst::State::PLAYING)
      @callbacks[:stream_start].call
      apply_fade
    end

    def update_fade
      finish_fade if fade_progress >= 1
      apply_fade
    end

    def finish_fade
      current.set_state(Gst::State::NULL)
      @active = 1 - @active
      @uri = @next_uri
      @next_uri = nil
      @queued = false
      @fading = false
      @requested_next = false
    end

    def fade_progress
      return 0 unless @fading

      ((monotonic_now - @fade_started) / @crossfade_seconds).clamp(0, 1)
    end

    def apply_fade
      master = muted? ? 0.0 : master_gain
      progress = fade_progress
      @fade_elements[@active]&.set_property('volume', master * (1 - progress))
      @fade_elements[1 - @active]&.set_property('volume', master * progress)
    end

    def master_gain = (@volume / 100.0)**3

    def save_settings
      return unless @settings

      @settings.replaygain_mode = @replaygain_mode if @replaygain_mode
      @settings.eq_preset = @eq_preset if @eq_preset
      @settings.save
    end

    def drain_buses
      @buses.each_with_index do |bus, index|
        while (message = bus.pop)
          handle_message(message, index)
        end
      end
    end

    def handle_message(message, index)
      case message.type
      when Gst::MessageType::EOS then handle_eos(index)
      when Gst::MessageType::ERROR then handle_error(message)
      when Gst::MessageType::TAG then handle_tags(message) if index == @active
      end
    end

    def handle_eos(index)
      return if @fading || index != @active

      stop
      @callbacks[:end_of_stream].call
    end

    def handle_error(message)
      error, = message.parse_error
      stop
      @callbacks[:error].call(error.respond_to?(:message) ? error.message : error.to_s)
    end

    def handle_tags(message)
      tags = message.parse_tag
      metadata = %w[title artist album].to_h do |name|
        [name.to_sym, tags.get_value_index(name, 0).to_s.strip]
      rescue StandardError
        [name.to_sym, nil]
      end.compact
      @callbacks[:stream_metadata].call(metadata) unless metadata.empty?
    end

    def query(player, method)
      ok, nanos = player.public_send(method, Gst::Format::TIME)
      ok && nanos && nanos >= 0 ? nanos / NANOS_PER_SECOND : 0.0
    rescue StandardError
      0.0
    end

    def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
