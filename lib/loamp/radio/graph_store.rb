# frozen_string_literal: true

require 'sqlite3'
require 'fileutils'

module Loamp
  module Radio
    class GraphStore
      CACHE_AGE = 30 * 24 * 60 * 60

      def initialize(path: self.class.default_path)
        FileUtils.mkdir_p(File.dirname(path)) unless path == ':memory:'
        @database = SQLite3::Database.new(path)
        @database.results_as_hash = true
        create_schema
      end

      def self.default_path
        root = ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache'))
        File.join(root, 'loamp', 'radio-graph.db')
      end

      def store_edges(seed, edges, fetched_at: Time.now.to_i)
        @database.transaction do
          edges.each do |target, weight|
            @database.execute(<<~SQL, [seed, target, weight.to_f, fetched_at])
              INSERT INTO edges (seed, target, weight, fetched_at) VALUES (?, ?, ?, ?)
              ON CONFLICT(seed, target) DO UPDATE SET weight=excluded.weight,
                fetched_at=excluded.fetched_at
            SQL
          end
        end
      end

      def neighbours(seed, max_age: CACHE_AGE)
        cutoff = Time.now.to_i - max_age
        @database.execute(<<~SQL, [seed, cutoff]).map { |row| [row['target'], row['weight'].to_f] }
          SELECT target, weight FROM edges WHERE seed = ? AND fetched_at >= ?
          ORDER BY weight DESC
        SQL
      end

      def feedback(track, value)
        key = track_key(track)
        @database.execute(<<~SQL, [key, track.artist, value.to_i])
          INSERT INTO feedback (track_key, artist, score) VALUES (?, ?, ?)
          ON CONFLICT(track_key) DO UPDATE SET score=excluded.score
        SQL
      end

      def score(track)
        @database.get_first_value('SELECT score FROM feedback WHERE track_key = ?',
                                  [track_key(track)]).to_i
      end

      def ban_artist(artist)
        @database.execute('INSERT OR IGNORE INTO banned_artists (artist) VALUES (?)', [artist])
      end

      def artist_banned?(artist)
        !@database.get_first_value('SELECT 1 FROM banned_artists WHERE artist = ?', [artist]).nil?
      end

      def close = @database.close

      private

      def create_schema
        @database.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS edges (
            seed TEXT NOT NULL, target TEXT NOT NULL, weight REAL NOT NULL,
            fetched_at INTEGER NOT NULL, PRIMARY KEY(seed, target)
          );
          CREATE TABLE IF NOT EXISTS feedback (
            track_key TEXT PRIMARY KEY, artist TEXT, score INTEGER NOT NULL
          );
          CREATE TABLE IF NOT EXISTS banned_artists (artist TEXT PRIMARY KEY);
        SQL
      end

      def track_key(track)
        [track.artist, track.album, track.title].join("\0").downcase
      end
    end
  end
end
