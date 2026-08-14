# frozen_string_literal: true

require 'digest'

module Loamp
  class Lastfm
    ENDPOINT = 'https://ws.audioscrobbler.com/2.0/'

    def initialize(api_key:, secret: nil, session_key: nil, client: Http::Client.new,
                   endpoint: ENDPOINT)
      @api_key = api_key
      @secret = secret
      @session_key = session_key
      @client = client
      @endpoint = endpoint
    end

    def similar_artists(artist, limit: 50)
      fields = get('artist.getSimilar', artist: artist, limit: limit)
      Array(fields&.dig('similarartists', 'artist')).map do |row|
        [row['name'], row['match'].to_f, row['mbid']]
      end
    end

    def top_artists(tag, limit: 50)
      fields = get('tag.getTopArtists', tag: tag, limit: limit)
      Array(fields&.dig('topartists', 'artist'))
    end

    def submit(track, listened_at:, now_playing: false)
      return false unless authenticated? && track&.artist && track.title

      method = now_playing ? 'track.updateNowPlaying' : 'track.scrobble'
      parameters = { artist: track.artist, track: track.title, album: track.album,
                     duration: track.duration.to_i }
      parameters[:timestamp] = listened_at.to_i unless now_playing
      post(method, parameters)
    end

    private

    def get(method, parameters)
      query = common(method).merge(parameters).merge(format: 'json')
      response = @client.get("#{@endpoint}?#{Http::Client.query(query)}")
      response.success? ? response.json : nil
    end

    def post(method, parameters)
      fields = common(method).merge(parameters).merge(sk: @session_key)
      fields[:api_sig] = signature(fields)
      fields[:format] = 'json'
      response = @client.post(@endpoint, body: Http::Client.query(fields),
                                         headers: form_headers)
      response.success?
    end

    def common(method) = { method: method, api_key: @api_key }

    def signature(fields)
      text = fields.sort_by { |key, _value| key.to_s }
        .map { |key, value| "#{key}#{value}" }.join
      Digest::MD5.hexdigest("#{text}#{@secret}")
    end

    def form_headers = { 'Content-Type' => 'application/x-www-form-urlencoded' }
    def authenticated? = @api_key && @secret && @session_key
  end
end
