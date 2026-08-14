# frozen_string_literal: true

require 'json'
require 'fileutils'

module Loamp
  module Radio
    class Store
      HISTORY_LIMIT = 100

      def initialize(path: self.class.default_path)
        @path = path
        @data = load_data
      end

      def self.default_path
        root = ENV.fetch('XDG_DATA_HOME', File.join(Dir.home, '.local', 'share'))
        File.join(root, 'loamp', 'radio.json')
      end

      def favorite(station)
        @data['favorites'].reject! { |known| known['id'] == station.id }
        @data['favorites'] << fields(station)
        save
      end

      def unfavorite(station)
        @data['favorites'].reject! { |known| known['id'] == station.id }
        save
      end

      def favorite?(station) = @data['favorites'].any? { |known| known['id'] == station.id }

      def favorites
        @data['favorites'].map { |known| Station.new(**known.transform_keys(&:to_sym)) }
      end

      def played(station)
        @data['history'].unshift(fields(station).merge('played_at' => Time.now.to_i))
        @data['history'] = @data['history'].first(HISTORY_LIMIT)
        save
      end

      def history
        @data['history'].map do |known|
          Station.new(**known.except('played_at').transform_keys(&:to_sym))
        end
      end

      private

      def fields(station)
        station.to_h.transform_keys(&:to_s)
      end

      def load_data
        data = JSON.parse(File.read(@path))
        return data if data['favorites'].is_a?(Array) && data['history'].is_a?(Array)

        empty
      rescue JSON::ParserError, SystemCallError
        empty
      end

      def empty = { 'favorites' => [], 'history' => [] }

      def save
        FileUtils.mkdir_p(File.dirname(@path))
        temporary = "#{@path}.#{Process.pid}.tmp"
        File.write(temporary, JSON.pretty_generate(@data))
        File.rename(temporary, @path)
        true
      rescue SystemCallError, IOError
        false
      end
    end
  end
end
