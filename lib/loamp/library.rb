# frozen_string_literal: true

require 'sqlite3'
require 'fileutils'

module Loamp
  # The music collection, indexed on disk.
  #
  # A playlist is what is queued right now; the library is everything the
  # listener owns. It exists so that browsing thousands of albums and
  # searching them stays instant, which means never re-reading tags that have
  # not changed: a file is only opened again when its mtime or size moves.
  #
  # One instance owns one SQLite connection and belongs to one thread. The
  # scanner opens its own on the same file — that is what WAL mode is for.
  class Library
    # Asking a closed library a question is a bug in the caller, and saying so
    # beats a NoMethodError on nil from somewhere three frames down.
    class ClosedError < StandardError; end

    IN_MEMORY = ':memory:'

    # Grouping falls back to the performing artist for files that never had an
    # album artist written, which is most of them.
    ALBUM_ARTIST = "COALESCE(NULLIF(album_artist, ''), artist)"

    UNKNOWN_ARTIST = 'Unknown Artist'
    UNKNOWN_ALBUM = 'Unknown Album'

    # Names are kept exactly as they were tagged, including not being tagged
    # at all, so that browsing by them can still find the tracks. The stand-in
    # is for display only.
    Artist = Struct.new(:name, :album_count, :track_count, keyword_init: true) do
      def display_name = name.to_s.empty? ? UNKNOWN_ARTIST : name
    end

    Album = Struct.new(:title, :artist, :year, :track_count, :path, keyword_init: true) do
      def display_title = title.to_s.empty? ? UNKNOWN_ALBUM : title
      def display_artist = artist.to_s.empty? ? UNKNOWN_ARTIST : artist
    end

    attr_reader :path

    def initialize(path: self.class.default_path)
      @path = path.to_s
      @database = connect
      Schema.create(@database)
    end

    def self.default_path
      root = ENV.fetch('XDG_DATA_HOME', File.join(Dir.home, '.local', 'share'))
      File.join(root, 'loamp', 'library.db')
    end

    def close
      @database&.close
      @database = nil
    end

    def closed?
      @database.nil? || @database.closed?
    end

    # --- Writing ------------------------------------------------------------

    # Indexes one file, reading its tags only when the file on disk differs
    # from what is already stored. Returns :added, :updated, :unchanged, or
    # :missing when the file is gone.
    def add(file_path, metadata: nil)
      absolute = File.expand_path(file_path.to_s)
      stat = File.stat(absolute)
      known = fingerprint(absolute)

      return :unchanged if !metadata && known && known == [stat.mtime.to_i, stat.size]

      store(absolute, metadata || Metadata.read(absolute), stat)
      known ? :updated : :added
    rescue SystemCallError
      :missing
    end

    # Wraps a batch of writes in one transaction. SQLite commits per statement
    # otherwise, which turns a 10,000 file scan into 10,000 fsyncs.
    def transaction(&)
      return yield if database.transaction_active?

      database.transaction(&)
    end

    def remove(file_path)
      database.execute('DELETE FROM tracks WHERE path = ?', [File.expand_path(file_path.to_s)])
      database.changes.positive?
    end

    # Drops rows whose file has disappeared. Returns the paths removed, so a
    # caller can tell the user what went.
    def prune
      gone = paths.reject { |stored| File.file?(stored) }
      transaction { gone.each { |stored| remove(stored) } }
      gone
    end

    def clear
      database.execute('DELETE FROM tracks')
    end

    # Roots the listener asked to index. Nested folders collapse into their
    # parent so an overlapping pair is stored once, and Rescan walks these
    # rather than every album directory a track happens to sit in.
    def watch_folders
      stored = stored_watch_folders
      stored.empty? ? inferred_watch_folders : stored
    end

    # Explicit auto-scan roots only — never the inferred album-dir fallback.
    # The folders dialog and startup scan use this so a legacy index without
    # stored roots does not suddenly walk every album directory.
    def stored_watch_folders
      database.execute('SELECT path FROM folders ORDER BY path')
        .map { |row| row['path'] }
    end

    def add_watch_folder(directory)
      root = File.expand_path(directory.to_s)
      return false unless File.directory?(root)

      database.transaction { store_watch_folder(root) }
      true
    end

    # Stops auto-scanning a root. When remove_tracks is true (the default),
    # every indexed file under that root leaves the library with it.
    def remove_watch_folder(directory, remove_tracks: true)
      root = File.expand_path(directory.to_s)
      database.transaction do
        database.execute('DELETE FROM folders WHERE path = ?', [root])
        removed = database.changes.positive?
        remove_tracks_under(root) if remove_tracks && removed
        removed
      end
    end

    # --- Reading ------------------------------------------------------------

    def count
      database.get_first_value('SELECT COUNT(*) FROM tracks').to_i
    end

    def empty?
      count.zero?
    end

    def include?(file_path)
      !fingerprint(File.expand_path(file_path.to_s)).nil?
    end

    def paths
      database.execute('SELECT path FROM tracks ORDER BY path').map { |row| row['path'] }
    end

    # Keys the similar-artist graph uses to colour nodes the library holds.
    def artist_index
      database.execute('SELECT DISTINCT artist, musicbrainz_artist_id FROM tracks')
        .each_with_object({}) do |row, index|
          index[row['artist']] = true unless row['artist'].to_s.empty?
          index[row['musicbrainz_artist_id']] = true unless row['musicbrainz_artist_id'].to_s.empty?
        end
    end

    def unresolved_artists
      database.execute(<<~SQL).map { |row| row['artist'] }
        SELECT DISTINCT artist FROM tracks
        WHERE artist IS NOT NULL AND artist != '' AND musicbrainz_artist_id IS NULL
        ORDER BY artist COLLATE NOCASE
      SQL
    end

    def identify_artist(name, mbid)
      return false unless mbid.to_s.match?(Metadata::MBID)

      sql = <<~SQL
        UPDATE tracks SET musicbrainz_artist_id = ?
        WHERE artist = ? AND musicbrainz_artist_id IS NULL
      SQL
      database.execute(sql, [mbid, name])
      database.changes.positive?
    end

    def track(file_path)
      row = database.execute('SELECT * FROM tracks WHERE path = ?',
                             [File.expand_path(file_path.to_s)]).first
      row && build_track(row)
    end

    # The natural order for a music collection is not alphabetical by title:
    # it is artist, then album, then the order the album was meant to play in.
    def tracks(artist: :any, album: :any, limit: nil, offset: 0)
      conditions = []
      values = []

      unless artist == :any
        conditions << "#{ALBUM_ARTIST} IS ?"
        values << artist
      end

      unless album == :any
        conditions << 'album IS ?'
        values << album
      end

      rows = database.execute(<<~SQL, values + [limit || -1, offset.to_i])
        SELECT * FROM tracks
        #{"WHERE #{conditions.join(' AND ')}" unless conditions.empty?}
        ORDER BY #{ALBUM_ARTIST} COLLATE NOCASE, album COLLATE NOCASE,
                 disc_number, track_number, title COLLATE NOCASE
        LIMIT ? OFFSET ?
      SQL

      rows.map { |row| build_track(row) }
    end

    # GROUP BY names a real column before it names an output alias, so the
    # expressions are repeated rather than referred to by their aliases —
    # grouping by `title` would silently group by the song title instead.
    def artists
      database.execute(<<~SQL).map do |row|
        SELECT #{ALBUM_ARTIST} AS name,
               COUNT(DISTINCT album) AS albums,
               COUNT(*) AS tracks
        FROM tracks
        GROUP BY #{ALBUM_ARTIST} COLLATE NOCASE
        ORDER BY #{ALBUM_ARTIST} COLLATE NOCASE
      SQL
        Artist.new(name: row['name'], album_count: row['albums'].to_i,
                   track_count: row['tracks'].to_i)
      end
    end

    def albums(artist: :any)
      values = artist == :any ? [] : [artist]

      database.execute(<<~SQL, values).map do |row|
        SELECT album AS title, #{ALBUM_ARTIST} AS artist, MIN(year) AS year,
               COUNT(*) AS tracks, MIN(path) AS path
        FROM tracks
        #{"WHERE #{ALBUM_ARTIST} IS ?" unless artist == :any}
        GROUP BY album COLLATE NOCASE, #{ALBUM_ARTIST} COLLATE NOCASE
        ORDER BY #{ALBUM_ARTIST} COLLATE NOCASE, MIN(year), album COLLATE NOCASE
      SQL
        Album.new(title: row['title'], artist: row['artist'], year: row['year'],
                  track_count: row['tracks'].to_i, path: row['path'])
      end
    end

    def genres
      database.execute(<<~SQL).map { |row| row['genre'] }
        SELECT DISTINCT genre FROM tracks
        WHERE genre IS NOT NULL AND genre <> ''
        ORDER BY genre COLLATE NOCASE
      SQL
    end

    # Full-text search over title, artist and album, ranked by FTS5's own
    # relevance — which weighs a hit in a short field more heavily.
    def search(query, limit: 200)
      expression = Search.expression(query)
      return [] unless expression

      rows = database.execute(<<~SQL, [expression, limit])
        SELECT tracks.* FROM tracks_fts
        JOIN tracks ON tracks.id = tracks_fts.rowid
        WHERE tracks_fts MATCH ?
        ORDER BY rank
        LIMIT ?
      SQL

      rows.map { |row| build_track(row) }
    rescue SQLite3::SQLException
      # A query FTS5 will not parse is a typo, not an error worth raising at
      # someone who is still typing.
      []
    end

    private

    # Everything public goes through here rather than touching @database, so
    # a call after #close says what is wrong.
    def database
      raise ClosedError, "the library at #{@path} is closed" if @database.nil?

      @database
    end

    def connect
      FileUtils.mkdir_p(File.dirname(@path)) unless @path == IN_MEMORY

      SQLite3::Database.new(@path).tap do |database|
        database.results_as_hash = true
        database.busy_timeout = 5_000
        # WAL lets the scanner write from its own thread while the UI reads.
        database.execute('PRAGMA journal_mode = WAL') unless @path == IN_MEMORY
        database.execute('PRAGMA synchronous = NORMAL')
        database.execute('PRAGMA temp_store = MEMORY')
      end
    end

    def store_watch_folder(root)
      already_watched = false

      database.execute('SELECT path FROM folders').each do |row|
        path = row['path']
        if path == root || nested?(root, under: path)
          already_watched = true
        elsif nested?(path, under: root)
          database.execute('DELETE FROM folders WHERE path = ?', [path])
        end
      end

      return if already_watched

      database.execute('INSERT INTO folders (path, added_at) VALUES (?, ?)',
                       [root, Time.now.to_i])
    end

    def nested?(path, under:)
      path.start_with?("#{under}#{File::SEPARATOR}")
    end

    def remove_tracks_under(root)
      database.execute(
        'DELETE FROM tracks WHERE path = ? OR path LIKE ? ESCAPE ?',
        [root, "#{escape_like(root)}#{File::SEPARATOR}%", '\\']
      )
    end

    def escape_like(value)
      value.gsub(/[%_\\]/) { |char| "\\#{char}" }
    end

    # An index written before folders were stored has no roots to rescan.
    # Album directories are a poorer substitute, but they still pick up
    # tag changes in files that are already known.
    def inferred_watch_folders
      database.execute('SELECT path FROM tracks')
        .map { |row| File.dirname(row['path']) }
        .uniq
        .sort
    end

    def fingerprint(absolute)
      row = database.execute('SELECT mtime, size FROM tracks WHERE path = ?', [absolute]).first
      row && [row['mtime'], row['size']]
    end

    def store(absolute, metadata, stat)
      identity = [absolute, stat.mtime.to_i, stat.size, metadata.artwork? ? 1 : 0, Time.now.to_i]
      tags = Schema::TAG_COLUMNS.map { |name| metadata.public_send(name) }

      database.execute(upsert, identity + tags)
    end

    def upsert
      @upsert ||= <<~SQL
        INSERT INTO tracks (#{Schema::COLUMNS.join(', ')})
        VALUES (#{Array.new(Schema::COLUMNS.size, '?').join(', ')})
        ON CONFLICT (path) DO UPDATE SET
          #{(Schema::COLUMNS - [:path]).map { |name| "#{name} = excluded.#{name}" }.join(', ')}
      SQL
    end

    def build_track(row)
      tags = Schema::TAG_COLUMNS.to_h { |name| [name, row[name.to_s]] }
      tags[:artwork] = row['artwork'].to_i == 1

      Track.new(row['path'], metadata: Metadata.new(**tags))
    end
  end
end
