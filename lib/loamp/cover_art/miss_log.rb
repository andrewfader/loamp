# frozen_string_literal: true

require 'json'
require 'fileutils'

module Loamp
  module CoverArt
    # Remembers which albums the network had no cover for.
    #
    # Without this, an album with no art anywhere costs a MusicBrainz search
    # and an archive lookup every time it is played — and MusicBrainz allows
    # one request a second, so a library of them would spend its life queueing.
    # ArtCache already remembers misses for as long as the process runs; this
    # is the half that survives a restart.
    #
    # Entries expire, because "no cover" is a fact about the archive today. Art
    # gets uploaded, and a cache that never forgets would never notice.
    #
    # Only misses the services actually confirmed are recorded. A lookup that
    # failed because the network did is not evidence of anything.
    class MissLog
      # Long enough that a library of coverless bootlegs is not rechecked
      # constantly, short enough that a cover uploaded this month is found.
      EXPIRY_SECONDS = 30 * 24 * 60 * 60

      FILENAME = 'misses.json'

      def initialize(path:, expiry: EXPIRY_SECONDS, clock: -> { Time.now.to_i })
        @path = path.to_s
        @expiry = expiry
        @clock = clock
        @entries = nil
      end

      def self.default_path(directory)
        File.join(directory, FILENAME)
      end

      def miss?(key)
        recorded = entries[key.to_s]
        return false unless recorded

        # An entry that has aged out is dropped on sight, so the next lookup
        # goes to the network and either finds art or writes the miss again.
        return true if fresh?(recorded)

        @entries.delete(key.to_s)
        false
      end

      def record(key)
        entries[key.to_s] = @clock.call
        save
        true
      end

      def forget(key = nil)
        key ? entries.delete(key.to_s) : entries.clear
        save
      end

      def size = entries.size

      private

      def fresh?(recorded)
        @clock.call - recorded.to_i < @expiry
      end

      # A cache file that cannot be read is a cache file with nothing in it.
      # Corrupt JSON, a half-written file, a directory that vanished: none of
      # them are worth a word to the listener, who did not ask for any of this.
      def entries
        @entries ||= prune(read)
      end

      def read
        return {} unless File.file?(@path)

        parsed = JSON.parse(File.read(@path))
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError, SystemCallError, IOError
        {}
      end

      def prune(loaded)
        loaded.select { |_, recorded| recorded.is_a?(Integer) && fresh?(recorded) }
      end

      # Written under a temporary name and moved into place, so a crash midway
      # leaves the previous log rather than a truncated one.
      def save
        FileUtils.mkdir_p(File.dirname(@path))
        temporary = "#{@path}.#{Process.pid}.tmp"
        File.write(temporary, JSON.generate(@entries))
        File.rename(temporary, @path)
        true
      rescue SystemCallError, IOError
        false
      end
    end
  end
end
