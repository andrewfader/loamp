# frozen_string_literal: true

module Loamp
  class Library
    # The shape of the index: one row per file, plus an FTS5 view over the
    # three fields anybody actually searches by.
    #
    # Columns mirror Metadata::ATTRIBUTES rather than being an independent
    # list, and the two are checked against each other at load time — a tag
    # added to Metadata and forgotten here would otherwise be read from disk
    # on every scan and then silently dropped.
    module Schema
      VERSION = 4

      TEXT = %i[title artist album album_artist composer genre comment lyrics
                musicbrainz_album_id musicbrainz_artist_id].freeze
      INTEGER = %i[track_number track_total disc_number disc_total year
                   bitrate sample_rate channels].freeze
      REAL = %i[duration replaygain_track_gain replaygain_album_gain].freeze

      TAG_COLUMNS = (TEXT + INTEGER + REAL).freeze

      missing = Metadata::ATTRIBUTES - TAG_COLUMNS
      raise "Library schema is missing Metadata attributes: #{missing.join(', ')}" if missing.any?

      # Identity, bookkeeping, then the tags.
      COLUMNS = (%i[path mtime size artwork indexed_at] + TAG_COLUMNS).freeze

      SEARCHABLE = %i[title artist album].freeze

      INDEXED = %i[artist album_artist album genre year].freeze

      module_function

      def create(database)
        database.execute_batch(<<~SQL)
          #{table}
          #{folders_table}
          #{indices}
          #{full_text_search}
        SQL
        migrate(database)
        database.user_version = VERSION
      end

      # CREATE TABLE IF NOT EXISTS leaves an index written by an older version
      # exactly as it was, so a tag added to the schema since would be read from
      # every file and then rejected by SQLite on the way in. Adding the columns
      # in place is enough: this schema only ever grows, and a column SQLite can
      # add is one it can also leave empty until the next scan fills it.
      def migrate(database)
        return if database.user_version == VERSION

        existing = database.table_info('tracks').map { |column| column['name'].to_sym }

        (TAG_COLUMNS - existing).each do |name|
          database.execute("ALTER TABLE tracks ADD COLUMN #{name} #{sql_type(name)}")
        end

        database.execute_batch(folders_table)
      end

      def folders_table
        <<~SQL
          CREATE TABLE IF NOT EXISTS folders (
            path TEXT PRIMARY KEY,
            added_at INTEGER NOT NULL
          );
        SQL
      end

      def table
        <<~SQL
          CREATE TABLE IF NOT EXISTS tracks (
            id INTEGER PRIMARY KEY,
            path TEXT NOT NULL UNIQUE,
            mtime INTEGER NOT NULL,
            size INTEGER NOT NULL,
            artwork INTEGER NOT NULL DEFAULT 0,
            indexed_at INTEGER NOT NULL,
            #{TAG_COLUMNS.map { |name| "#{name} #{sql_type(name)}" }.join(",\n  ")}
          );
        SQL
      end

      def indices
        INDEXED.map do |name|
          "CREATE INDEX IF NOT EXISTS tracks_#{name}_index ON tracks (#{name});"
        end.join("\n")
      end

      # An external-content FTS5 table: the index stores no copy of the text,
      # it points back at the tracks row. Triggers keep the two in step, which
      # is the documented way to use contentless-delete-free external content.
      def full_text_search
        columns = SEARCHABLE.join(', ')

        <<~SQL
          CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5(
            #{columns},
            content='tracks',
            content_rowid='id',
            tokenize='unicode61 remove_diacritics 2'
          );

          CREATE TRIGGER IF NOT EXISTS tracks_fts_insert AFTER INSERT ON tracks BEGIN
            INSERT INTO tracks_fts (rowid, #{columns})
            VALUES (new.id, #{SEARCHABLE.map { |c| "new.#{c}" }.join(', ')});
          END;

          CREATE TRIGGER IF NOT EXISTS tracks_fts_delete AFTER DELETE ON tracks BEGIN
            INSERT INTO tracks_fts (tracks_fts, rowid, #{columns})
            VALUES ('delete', old.id, #{SEARCHABLE.map { |c| "old.#{c}" }.join(', ')});
          END;

          CREATE TRIGGER IF NOT EXISTS tracks_fts_update AFTER UPDATE ON tracks BEGIN
            INSERT INTO tracks_fts (tracks_fts, rowid, #{columns})
            VALUES ('delete', old.id, #{SEARCHABLE.map { |c| "old.#{c}" }.join(', ')});
            INSERT INTO tracks_fts (rowid, #{columns})
            VALUES (new.id, #{SEARCHABLE.map { |c| "new.#{c}" }.join(', ')});
          END;
        SQL
      end

      def sql_type(name)
        return 'INTEGER' if INTEGER.include?(name)
        return 'REAL' if REAL.include?(name)

        'TEXT'
      end
    end
  end
end
