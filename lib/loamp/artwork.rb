# frozen_string_literal: true

module Loamp
  # Finds cover art for a track.
  #
  # Looks in the places art actually lives, cheapest first: embedded in the
  # file's own tag, then a conventionally named image sitting in the same
  # folder. Network lookups belong in a separate provider layered on top of
  # this, so that displaying art never blocks on the internet.
  module Artwork
    # Reuses Metadata's shape so callers handle one kind of object.
    Image = Metadata::Artwork

    # The filenames ripping tools and music managers actually write. Matched
    # case insensitively, since these come from every OS there is.
    FOLDER_ART_NAMES = %w[cover folder front album albumart].freeze
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp .bmp .gif].freeze

    MIME_TYPES = {
      '.jpg' => 'image/jpeg',
      '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.bmp' => 'image/bmp',
      '.gif' => 'image/gif',
    }.freeze

    module_function

    def for(track)
      return nil unless track&.file_path

      embedded(track) || folder_art(track.file_path)
    end

    def embedded(track)
      Metadata.artwork(track.file_path)
    rescue StandardError
      nil
    end

    # Looks for cover.jpg and friends next to the track.
    def folder_art(file_path)
      directory = File.dirname(file_path.to_s)
      return nil unless File.directory?(directory)

      path = find_folder_art(directory)
      return nil unless path

      Image.new(data: File.binread(path), mime_type: mime_type_for(path))
    rescue StandardError
      nil
    end

    # Names are checked in preference order, so "cover" wins over "albumart".
    def find_folder_art(directory)
      entries = Dir.children(directory)

      matches = FOLDER_ART_NAMES.filter_map do |name|
        entries.find { |entry| folder_art_match?(entry, name) }
      end

      matches.map { |entry| File.join(directory, entry) }.find { |path| File.file?(path) }
    rescue SystemCallError
      nil
    end

    def folder_art_match?(entry, name)
      extension = File.extname(entry).downcase
      return false unless IMAGE_EXTENSIONS.include?(extension)

      File.basename(entry, File.extname(entry)).casecmp?(name)
    end

    def mime_type_for(path)
      MIME_TYPES.fetch(File.extname(path).downcase, 'application/octet-stream')
    end
  end
end
