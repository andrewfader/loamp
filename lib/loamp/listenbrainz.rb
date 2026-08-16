# frozen_string_literal: true

module Loamp
  class ListenBrainz
    API = 'https://api.listenbrainz.org/1'
    LABS = 'https://labs.api.listenbrainz.org'
    # Labs refuses similar-artist queries without an algorithm. This is the
    # long-window session dataset the public viewer uses by default.
    SIMILAR_ALGORITHM = 'session_based_days_7500_session_300_contribution_5_' \
                        'threshold_10_limit_100_filter_True_skip_30'

    def initialize(token: nil, client: Http::Client.new, api: API, labs: LABS)
      @token = token
      @client = client
      @api = api
      @labs = labs
    end

    def similar_artists(mbid)
      return [] unless mbid.to_s.match?(Metadata::MBID)

      query = Http::Client.query(artist_mbid: mbid, artist_mbids: mbid,
                                 algorithm: SIMILAR_ALGORITHM)
      response = @client.get("#{@labs}/similar-artists/json?#{query}")
      rows = response.success? ? response.json : nil
      list = rows.is_a?(Hash) ? [rows] : Array(rows)
      list.filter_map do |row|
        next unless row.is_a?(Hash)

        id = row['artist_mbid'] || row['mbid']
        name = row['name'] || row['artist_name']
        [id, (row['score'] || row['similarity']).to_f, name] if id
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
