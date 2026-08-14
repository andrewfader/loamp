# frozen_string_literal: true

module Loamp
  module Provider
    Item = Struct.new(
      :id, :title, :artist, :album, :duration, :artwork_url, :playable,
      :external_url, :provider, :data, keyword_init: true
    ) do
      def playable? = playable == true
    end

    class Base
      def search(*) = []
      def browse(_parent = nil) = []
      def resolve_stream_uri(_item) = nil

      def track_for(item)
        uri = resolve_stream_uri(item)
        return nil unless uri

        Track.new(uri, metadata: Metadata.new(title: item.title, artist: item.artist,
                                              album: item.album, duration: item.duration))
      end
    end

    class Registry
      include Enumerable

      def initialize
        @providers = {}
      end

      def register(name, provider)
        @providers[name.to_sym] = provider
      end

      def [](name) = @providers[name.to_sym]
      def each(&) = @providers.each(&)

      def search(query, limit: 50)
        @providers.flat_map do |name, provider|
          provider.search(query, limit: limit).map { |item| item.tap { item.provider ||= name } }
        rescue StandardError
          []
        end
      end

      def track_for(item)
        provider = self[item.provider]
        provider&.track_for(item)
      end
    end
  end
end
