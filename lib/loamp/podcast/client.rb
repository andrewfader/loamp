# frozen_string_literal: true

module Loamp
  module Podcast
    class Client
      def initialize(http: Http::Client.new, parser: Parser.new)
        @http = http
        @parser = parser
      end

      def fetch(url)
        types = 'application/rss+xml, application/atom+xml, text/xml'
        response = @http.get(url, headers: { 'Accept' => types })
        return nil unless response.success?

        @parser.parse(response.body, url: url)
      rescue StandardError
        nil
      end
    end
  end
end
