# frozen_string_literal: true

require 'json'
require 'fileutils'

module Loamp
  # Small persistent playback preferences store. Invalid and older files fall
  # back field-by-field so adding a preference never makes LOAMP unstartable.
  class PlaybackSettings
    REPLAYGAIN_MODES = %i[off track album].freeze
    REPEAT_MODES = %i[off all one].freeze
    DEFAULTS = { replaygain_mode: :track, eq_preset: :flat, crossfade_seconds: 0.0,
                 volume: 100, shuffle: false, repeat_mode: :off }.freeze

    attr_reader :path, :replaygain_mode, :eq_preset, :crossfade_seconds, :volume,
                :repeat_mode

    def initialize(path: self.class.default_path)
      @path = path
      load
    end

    def self.default_path
      root = ENV.fetch('XDG_CONFIG_HOME', File.join(Dir.home, '.config'))
      File.join(root, 'loamp', 'playback.json')
    end

    def replaygain_mode=(mode)
      candidate = mode.to_sym
      @replaygain_mode = if REPLAYGAIN_MODES.include?(candidate)
                           candidate
                         else
                           DEFAULTS[:replaygain_mode]
                         end
    end

    def eq_preset=(name)
      @eq_preset = name.to_s.strip.downcase.tr(' ', '_').to_sym
    end

    def crossfade_seconds=(seconds)
      @crossfade_seconds = seconds.to_f.clamp(0, 12)
    end

    # The listener's volume survives a restart: a player that comes back at
    # full blast every launch is a player that gets muted before it is used.
    def volume=(level)
      @volume = level.to_i.clamp(0, 100)
    end

    def shuffle? = @shuffle

    def shuffle=(enabled)
      @shuffle = enabled == true
    end

    def repeat_mode=(mode)
      candidate = mode.to_s.to_sym
      @repeat_mode = REPEAT_MODES.include?(candidate) ? candidate : DEFAULTS[:repeat_mode]
    end

    def save
      FileUtils.mkdir_p(File.dirname(@path))
      temporary = "#{@path}.#{Process.pid}.tmp"
      File.write(temporary, JSON.pretty_generate(to_h))
      File.rename(temporary, @path)
      true
    rescue SystemCallError, IOError
      false
    end

    def to_h
      { replaygain_mode: @replaygain_mode, eq_preset: @eq_preset,
        crossfade_seconds: @crossfade_seconds, volume: @volume,
        shuffle: @shuffle, repeat_mode: @repeat_mode }
    end

    private

    def load
      fields = JSON.parse(File.read(@path), symbolize_names: true)
      fields = {} unless fields.is_a?(Hash)
      apply(fields)
    rescue JSON::ParserError, SystemCallError, TypeError
      apply({})
    end

    def apply(fields)
      DEFAULTS.each do |name, default|
        public_send("#{name}=", fields.fetch(name, default))
      end
    end
  end
end
