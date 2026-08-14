# frozen_string_literal: true

require 'json'
require 'fileutils'

module Loamp
  # Small persistent playback preferences store. Invalid and older files fall
  # back field-by-field so adding a preference never makes LOAMP unstartable.
  class PlaybackSettings
    REPLAYGAIN_MODES = %i[off track album].freeze
    DEFAULTS = { replaygain_mode: :track, eq_preset: :flat, crossfade_seconds: 0.0 }.freeze

    attr_reader :path, :replaygain_mode, :eq_preset, :crossfade_seconds

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
        crossfade_seconds: @crossfade_seconds }
    end

    private

    def load
      fields = JSON.parse(File.read(@path), symbolize_names: true)
      self.replaygain_mode = fields.fetch(:replaygain_mode, DEFAULTS[:replaygain_mode])
      self.eq_preset = fields.fetch(:eq_preset, DEFAULTS[:eq_preset])
      self.crossfade_seconds = fields.fetch(:crossfade_seconds, DEFAULTS[:crossfade_seconds])
    rescue JSON::ParserError, SystemCallError, TypeError
      self.replaygain_mode = DEFAULTS[:replaygain_mode]
      self.eq_preset = DEFAULTS[:eq_preset]
      self.crossfade_seconds = DEFAULTS[:crossfade_seconds]
    end
  end
end
