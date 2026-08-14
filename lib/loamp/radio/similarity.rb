# frozen_string_literal: true

module Loamp
  module Radio
    class Similarity
      def initialize(graph:, listenbrainz: ListenBrainz.new, lastfm: nil,
                     musicbrainz: MusicbrainzArtist.new, library: nil)
        @graph = graph
        @listenbrainz = listenbrainz
        @lastfm = lastfm
        @musicbrainz = musicbrainz
        @library = library
      end

      def expand(artist:, mbid: nil)
        mbid ||= @musicbrainz.resolve(artist)
        key = mbid || artist
        cached = @graph.neighbours(key)
        return cached unless cached.empty?

        edges = mbid ? @listenbrainz.similar_artists(mbid) : lastfm_edges(artist)
        edges = local_edges(artist) if edges.empty?
        @graph.store_edges(key, edges)
        edges
      end

      private

      def lastfm_edges(artist)
        return [] unless @lastfm

        @lastfm.similar_artists(artist).map do |name, score, mbid|
          [mbid.to_s.empty? ? name : mbid, score]
        end
      end

      def local_edges(artist)
        return [] unless @library

        tracks = @library.tracks(limit: -1)
        genres = tracks.select { |track| track.artist == artist }
          .flat_map { |track| track.genre.to_s.downcase.split(/[,;]\s*/) }.uniq
        return [] if genres.empty?

        counts = Hash.new(0)
        tracks.each do |track|
          next if track.artist == artist

          tags = track.genre.to_s.downcase.split(/[,;]\s*/)
          counts[track.artist] += (genres & tags).length
        end
        counts.sort_by { |_name, count| -count }.first(50).map do |name, count|
          [name, count.to_f / genres.length]
        end
      end
    end
  end
end
