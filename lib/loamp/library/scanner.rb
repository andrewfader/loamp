# frozen_string_literal: true

module Loamp
  class Library
    # Walks folders and feeds them to the index.
    #
    # Reading tags is disk-bound and slow enough to be felt: a few thousand
    # files is several seconds. So #start does the work on a plain Ruby
    # thread, which is safe here because TagLib and SQLite both release the
    # GVL, and hands results back to the main loop with GLib::Idle.add — the
    # only place GTK may be touched.
    #
    # The worker opens its own connection to the same database file rather
    # than borrowing the one the UI is reading through, which is what WAL mode
    # is for.
    class Scanner
      # Big enough that the fsyncs disappear, small enough that a scan
      # interrupted by a crash has not lost much.
      BATCH_SIZE = 250

      Progress = Struct.new(:scanned, :added, :updated, :total, keyword_init: true) do
        def complete? = total && scanned >= total
        def fraction = total.to_i.positive? ? scanned.to_f / total : 0.0
      end

      attr_reader :library_path

      def initialize(library)
        @library_path = library.respond_to?(:path) ? library.path : library.to_s
        # An in-memory database lives inside the connection that created it,
        # so there is no file for the worker to open its own handle onto. The
        # instance is shared instead, which SQLite's serialized threading mode
        # allows.
        @shared = library if library.respond_to?(:path) && library.path == Library::IN_MEMORY
        @cancelled = false
        @thread = nil
      end

      def running?
        @thread&.alive? || false
      end

      def cancel
        @cancelled = true
      end

      # Runs the scan on this thread. Yields Progress every batch.
      def scan(directories, &progress)
        @cancelled = false
        files = audio_files(Array(directories))
        counts = { scanned: 0, added: 0, updated: 0 }

        with_library do |library|
          files.each_slice(BATCH_SIZE) do |batch|
            break if @cancelled

            # Checked per file as well as per batch: cancelling a scan of ten
            # thousand tracks should stop it now, not at the next boundary.
            library.transaction do
              batch.each do |file|
                break if @cancelled

                record(library, file, counts)
              end
            end

            report(progress, counts, files.size)
          end
        end

        report(progress, counts, files.size) if files.empty?
        Progress.new(**counts, total: files.size)
      end

      # Runs the scan on a worker thread. Both callbacks are delivered on the
      # main loop, so they may touch widgets directly.
      def start(directories, on_progress: nil, on_finished: nil)
        return false if running?

        @thread = Thread.new do
          result = scan(directories) { |progress| idle { on_progress&.call(progress) } }
          idle { on_finished&.call(result) }
        rescue StandardError => e
          idle { on_finished&.call(e) }
        end

        true
      end

      # Stops for good: no further work, and no further callbacks. A scan
      # that finishes after the widgets it would report to have gone is a
      # crash rather than an error, so detaching has to be possible.
      def shutdown(timeout: 5)
        cancel
        @detached = true
        wait(timeout: timeout)
      end

      # Blocks until a running scan finishes. For tests and for shutdown.
      def wait(timeout: nil)
        @thread&.join(timeout)
        !running?
      end

      # Every audio file under the given folders, deduplicated — two watch
      # folders that overlap must not index the same track twice.
      def audio_files(directories)
        directories.flat_map { |directory| audio_files_in(directory) }
          .uniq
          .sort
      end

      private

      def audio_files_in(directory)
        root = File.expand_path(directory.to_s)
        return [root] if audio?(root) && File.file?(root)
        return [] unless File.directory?(root)

        Dir.glob(File.join(root, '**', '*'), File::FNM_DOTMATCH)
          .select { |entry| File.file?(entry) && audio?(entry) }
      end

      def audio?(entry)
        Playlist::AUDIO_EXTENSIONS.include?(File.extname(entry).downcase)
      end

      def record(library, file, counts)
        case library.add(file)
        when :added then counts[:added] += 1
        when :updated then counts[:updated] += 1
        end

        counts[:scanned] += 1
      rescue StandardError => e
        # One unreadable file must not abandon the other nine thousand.
        counts[:scanned] += 1
        warn "Skipped #{file}: #{e.message}"
      end

      def report(progress, counts, total)
        progress&.call(Progress.new(**counts, total: total))
      end

      def with_library(&)
        return yield(@shared) if @shared

        library = Library.new(path: @library_path)
        yield library
      ensure
        library&.close
      end

      # Outside a GLib main loop — in a plain test process — there is nothing
      # to schedule onto, so the block runs where it stands.
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
    end
  end
end
