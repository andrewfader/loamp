# frozen_string_literal: true

module Loamp
  class Library
    # Turns a shell-style path pattern into the folders it names.
    #
    # Picking library folders one at a time through a file chooser is fine for
    # a tidy ~/Music and useless for a disk where the albums are scattered:
    # /mnt/**/downloads* is the question actually being asked. Because a
    # pattern can match far more than its author expected, this only ever
    # reports — nothing is indexed until the caller takes the paths and adds
    # them, which is what makes the preview a dry run.
    #
    # Matches are folders. A pattern may well hit ordinary files too; those
    # are counted and set aside rather than silently ignored, because
    # "matched 900 things, 12 of them folders" is the sort of thing that
    # explains a surprising result.
    class FolderGlob
      # A pattern like /**/* on a large disk can name tens of thousands of
      # directories. Past a few hundred the list has stopped being something
      # a person reads, and walking them all for track counts costs minutes.
      MAX_MATCHES = 500

      Match = Struct.new(:path, :track_count, :watched, keyword_init: true) do
        def name = File.basename(path)
        def watched? = watched ? true : false
      end

      Result = Struct.new(:pattern, :matches, :truncated, :skipped_files, :error,
                          keyword_init: true) do
        def error? = !error.nil?
        def empty? = matches.empty?

        # Folders worth adding: what matched, minus the ones the library
        # already watches.
        def addable = matches.reject(&:watched?)

        def track_count = matches.sum { |match| match.track_count.to_i }
        def addable_track_count = addable.sum { |match| match.track_count.to_i }
        def paths = matches.map(&:path)
      end

      def self.preview(pattern, watched: [], count_tracks: true)
        new(pattern, watched: watched).preview(count_tracks: count_tracks)
      end

      def initialize(pattern, watched: [])
        @pattern = pattern.to_s.strip
        @watched = Array(watched).map { |path| File.expand_path(path.to_s) }
        @cancelled = false
      end

      # Stops a walk in progress. The result is discarded by the caller, so
      # what comes back afterwards does not matter — only that it comes back.
      def cancel
        @cancelled = true
      end

      def cancelled? = @cancelled

      def preview(count_tracks: true)
        return failure('Enter a path pattern, such as /mnt/**/downloads*') if @pattern.empty?

        entries = glob
        directories = entries.select { |entry| File.directory?(entry) }
        roots = collapse(directories.sort)
        truncated = roots.size > MAX_MATCHES

        Result.new(
          pattern: @pattern,
          matches: build_matches(roots.first(MAX_MATCHES), count_tracks: count_tracks),
          truncated: truncated,
          skipped_files: entries.size - directories.size,
        )
      rescue StandardError => e
        failure("Could not read #{@pattern}: #{e.message}")
      end

      private

      def glob
        Dir.glob(expanded_pattern).map { |entry| File.expand_path(entry) }.uniq
      end

      # A bare ~ never reaches the glob as a home directory, and a relative
      # pattern should mean the same thing it means in a shell.
      def expanded_pattern
        File.expand_path(@pattern)
      rescue ArgumentError
        # File.expand_path raises on ~nosuchuser; the literal is a better
        # answer than an exception, and simply matches nothing.
        @pattern
      end

      # Drops any match that sits inside another match. Adding both would
      # index the same tree twice in the preview's totals and then collapse
      # to one folder anyway when stored.
      def collapse(paths)
        paths.reject do |path|
          paths.any? { |other| other != path && nested?(path, under: other) }
        end
      end

      def build_matches(roots, count_tracks:)
        roots.filter_map do |path|
          break [] if cancelled?

          Match.new(
            path: path,
            track_count: count_tracks ? AudioFiles.count_under(path) : nil,
            watched: watched?(path),
          )
        end
      end

      def watched?(path)
        @watched.any? { |root| root == path || nested?(path, under: root) }
      end

      def nested?(path, under:)
        path.start_with?("#{under}#{File::SEPARATOR}")
      end

      def failure(message)
        Result.new(pattern: @pattern, matches: [], truncated: false, skipped_files: 0,
                   error: message)
      end
    end
  end
end
