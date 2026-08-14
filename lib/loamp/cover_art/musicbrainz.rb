# frozen_string_literal: true

module Loamp
  module CoverArt
    # Turns "an album by an artist" into the MusicBrainz release id that the
    # Cover Art Archive is keyed by.
    #
    # This step is skipped entirely for files tagged by Picard, which already
    # carry the id — see Metadata#musicbrainz_album_id. It exists for the rest
    # of a collection, which is most of it.
    #
    # MusicBrainz asks for no more than one request a second and enforces it,
    # so the client this is built with must carry a limiter. Nothing here
    # touches GTK; it is called from a worker thread.
    class MusicBrainz
      BASE_URL = 'https://musicbrainz.org/ws/2'

      # A shade over a second, because the limit is enforced against arrival
      # times and a request that leaves exactly on the second may not arrive
      # after it.
      INTERVAL = 1.1

      # Search results come back scored out of 100. A wrong cover is worse than
      # no cover, so a weak match is treated as no match at all.
      MINIMUM_SCORE = 80

      # Only the top few are worth looking at; the tail of a Lucene search is
      # noise.
      SEARCH_LIMIT = 5

      # Lucene reads all of these as syntax. Album titles contain most of them.
      LUCENE_SPECIAL = %r{([+\-!(){}\[\]^"~*?:\\/]|&&|\|\|)}

      # base_url is injectable so specs can point at a local server instead of
      # at MusicBrainz, whose rate limit is not there to be spent on tests.
      def initialize(client: nil, base_url: BASE_URL)
        @client = client || self.class.default_client
        @base_url = base_url
      end

      def self.default_client
        Http::Client.new(limiter: Http::RateLimiter.new(interval: INTERVAL))
      end

      # The release id for an album, or nil when nothing matched it well
      # enough. Raises nothing: a lookup that fails is a cover the player does
      # not have.
      def release_id(artist:, album:)
        return nil if album.to_s.strip.empty?

        response = search(artist: artist, album: album)
        return nil unless response.success?

        best_release(response.json)
      end

      # Whether the last answer was the service's own, rather than the network
      # failing on the way to it. Callers use it to decide whether a miss is
      # worth writing down.
      attr_reader :last_response

      def definitive?
        @last_response ? @last_response.definitive? : false
      end

      private

      def search(artist:, album:)
        @last_response = @client.get(search_url(artist: artist, album: album),
                                     headers: { 'Accept' => 'application/json' })
      end

      def search_url(artist:, album:)
        query = [%(release:#{quote(album)})]
        query << %(artist:#{quote(artist)}) unless artist.to_s.strip.empty?

        parameters = Http::Client.query(query: query.join(' AND '), fmt: 'json',
                                        limit: SEARCH_LIMIT)
        "#{@base_url}/release?#{parameters}"
      end

      # Quoting makes a title with spaces one term; escaping stops a title
      # containing Lucene syntax — "Where Are We Now?" — from being read as it.
      def quote(value)
        %("#{value.to_s.strip.gsub(LUCENE_SPECIAL, '\\\\\1')}")
      end

      def best_release(payload)
        releases = payload.is_a?(Hash) ? payload['releases'] : nil
        return nil unless releases.is_a?(Array)

        best = releases.grep(Hash).max_by { |release| release['score'].to_i }
        return nil unless best && best['score'].to_i >= MINIMUM_SCORE

        presence(best['id'])
      end

      def presence(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
