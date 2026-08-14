# frozen_string_literal: true

module Loamp
  module CoverArt
    # Finds cover art on the network for a track that has none on disk.
    #
    # Two steps, and the first is often free: a file tagged by Picard already
    # says which release it belongs to, and the Cover Art Archive is keyed by
    # exactly that. Only an untagged file needs a search against MusicBrainz,
    # which is the slow, rate-limited half.
    #
    # Failure is reported, never raised. The distinction that matters is
    # between "this release has no cover", which is worth writing down, and
    # "nobody answered", which is not.
    class Fetcher
      Result = Struct.new(:image, :release_id, :definitive, keyword_init: true) do
        def found? = !image.nil?

        # Whether the answer came from the services rather than from the
        # network failing on the way to them.
        def definitive? = definitive
      end

      def initialize(musicbrainz: nil, archive: nil)
        @musicbrainz = musicbrainz || MusicBrainz.new
        @archive = archive || Archive.new
      end

      def fetch(track)
        release_id = release_id_for(track)
        return Result.new(image: nil, definitive: @musicbrainz.definitive?) unless release_id

        image = @archive.front(release_id)

        Result.new(image: image,
                   release_id: release_id,
                   definitive: image ? true : @archive.definitive?)
      end

      private

      # A tagged file skips the search, and with it the one-request-a-second
      # queue that makes filling a whole library slow.
      def release_id_for(track)
        track.musicbrainz_album_id ||
          @musicbrainz.release_id(artist: album_artist_of(track), album: track.album)
      end

      # Compilations are credited to the album artist; searching by the
      # performing artist would miss them.
      def album_artist_of(track)
        track.album_artist || track.artist
      end
    end
  end
end
