# frozen_string_literal: true

module Loamp
  module Provider
    class Jellyfin < Base
      def initialize(url:, user_id:, token:, client: Http::Client.new)
        super()
        @url = url.to_s.delete_suffix('/')
        @user_id = user_id
        @token = token
        @client = client
      end

      def search(query, limit: 50)
        fields = get('/Items', SearchTerm: query, IncludeItemTypes: 'Audio',
                               Recursive: 'true', Limit: limit)
        Array(fields&.dig('Items')).map { |item| item_from(item) }
      end

      def browse(parent = nil)
        parameters = { IncludeItemTypes: 'MusicAlbum,MusicArtist,Audio', SortBy: 'SortName' }
        parameters[:ParentId] = parent if parent
        Array(get('/Items', parameters)&.dig('Items')).map { |item| item_from(item) }
      end

      def resolve_stream_uri(item)
        return nil unless item&.playable?

        "#{@url}/Audio/#{escape(item.id)}/universal?#{Http::Client.query(api_key: @token)}"
      end

      private

      def get(path, parameters = {})
        parameters[:UserId] = @user_id
        response = @client.get("#{@url}#{path}?#{Http::Client.query(parameters)}",
                               headers: { 'X-Emby-Token' => @token })
        response.success? ? response.json : nil
      end

      def item_from(item)
        artists = Array(item['ArtistItems']).map { |artist| artist['Name'] }
        Item.new(id: item['Id'], title: item['Name'], artist: artists.join(', '),
                 album: item['Album'], duration: item['RunTimeTicks'].to_i / 10_000_000.0,
                 playable: item['Type'] == 'Audio', provider: :jellyfin, data: item)
      end

      def escape(value) = URI.encode_www_form_component(value.to_s)
    end
  end
end
