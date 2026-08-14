# frozen_string_literal: true

require 'forwardable'

module Loamp
  # A single audio file and the tags that describe it.
  #
  # Tags are read once through Metadata; artwork is fetched lazily so building
  # a playlist of thousands of tracks stays cheap.
  class Track
    extend Forwardable

    DELEGATED = (Metadata::ATTRIBUTES - [:duration]).freeze

    attr_reader :file_path, :metadata

    def_delegators :@metadata, *DELEGATED
    def_delegator :@metadata, :artwork?

    # Metadata can be supplied instead of read from disk, which is how the
    # library index rebuilds tracks from stored rows without touching the file.
    def initialize(file_path, metadata: nil)
      @file_path = file_path
      @metadata = metadata || Metadata.read(file_path)
      @duration = @metadata.duration
    end

    # Writable because the audio engine reports a more accurate duration than
    # the tag once a track is actually decoded.
    attr_accessor :duration

    def to_s
      return "#{artist} - #{title}" if artist && title
      return title if title

      File.basename(@file_path, File.extname(@file_path))
    end

    def duration_formatted
      total = @duration.to_i
      format('%d:%02d', total / 60, total % 60)
    end

    # Reads the embedded cover art from disk on demand.
    def artwork
      Metadata.artwork(@file_path)
    end
  end
end
