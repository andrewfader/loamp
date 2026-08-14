# frozen_string_literal: true

module Loamp
  class ListenBrainz
    API = 'https://api.listenbrainz.org/1'
    LABS = 'https://labs.api.listenbrainz.org'

    def initialize(token: nil, client: Http::Client.new, api: API, labs: LABS)
      @token = token
      @client = client
      @api = api
      @labs = labs
    end

    def similar_artists(mbid)
      return [] unless mbid.to_s.match?(Metadata::MBID)

      query = Http::Client.query(artist_mbids: mbid)
      response = @client.get("#{@labs}/similar-artists/json?#{query}")
      rows = response.success? ? response.json : nil
      Array(rows).filter_map do |row|
        id = row['artist_mbid'] || row['mbid']
        [id, (row['score'] || row['similarity']).to_f] if id
      end
    end

    def submit(track, listened_at:, now_playing: false)
      return false unless @token && track&.artist && track.title

      payload = { listen_type: now_playing ? 'playing_now' : 'single',
                  payload: [listen(track, listened_at, now_playing)] }
      response = @client.post("#{@api}/submit-listens", body: JSON.generate(payload),
                                                        headers: auth_headers)
      response.success?
    end

    private

    def listen(track, listened_at, now_playing)
      metadata = { artist_name: track.artist, track_name: track.title,
                   release_name: track.album }
      {}.tap do |entry|
        entry[:listened_at] = listened_at.to_i unless now_playing
        entry[:track_metadata] = metadata
      end
    end

    def auth_headers
      { 'Authorization' => "Token #{@token}", 'Content-Type' => 'application/json' }
    end
  end
end
