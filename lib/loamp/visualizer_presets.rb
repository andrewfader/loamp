# frozen_string_literal: true

module Loamp
  # The preset list behind projectM-style visualizers.
  #
  # GStreamer's projectm element takes one preset at a time through a string
  # property, so cycling is ours to do: find the `.milk` files installed on the
  # system, keep a cursor into that list, and hand the element a new path each
  # time the cursor moves. Elements without a preset property (goom and friends)
  # report `available?` as false and every move is a no-op.
  #
  # The projectm element only reads its preset property when it starts up, so
  # the owner passes a `restart` hook that bounces a running visualizer. Without
  # one the new preset appears the next time the visualizer is started.
  class VisualizerPresets
    EXTENSIONS = %w[milk prjm].freeze
    PROPERTIES = %w[preset preset-path preset-file].freeze
    ENVIRONMENT_VARIABLES = %w[LOAMP_PROJECTM_PRESETS PROJECTM_PRESET_PATH].freeze
    DATA_SUBDIRECTORIES = ['projectM/presets', 'projectm/presets', 'projectM'].freeze

    attr_reader :index

    def initialize(element = nil, search_paths: nil, restart: nil)
      @search_paths = search_paths
      @restart = restart
      @index = 0
      self.element = element
    end

    def element=(element)
      @element = element
      @property = element && PROPERTIES.find { |name| property?(element, name) }
    end

    # Preset files are only looked for when something asks, so building a
    # Visualizer stays as cheap as a factory lookup.
    def paths
      @paths ||= self.class.discover(@search_paths || self.class.search_paths)
    end

    def available? = !@property.nil? && !paths.empty?
    def count = paths.size
    def current = paths[@index]
    def current_name = current && File.basename(current, '.*')

    def next_preset = move(1)
    def previous_preset = move(-1)

    def random_preset
      return nil unless available?

      @index = rand(count)
      apply
    end

    # Jump straight to a preset by list position, wrapping like the arrows do.
    def select(position)
      return nil unless available?

      @index = position.to_i % count
      apply
    end

    def self.search_paths
      roots = ([data_home] + data_dirs).compact
      environment_paths +
        roots.product(DATA_SUBDIRECTORIES).map { |root, sub| File.join(root, sub) } +
        [home_path('.projectM/presets'), home_path('.projectM')].compact
    end

    def self.discover(search_paths)
      pattern = "*.{#{EXTENSIONS.join(',')}}"
      search_paths.uniq.flat_map do |path|
        if File.file?(path)
          [path]
        else
          Dir.glob(File.join(path, '**', pattern))
        end
      end.uniq
    rescue SystemCallError
      []
    end

    def self.environment_paths
      ENVIRONMENT_VARIABLES.filter_map { |name| ENV.fetch(name, nil) }
        .flat_map { |value| value.split(File::PATH_SEPARATOR) }
        .reject(&:empty?)
    end

    def self.data_home = ENV.fetch('XDG_DATA_HOME', home_path('.local/share'))

    def self.data_dirs
      ENV.fetch('XDG_DATA_DIRS', '/usr/local/share:/usr/share').split(File::PATH_SEPARATOR)
    end

    def self.home_path(relative)
      File.join(Dir.home, relative)
    rescue ArgumentError
      nil
    end

    private

    def move(step)
      return nil unless available?

      @index = (@index + step) % count
      apply
    end

    def apply
      @element.set_property(@property, current)
      @restart&.call
      current_name
    rescue StandardError
      nil
    end

    def property?(element, name)
      element.class.properties.include?(name)
    rescue StandardError
      false
    end
  end

  # Preset cycling as an engine sees it. Both engines own a visualizer in a
  # different shape, so they supply `visualizer_presets` and share the rest.
  module VisualizerPresetControls
    def visualizer_presets? = visualizer_presets&.available? == true
    def visualizer_preset_count = visualizer_presets&.count.to_i
    def current_visualizer_preset = visualizer_presets&.current_name
    def next_visualizer_preset = visualizer_presets&.next_preset
    def previous_visualizer_preset = visualizer_presets&.previous_preset
    def random_visualizer_preset = visualizer_presets&.random_preset
  end
end
