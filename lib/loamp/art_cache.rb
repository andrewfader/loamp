# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'gdk_pixbuf2'

module Loamp
  # Cover art as a file:// URL.
  #
  # Everything outside the process — the MPRIS metadata map, the GNOME Shell
  # media widget, a notification — wants a URL, not a blob of JPEG. Art that
  # already sits on disk beside the track is pointed at where it lies; art
  # embedded in a tag is written out once and reused.
  #
  # Lookups are memoised per file, including the misses, because this is asked
  # on every track change and reading a tag to learn "still no art" is waste.
  class ArtCache
    EXTENSIONS = {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/bmp' => '.bmp',
      'image/gif' => '.gif',
    }.freeze

    DEFAULT_EXTENSION = '.img'

    attr_reader :directory

    # The fetcher is built on first use rather than here, so a cache that is
    # only ever asked about local art never constructs a rate limiter it will
    # not use — and, more to the point, so nothing reaches the network unless
    # #fetch_remote is actually called.
    def initialize(directory: self.class.default_directory, fetcher: nil, miss_log: nil)
      @directory = directory.to_s
      @urls = {}
      @fetcher = fetcher
      @miss_log = miss_log
      @pending = {}
      @threads = []
      @mutex = Mutex.new
    end

    def self.default_directory
      root = ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache'))
      File.join(root, 'loamp', 'art')
    end

    # nil when the track has no art anywhere, which callers treat as "omit the
    # artUrl key" rather than as an error.
    def url_for(track)
      return nil unless track&.file_path

      @urls.fetch(track.file_path) do
        @urls[track.file_path] = resolve(track)
      end
    end

    def forget(track = nil)
      track ? @urls.delete(track.file_path) : @urls.clear
    end

    # A list-row-sized copy, cached separately from the full cover used by
    # Now Playing and MPRIS. Folder and embedded art therefore decode once.
    def thumbnail_for(track, size: 64)
      source_url = url_for(track)
      source = FileUri.to_path(source_url)
      return nil unless source

      path = File.join(@directory, "#{cache_key(track)}-#{size}.png")
      return FileUri.for(path) if File.file?(path) && !File.empty?(path)

      pixbuf = GdkPixbuf::Pixbuf.new(file: source)
      width, height = thumbnail_dimensions(pixbuf.width, pixbuf.height, size)
      thumbnail = pixbuf.scale_simple(width, height, :bilinear)
      FileUtils.mkdir_p(@directory)
      thumbnail.save(path, 'png')
      FileUri.for(path)
    rescue StandardError
      nil
    end

    # Looks for cover art on the network for a track that has none locally.
    #
    # The lookup runs on a worker thread — MusicBrainz allows one request a
    # second, and a UI that waited for it would be unusable — and the block is
    # called on the main loop with the URL, or with nil when there is no art to
    # be had.
    #
    # Returns false when there is nothing to do: the art is already known, the
    # album has been looked for before and not found, or a lookup for it is
    # already in flight. Callers can use that to tell a real fetch from a
    # redraw, and every one of those cases matters — this is asked on every
    # track change, and an album with no cover anywhere must not cost a search
    # every time it is played.
    def fetch_remote(track, &on_resolved)
      return false unless track&.file_path
      return false if @detached || url_for(track)
      # Nothing to look anything up by. A search on an empty album title
      # matches everything and means nothing.
      return false if track.musicbrainz_album_id.nil? && track.album.to_s.strip.empty?

      key = cache_key(track)
      return false if miss_log.miss?(key)
      return false unless claim(key)

      # Built here rather than on the worker: two threads racing to create the
      # fetcher would each get one, and with it a rate limiter of its own,
      # which is exactly the thing a rate limiter cannot have.
      resolver = fetcher
      @threads << Thread.new { look_up(resolver, track, key, on_resolved) }
      true
    end

    # Stops delivering results. A callback that reaches a widget torn down
    # while a lookup was in flight is a crash rather than an error, so the
    # owner of the cache has to be able to say when it is finished.
    def shutdown(timeout: 5)
      @detached = true
      wait(timeout: timeout)
    end

    # Blocks until every lookup in flight has finished, without detaching —
    # results still arrive. For tests, and for anything that wants the network
    # answer before it carries on.
    def wait(timeout: nil)
      @threads.each { |thread| thread.join(timeout) }
      @threads.clear
      true
    end

    def fetcher
      @fetcher ||= CoverArt::Fetcher.new
    end

    def miss_log
      @miss_log ||= CoverArt::MissLog.new(path: CoverArt::MissLog.default_path(@directory))
    end

    private

    def resolve(track)
      beside = Artwork.find_folder_art(File.dirname(track.file_path.to_s))
      return FileUri.for(beside) if beside

      embedded = Artwork.embedded(track)
      path = embedded&.data && write(embedded, track)

      # Last, because it is the only one that can be stale: art written here by
      # an earlier run, or by another track of the same album a moment ago.
      path ||= cached_file(track)

      path && FileUri.for(path)
    end

    # The whole of a lookup that happens away from the main loop, including
    # writing the image out — a cover is hundreds of kilobytes, and the point
    # of the worker thread is that none of that lands on the UI.
    def look_up(resolver, track, key, on_resolved)
      result = resolver.fetch(track)
      path = result.found? ? write(result.image, track) : nil

      idle { finish(track, key, result, path, on_resolved) }
    rescue StandardError
      # A lookup that fails says nothing about the album, so nothing is
      # remembered about it beyond letting go of the claim.
      idle { release_and_report(key, nil, on_resolved) }
    end

    def finish(track, key, result, path, on_resolved)
      url = path && FileUri.for(path)
      @urls[track.file_path] = url if url
      miss_log.record(key) if !url && result.definitive?

      release_and_report(key, url, on_resolved)
    end

    def release_and_report(key, url, on_resolved)
      @mutex.synchronize { @pending.delete(key) }
      on_resolved&.call(url)
    end

    # One lookup per album, however many of its tracks ask at once.
    def claim(key)
      @mutex.synchronize do
        next false if @pending.key?(key)

        @pending[key] = true
      end
    end

    # Outside a GLib main loop — in a plain test process — there is nothing to
    # schedule onto, so the block runs where it stands.
    def idle(&)
      return if @detached

      unless defined?(GLib::Idle)
        yield
        return
      end

      GLib::Idle.add do
        yield unless @detached
        false
      end
    end

    def cached_file(track)
      Dir.glob(File.join(@directory, "#{cache_key(track)}.*")).find { |path| File.file?(path) }
    rescue SystemCallError
      nil
    end

    # Keyed on the album rather than the track, so the twelve files of one
    # album share a single cached cover instead of writing it twelve times.
    def write(image, track)
      path = File.join(@directory, "#{cache_key(track)}#{extension_for(image)}")
      return path if File.file?(path) && !File.empty?(path)

      FileUtils.mkdir_p(@directory)
      # A partial file left by a crash would be cached forever, so the write
      # is completed under a temporary name and moved into place.
      temporary = "#{path}.#{Process.pid}.tmp"
      File.binwrite(temporary, image.data)
      File.rename(temporary, path)
      path
    rescue SystemCallError, IOError
      nil
    end

    def cache_key(track)
      album = track.album.to_s
      identity = album.empty? ? track.file_path.to_s : "#{album_artist_of(track)} #{album}"

      Digest::SHA256.hexdigest(identity)[0, 32]
    end

    def album_artist_of(track)
      track.album_artist || track.artist
    end

    def extension_for(image)
      EXTENSIONS.fetch(image.mime_type.to_s.downcase.split(';').first, DEFAULT_EXTENSION)
    end

    def thumbnail_dimensions(width, height, size)
      ratio = [size.to_f / width, size.to_f / height, 1.0].min
      [[(width * ratio).round, 1].max, [(height * ratio).round, 1].max]
    end
  end
end
