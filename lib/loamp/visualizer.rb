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

    def attach(playbin)
      return false unless available?

      @plugin ||= build(@name)
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

    def build(name)
      Gst::ElementFactory.make(name, "loamp-#{name}")
    rescue StandardError
      nil
    end

    def factory?(name) = !Gst::ElementFactory.find(name).nil?
  end
end
