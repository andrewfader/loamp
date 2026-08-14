# frozen_string_literal: true

module Loamp
  module Radio
    # Search client for the community-run radio-browser.info directory.
    class Browser
      ENDPOINTS = %w[
        https://de1.api.radio-browser.info/json/stations/search
        https://nl1.api.radio-browser.info/json/stations/search
        https://at1.api.radio-browser.info/json/stations/search
      ].freeze
      DEFAULT_LIMIT = 50
      MAX_LIMIT = 100

      def initialize(client: Http::Client.new, endpoint: nil)
        @client = client
        @endpoints = Array(endpoint || ENDPOINTS)
      end

      def search(query, limit: DEFAULT_LIMIT)
        text = query.to_s.strip
        return [] if text.empty?

        response = first_response({ name: text }, limit)
        stations_from(response)
      rescue StandardError
        []
      end

      # A useful landing page for RadioView. Radio Browser ranks this request
      # by community votes, so opening Radio never presents an unexplained
      # empty list and does not require guessing a search term first.
      def popular(limit: DEFAULT_LIMIT)
        response = first_response({}, limit)
        stations_from(response)
      rescue StandardError
        []
      end

      private

      def stations_from(response)
        return [] unless response&.success?

        Array(response.json).filter_map { |fields| station_from(fields) }
      end

      def first_response(filters, limit)
        @endpoints.each do |endpoint|
          response = @client.get(url_for(endpoint, filters, limit))
          return response if response.success?
        end
        nil
      end

      def url_for(endpoint, filters, limit)
        parameters = filters.merge(
          hidebroken: 'true',
          order: 'votes',
          reverse: 'true',
          limit: limit.to_i.clamp(1, MAX_LIMIT),
        )
        "#{endpoint}?#{Http::Client.query(parameters)}"
      end

      def station_from(fields)
        uri = fields['url_resolved'].to_s.strip
        uri = fields['url'].to_s.strip if uri.empty?

        station = Station.new(
          id: fields['stationuuid'], name: fields['name'].to_s.strip,
          stream_uri: uri, homepage: fields['homepage'], favicon: fields['favicon'],
          country: fields['country'], language: fields['language'],
          tags: fields['tags'].to_s.split(',').map(&:strip).reject(&:empty?),
          codec: fields['codec'], bitrate: fields['bitrate'].to_i,
          votes: fields['votes'].to_i
        )
        station if !station.name.empty? && station.playable?
      end
    end
  end
end
