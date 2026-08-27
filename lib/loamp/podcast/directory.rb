# frozen_string_literal: true

module Loamp
  module Podcast
    # Directory of podcasts to browse without knowing a feed URL.
    #
    # Uses Apple's public Search and Lookup APIs — no key, plain JSON — the
    # same shape Radio::Browser uses against Radio Browser. Top charts land
    # through the iTunes RSS feed, then a single lookup fills in feed URLs.
    class Directory
      SEARCH_URL = 'https://itunes.apple.com/search'
      LOOKUP_URL = 'https://itunes.apple.com/lookup'
      TOP_URL = 'https://itunes.apple.com/us/rss/toppodcasts/limit=%{limit}/json'
      DEFAULT_LIMIT = 40
      MAX_LIMIT = 50

      Listing = Struct.new(:title, :artist, :feed_url, :artwork_url, :genre,
                           :collection_id, keyword_init: true) do
        def subscribe_url = feed_url.to_s
        def browsable? = !subscribe_url.empty?
      end

      def initialize(client: Http::Client.new)
        @client = client
      end

      def search(query, limit: DEFAULT_LIMIT)
        text = query.to_s.strip
        return [] if text.empty?

        response = @client.get(search_url(text, limit))
        listings_from_search(response)
      rescue StandardError
        []
      end

      def popular(limit: DEFAULT_LIMIT)
        capped = limit.to_i.clamp(1, MAX_LIMIT)
        response = @client.get(format(TOP_URL, limit: capped))
        ids = collection_ids_from_top(response)
        return [] if ids.empty?

        listings_from_lookup(@client.get(lookup_url(ids)))
      rescue StandardError
        []
      end

      private

      def search_url(term, limit)
        parameters = {
          term: term,
          media: 'podcast',
          entity: 'podcast',
          limit: limit.to_i.clamp(1, MAX_LIMIT),
        }
        "#{SEARCH_URL}?#{Http::Client.query(parameters)}"
      end

      def lookup_url(ids)
        "#{LOOKUP_URL}?#{Http::Client.query(id: ids.join(','), entity: 'podcast')}"
      end

      def listings_from_search(response)
        return [] unless response&.success?

        Array(response.json&.dig('results')).filter_map { |row| listing_from(row) }
      end

      def listings_from_lookup(response)
        return [] unless response&.success?

        Array(response.json&.dig('results')).filter_map { |row| listing_from(row) }
      end

      def collection_ids_from_top(response)
        return [] unless response&.success?

        Array(response.json&.dig('feed', 'entry')).filter_map do |entry|
          entry.dig('id', 'attributes', 'im:id').to_s.then { |id| id unless id.empty? }
        end
      end

      def listing_from(row)
        feed = row['feedUrl'].to_s.strip
        title = row['collectionName'].to_s.strip
        return nil if feed.empty? || title.empty?

        Listing.new(
          title: title,
          artist: row['artistName'].to_s.strip,
          feed_url: feed,
          artwork_url: row['artworkUrl100'] || row['artworkUrl60'],
          genre: row['primaryGenreName'].to_s.strip,
          collection_id: row['collectionId'],
        )
      end
    end
  end
end
