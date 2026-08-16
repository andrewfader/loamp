# frozen_string_literal: true

module Loamp
  class Visualizer
    PLAY_FLAG_VIS = 1 << 3
    CANDIDATES = %w[projectm goom goom2k1].freeze

    attr_reader :name, :paintable

    def initialize
      @name = CANDIDATES.find { |candidate| factory?(candidate) }
      @sink_available = factory?('gtk4paintablesink')
    rescue StandardError
      @name = nil
      @sink_available = false
    end

    def available? = !@name.nil? && @sink_available

    # The preset cursor follows the plugin element, which only exists once one
    # has been built; building it early costs a factory call and nothing else.
    def presets
      @presets ||= VisualizerPresets.new(plugin, restart: method(:restart))
    end

    # projectM loads its preset when the element starts, so a preset picked
    # mid-track only shows up once the visualization chain is rebuilt. Dropping
    # and restoring the vis flag is the same path the Start/Stop button takes.
    def restart
      return false unless @playbin

      flags = @playbin.get_property('flags').to_i
      return false unless flags.anybits?(PLAY_FLAG_VIS)

      @playbin.set_property('flags', flags & ~PLAY_FLAG_VIS)
      @playbin.set_property('flags', flags)
      true
    rescue StandardError
      false
    end

    def attach(playbin)
      return false unless available?

      @playbin = playbin
      @plugin ||= build(@name)
      presets.element = @plugin
      @video_sink ||= Gst.parse_bin_from_description(
        'videoconvert ! video/x-raw(memory:SystemMemory),format=RGBA ! ' \
        'gtk4paintablesink name=loamp-visualizer-sink',
        true,
      )
      @sink ||= @video_sink&.get_by_name('loamp-visualizer-sink')
      return false unless @plugin && @video_sink && @sink

      playbin.set_property('vis-plugin', @plugin)
      playbin.set_property('video-sink', @video_sink)
      flags = playbin.get_property('flags').to_i
      playbin.set_property('flags', flags | PLAY_FLAG_VIS)
      @paintable = @sink.get_property('paintable')
      true
    rescue StandardError
      false
    end

    def detach(playbin)
      flags = playbin.get_property('flags').to_i
      playbin.set_property('flags', flags & ~PLAY_FLAG_VIS)
      true
    rescue StandardError
      false
    end

    private

    def plugin
      return nil unless @name

      @plugin ||= build(@name)
    end

    def build(name)
      Gst::ElementFactory.make(name, "loamp-#{name}")
    rescue StandardError
      nil
    end

    def factory?(name) = !Gst::ElementFactory.find(name).nil?
  end
end
