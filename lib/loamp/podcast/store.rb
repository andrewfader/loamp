# frozen_string_literal: true

require 'sqlite3'
require 'fileutils'

module Loamp
  module Podcast
    class Store
      def initialize(path: self.class.default_path)
        @path = path
        FileUtils.mkdir_p(File.dirname(path)) unless path == ':memory:'
        @database = SQLite3::Database.new(path)
        @database.results_as_hash = true
        create_schema
      end

      def self.default_path
        root = ENV.fetch('XDG_DATA_HOME', File.join(Dir.home, '.local', 'share'))
        File.join(root, 'loamp', 'podcasts.db')
      end

      def subscribe(feed)
        values = [feed.url, feed.title, feed.description, feed.site_url,
                  feed.image_url, Time.now.to_i]
        @database.execute(<<~SQL, values)
          INSERT INTO feeds (url, title, description, site_url, image_url, updated_at)
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(url) DO UPDATE SET title=excluded.title, description=excluded.description,
            site_url=excluded.site_url, image_url=excluded.image_url, updated_at=excluded.updated_at
        SQL
        feed_id = @database.get_first_value('SELECT id FROM feeds WHERE url = ?', [feed.url])
        feed.episodes.each { |episode| store_episode(feed_id, episode) }
        feed
      end

      def unsubscribe(url)
        @database.execute('DELETE FROM feeds WHERE url = ?', [url])
        @database.changes.positive?
      end

      def feeds
        @database.execute('SELECT * FROM feeds ORDER BY title COLLATE NOCASE').map do |row|
          Feed.new(title: row['title'], description: row['description'], url: row['url'],
                   site_url: row['site_url'], image_url: row['image_url'],
                   episodes: episodes(row['url']))
        end
      end

      def episodes(feed_url)
        @database.execute(<<~SQL, [feed_url]).map { |row| episode_from(row) }
          SELECT episodes.*, feeds.title AS feed_title FROM episodes
          JOIN feeds ON feeds.id = episodes.feed_id
          WHERE feeds.url = ? ORDER BY published_at DESC, episodes.id DESC
        SQL
      end

      def remember_position(guid, seconds)
        @database.execute('UPDATE episodes SET position = ? WHERE guid = ?', [seconds.to_f, guid])
      end

      def position(guid)
        @database.get_first_value('SELECT position FROM episodes WHERE guid = ?', [guid]).to_f
      end

      def downloaded(guid, path)
        @database.execute('UPDATE episodes SET local_path = ? WHERE guid = ?', [path, guid])
      end

      def close = @database&.close

      private

      def create_schema
        @database.execute_batch(<<~SQL)
          PRAGMA foreign_keys = ON;
          CREATE TABLE IF NOT EXISTS feeds (
            id INTEGER PRIMARY KEY, url TEXT NOT NULL UNIQUE, title TEXT,
            description TEXT, site_url TEXT, image_url TEXT, updated_at INTEGER NOT NULL
          );
          CREATE TABLE IF NOT EXISTS episodes (
            id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
            guid TEXT NOT NULL UNIQUE, title TEXT, description TEXT, media_url TEXT NOT NULL,
            published_at INTEGER, duration REAL, image_url TEXT, position REAL NOT NULL DEFAULT 0,
            local_path TEXT
          );
        SQL
      end

      def store_episode(feed_id, episode)
        values = [feed_id, episode.guid, episode.title, episode.description,
                  episode.media_url, episode.published_at, episode.duration, episode.image_url]
        @database.execute(<<~SQL, values)
          INSERT INTO episodes
            (feed_id, guid, title, description, media_url, published_at, duration, image_url)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(guid) DO UPDATE SET title=excluded.title, description=excluded.description,
            media_url=excluded.media_url, published_at=excluded.published_at,
            duration=excluded.duration, image_url=excluded.image_url
        SQL
      end

      def episode_from(row)
        Episode.new(guid: row['guid'], title: row['title'], description: row['description'],
                    media_url: row['local_path'] || row['media_url'],
                    published_at: row['published_at'], duration: row['duration'],
                    image_url: row['image_url'], feed_title: row['feed_title'])
      end
    end
  end
end
