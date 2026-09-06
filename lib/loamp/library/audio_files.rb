# frozen_string_literal: true

module Loamp
  class Library
    # Finding audio files on disk.
    #
    # The scanner walks folders to index them and the glob preview walks the
    # same folders to count what a pattern would pull in; both have to agree
    # on what counts as audio, or a dry run promises tracks the scan then
    # never adds.
    module AudioFiles
      module_function

      # Every audio file under a folder. A path that is itself an audio file
      # counts as one match, so a pattern may name files as readily as trees.
      def under(directory)
        root = File.expand_path(directory.to_s)
        return [root] if File.file?(root) && audio?(root)
        return [] unless File.directory?(root)

        Dir.glob(File.join(root, '**', '*'), File::FNM_DOTMATCH)
          .select { |entry| File.file?(entry) && audio?(entry) }
      end

      def count_under(directory)
        under(directory).size
      end

      def audio?(entry)
        Playlist::AUDIO_EXTENSIONS.include?(File.extname(entry).downcase)
      end
    end
  end
end
