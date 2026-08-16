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
        remember_identity(artist, mbid)
        keys = [mbid, artist].compact.uniq
        cached = keys.filter_map { |key| @graph.neighbours(key) }.find { |edges| !edges.empty? }
        return cached if cached

        edges = merge_edges(listenbrainz_edges(mbid), lastfm_edges(artist), local_edges(artist))
        keys.each { |key| @graph.store_edges(key, edges) }
        edges
      end

      def local?(id, name = nil)
        index = library_index
        index[id] || index[name]
      end

      private

      def listenbrainz_edges(mbid)
        mbid ? @listenbrainz.similar_artists(mbid) : []
      rescue StandardError
        []
      end

      def lastfm_edges(artist)
        return [] unless @lastfm

        @lastfm.similar_artists(artist).map do |name, score, mbid|
          [mbid.to_s.empty? ? name : mbid, score, name]
        end
      rescue StandardError
        []
      end

      def local_edges(artist)
        return [] unless @library

        tracks = @library.tracks(limit: -1)
        genres = tracks.select { |track| same_artist?(track, artist) }
          .flat_map { |track| split_genres(track.genre) }.uniq
        return [] if genres.empty?

        counts = Hash.new(0)
        tracks.each do |track|
          next if same_artist?(track, artist)

          overlap = (genres & split_genres(track.genre)).length
          counts[track.artist] += overlap if overlap.positive? && track.artist
        end
        counts.sort_by { |_name, count| -count }.first(50).map do |name, count|
          [name, count.to_f / genres.length, name]
        end
      end

      def merge_edges(*groups)
        best = {}
        groups.each { |edges| merge_group(best, edges) }
        best.values.sort_by { |_, score, _| -score }
      end

      def merge_group(best, edges)
        normalize(edges).each do |id, score, name|
          next if id.to_s.empty?

          key = id.to_s.match?(Metadata::MBID) ? id : id.to_s.downcase
          current = best[key]
          if current.nil? || score > current[1]
            best[key] = [id, score, name.to_s.empty? ? current&.[](2) : name]
          elsif current[2].to_s.empty? && !name.to_s.empty?
            current[2] = name
          end
        end
      end

      def normalize(edges)
        max = edges.map { |_, score, _| score.to_f }.max.to_f
        return [] if max <= 0

        scale = max > 1 ? max : 1.0
        edges.map { |id, score, name| [id, score.to_f / scale, name] }
      end

      def remember_identity(artist, mbid)
        return unless mbid && @library.respond_to?(:identify_artist)

        @library.identify_artist(artist, mbid)
        @library_index = nil
      rescue StandardError
        nil
      end

      def library_index
        @library_index ||= if @library.respond_to?(:artist_index)
                             @library.artist_index
                           else
                             {}
                           end
      end

      def same_artist?(track, artist)
        needle = artist.to_s
        [track.artist, track.album_artist].compact.any? { |name| name.casecmp?(needle) }
      end

      def split_genres(value) = value.to_s.downcase.split(/[,;]\s*/)
    end
  end
end
