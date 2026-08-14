# frozen_string_literal: true

module Loamp
  module Lyrics
    class Lrclib
      ENDPOINT = 'https://lrclib.net/api/get'

      def initialize(client: Http::Client.new, endpoint: ENDPOINT, parser: LrcParser.new)
        @client = client
        @endpoint = endpoint
        @parser = parser
      end

      attr_reader :last_response

      def fetch(track)
        return nil unless track && !track.title.to_s.empty? && !track.artist.to_s.empty?

        @last_response = @client.get(url(track))
        return nil unless @last_response.success?

        fields = @last_response.json
        return nil unless fields.is_a?(Hash)

        build_document(fields)
      rescue StandardError
        nil
      end

      def definitive? = @last_response ? @last_response.definitive? : false

      private

      def url(track)
        query = Http::Client.query(
          track_name: track.title, artist_name: track.artist,
          album_name: track.album,
          duration: track.duration.to_i.positive? ? track.duration.to_i : nil
        )
        "#{@endpoint}?#{query}"
      end

      def build_document(fields)
        synced = fields['syncedLyrics'].to_s
        return @parser.parse(synced, source: :lrclib) unless synced.empty?

        plain = fields['plainLyrics'].to_s.strip
        Document.new(plain: plain, lines: [], source: :lrclib) unless plain.empty?
      end
    end
  end
end
