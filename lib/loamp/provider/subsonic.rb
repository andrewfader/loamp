# frozen_string_literal: true

require 'digest'
require 'securerandom'

module Loamp
  module Provider
    # Open Subsonic API, shared by Subsonic, Navidrome and compatible servers.
    class Subsonic < Base
      API_VERSION = '1.16.1'

      def initialize(url:, username:, password:, client: Http::Client.new)
        super()
        @url = url.to_s.delete_suffix('/')
        @username = username
        @password = password
        @client = client
      end

      def ping = request('ping').is_a?(Hash)

      def search(query, limit: 50)
        body = request('search3', query: query, songCount: limit, albumCount: 0, artistCount: 0)
        songs = body&.dig('searchResult3', 'song')
        Array(songs).map { |song| item_from(song) }
      end

      def browse(parent = nil)
        body = parent ? request('getMusicDirectory', id: parent) : request('getIndexes')
        rows = parent ? body&.dig('directory', 'child') : body&.dig('indexes', 'index')
        Array(rows).flat_map { |row| row.is_a?(Hash) && row['artist'] ? row['artist'] : row }
      end

      def resolve_stream_uri(item)
        return nil unless item&.playable?

        endpoint('stream', id: item.id)
      end

      private

      def request(method, parameters = {})
        response = @client.get(endpoint(method, parameters))
        return nil unless response.success?

        response.json&.dig('subsonic-response')&.then do |body|
          body['status'] == 'ok' ? body : nil
        end
      end

      def endpoint(method, parameters = {})
        salt = SecureRandom.hex(8)
        authentication = {
          u: @username, t: Digest::MD5.hexdigest("#{@password}#{salt}"), s: salt,
          v: API_VERSION, c: 'loamp', f: 'json'
        }
        query = Http::Client.query(authentication.merge(parameters))
        "#{@url}/rest/#{method}.view?#{query}"
      end

      def item_from(song)
        Item.new(id: song['id'], title: song['title'], artist: song['artist'],
                 album: song['album'], duration: song['duration'].to_f,
                 playable: true, provider: :subsonic, data: song)
      end
    end
  end
end
