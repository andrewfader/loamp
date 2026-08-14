# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'

module Loamp
  module Lyrics
    class Cache
      def initialize(directory: self.class.default_directory, resolver: Resolver.new, miss_log: nil)
        @directory = directory
        @resolver = resolver
        @miss_log = miss_log || CoverArt::MissLog.new(path: File.join(directory, 'misses.json'))
        @pending = {}
        @threads = []
        @mutex = Mutex.new
      end

      def self.default_directory
        root = ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache'))
        File.join(root, 'loamp', 'lyrics')
      end

      def for(track)
        return nil unless track

        @resolver.local(track) || read(track)
      end

      def fetch_remote(track, &callback)
        return false if @detached || !eligible?(track) || self.for(track)

        key = key_for(track)
        return false if @miss_log.miss?(key) || !claim(key)

        @threads << Thread.new { look_up(track, key, callback) }
        true
      end

      def shutdown(timeout: 5)
        @detached = true
        @threads.each { |thread| thread.join(timeout) }
        @threads.clear
      end

      private

      def eligible?(track)
        track && !track.title.to_s.empty? && !track.artist.to_s.empty?
      end

      def claim(key)
        @mutex.synchronize do
          next false if @pending[key]

          @pending[key] = true
        end
      end

      def look_up(track, key, callback)
        document = @resolver.remote(track)
        write(track, document) if document
        @miss_log.record(key) if !document && @resolver.last_definitive
        deliver(key, document, callback)
      rescue StandardError
        deliver(key, nil, callback)
      end

      def deliver(key, document, callback)
        idle do
          @mutex.synchronize { @pending.delete(key) }
          callback&.call(document)
        end
      end

      def idle
        return if @detached
        return yield unless defined?(GLib::Idle)

        GLib::Idle.add do
          yield unless @detached
          false
        end
      end

      def read(track)
        fields = JSON.parse(File.read(path_for(track)))
        Document.new(plain: fields['plain'], lines: fields['lines'], source: :cache)
      rescue JSON::ParserError, SystemCallError, TypeError
        nil
      end

      def write(track, document)
        return unless document

        FileUtils.mkdir_p(@directory)
        path = path_for(track)
        temporary = "#{path}.#{Process.pid}.tmp"
        File.write(temporary, JSON.generate(plain: document.plain, lines: document.lines))
        File.rename(temporary, path)
      rescue SystemCallError, IOError
        nil
      end

      def path_for(track) = File.join(@directory, "#{key_for(track)}.json")

      def key_for(track)
        identity = [track.artist, track.album, track.title, track.duration.to_i].join("\0")
        Digest::SHA256.hexdigest(identity)[0, 32]
      end
    end
  end
end
