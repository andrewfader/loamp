# frozen_string_literal: true

module Loamp
  class MusicbrainzArtist
    ENDPOINT = 'https://musicbrainz.org/ws/2/artist/'
    MIN_SCORE = 80

    def initialize(client: nil, endpoint: ENDPOINT)
      limiter = Http::RateLimiter.new(interval: 1.0)
      @client = client || Http::Client.new(limiter: limiter)
      @endpoint = endpoint
    end

    def resolve(name)
      text = name.to_s.strip
      return nil if text.empty?

      query = Http::Client.query(query: %(artist:"#{escape(text)}"), fmt: 'json', limit: 5)
      response = @client.get("#{@endpoint}?#{query}", headers: { 'Accept' => 'application/json' })
      artists = response.success? ? response.json&.dig('artists') : nil
      match = Array(artists).max_by { |artist| artist['score'].to_i }
      if match && match['score'].to_i >= MIN_SCORE && match['id'].to_s.match?(Metadata::MBID)
        match['id']
      end
    rescue StandardError
      nil
    end

    private

    def escape(text) = text.gsub(/["\\]/) { |character| "\\#{character}" }
  end
end
