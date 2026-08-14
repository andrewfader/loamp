# frozen_string_literal: true

module Loamp
  module Radio
    # Endless local-library station with feedback and explicit variety rules.
    class StationQueue
      ARTIST_WINDOW = 5
      ALBUM_CAP = 3

      attr_accessor :adventure

      def initialize(library:, graph:, seed:, seed_type: :artist, random: Random.new)
        @library = library
        @graph = graph
        @seed = seed
        @seed_type = seed_type
        @random = random
        @adventure = 0.5
        @played = {}
        @recent_artists = []
        @album_counts = Hash.new(0)
      end

      def next_track
        candidates = candidate_tracks.reject { |track| excluded?(track) }
        return nil if candidates.empty?

        chosen = weighted_pick(candidates)
        remember(chosen)
        chosen
      end

      def each
        return enum_for(__method__) unless block_given?

        while (track = next_track)
          yield track
        end
      end

      def thumbs_up(track) = @graph.feedback(track, 1)
      def thumbs_down(track) = @graph.feedback(track, -1)
      def ban_artist(artist) = @graph.ban_artist(artist)

      private

      def candidate_tracks
        tracks = @library.tracks(limit: -1)
        case @seed_type
        when :artist then artist_candidates(tracks)
        when :tag, :genre then tracks.select do |track|
          track.genre.to_s.downcase.include?(@seed.to_s.downcase)
        end
        when :decade then tracks.select { |track| decade?(track.year) }
        else tracks
        end
      end

      def artist_candidates(tracks)
        @similarity_weights = @graph.neighbours(@seed).to_h
        names = [@seed, *@similarity_weights.keys]
        selected = tracks.select do |track|
          names.include?(track.artist) || names.include?(track.musicbrainz_artist_id)
        end
        selected.empty? ? tracks.select { |track| track.artist == @seed } : selected
      end

      def decade?(year)
        start = @seed.to_i
        year.to_i >= start && year.to_i < start + 10
      end

      def excluded?(track)
        @played[track.file_path] || @recent_artists.include?(track.artist) ||
          @album_counts[[track.artist,
                         track.album]] >= ALBUM_CAP || @graph.artist_banned?(track.artist)
      end

      def weighted_pick(tracks)
        weighted = tracks.map { |track| [track, weight(track)] }
        target = @random.rand * weighted.sum(&:last)
        weighted.each do |track, value|
          target -= value
          return track if target <= 0
        end
        tracks.last
      end

      def weight(track)
        feedback = @graph.score(track)
        base = if feedback.positive?
                 2.0
               else
                 (feedback.negative? ? 0.15 : 1.0)
               end
        similarity = @similarity_weights&.fetch(track.musicbrainz_artist_id,
                                                @similarity_weights.fetch(track.artist, 1.0)) || 1.0
        # Familiar favours strong graph edges; adventurous favours the outer
        # edge of the known neighbourhood. The midpoint leaves ranking alone.
        exponent = 1.0 - (2.0 * @adventure.to_f.clamp(0, 1))
        distance_bias = similarity.to_f.clamp(0.1, 1.0)**exponent
        base * distance_bias
      end

      def remember(track)
        @played[track.file_path] = true
        @recent_artists << track.artist
        @recent_artists.shift while @recent_artists.length > ARTIST_WINDOW
        @album_counts[[track.artist, track.album]] += 1
      end
    end
  end
end
