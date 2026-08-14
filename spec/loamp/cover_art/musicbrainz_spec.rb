# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::CoverArt::MusicBrainz do
  subject(:musicbrainz) { described_class.new(client: Loamp::Http::Client.new, base_url: server.url_for('')) }

  let(:server) { StubHttpServer.new }
  let(:release_id) { AudioFixtures::MUSICBRAINZ_ALBUM_ID }

  after { server.stop }

  # The shape MusicBrainz actually answers a release search with.
  def results(*releases)
    JSON.generate(count: releases.size, releases: releases)
  end

  def route(body, status: 200)
    server.on('/release', status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def last_query
    URI.decode_www_form(server.requests.last.query).to_h
  end

  describe '#release_id' do
    it 'returns the id of the best-scoring release' do
      route(results({ 'id' => release_id, 'score' => 100 }, { 'id' => 'other', 'score' => 60 }))

      expect(musicbrainz.release_id(artist: 'Radiohead', album: 'OK Computer')).to eq(release_id)
    end

    it 'picks the best score whatever order they arrived in' do
      route(results({ 'id' => 'weak', 'score' => 85 }, { 'id' => release_id, 'score' => 99 }))

      expect(musicbrainz.release_id(artist: 'Radiohead', album: 'OK Computer')).to eq(release_id)
    end

    # A wrong cover is worse than no cover.
    it 'refuses a match too weak to trust' do
      route(results({ 'id' => release_id, 'score' => 40 }))

      expect(musicbrainz.release_id(artist: 'Radiohead', album: 'OK Computer')).to be_nil
    end

    it 'returns nil when nothing matched' do
      route(results)

      expect(musicbrainz.release_id(artist: 'Nobody', album: 'Nothing')).to be_nil
    end

    it 'does not ask at all for a track with no album' do
      expect(musicbrainz.release_id(artist: 'Radiohead', album: '')).to be_nil
      expect(server.requests).to be_empty
    end

    it 'searches by album alone when the artist is unknown' do
      route(results({ 'id' => release_id, 'score' => 100 }))

      musicbrainz.release_id(artist: nil, album: 'OK Computer')

      expect(last_query['query']).to eq('release:"OK Computer"')
    end

    it 'searches by both when it knows both' do
      route(results({ 'id' => release_id, 'score' => 100 }))

      musicbrainz.release_id(artist: 'Radiohead', album: 'OK Computer')

      expect(last_query['query']).to eq('release:"OK Computer" AND artist:"Radiohead"')
    end

    it 'asks for JSON' do
      route(results)

      musicbrainz.release_id(artist: 'Radiohead', album: 'OK Computer')

      expect(last_query['fmt']).to eq('json')
      expect(server.requests.last.headers['accept']).to eq('application/json')
    end

    # Lucene reads these as syntax, and album titles are full of them.
    it 'escapes the punctuation a search would otherwise read as syntax' do
      route(results)

      musicbrainz.release_id(artist: 'David Bowie', album: 'Where Are We Now?')

      expect(last_query['query']).to include('release:"Where Are We Now\\?"')
    end

    it 'survives a reply that is not the JSON it claimed to be' do
      route('<html>down for maintenance</html>')

      expect(musicbrainz.release_id(artist: 'Radiohead', album: 'OK Computer')).to be_nil
    end

    it 'survives a reply with no releases in it at all' do
      route(JSON.generate(error: 'nope'))

      expect(musicbrainz.release_id(artist: 'Radiohead', album: 'OK Computer')).to be_nil
    end

    it 'returns nil rather than raising when the service is unreachable' do
      unreachable = described_class.new(client: Loamp::Http::Client.new, base_url: 'http://127.0.0.1:1')

      expect(unreachable.release_id(artist: 'Radiohead', album: 'OK Computer')).to be_nil
    end
  end

  # Whether a miss is worth remembering depends on who said so.
  describe '#definitive?' do
    it 'is true when MusicBrainz answered, even with nothing' do
      route(results)
      musicbrainz.release_id(artist: 'Nobody', album: 'Nothing')

      expect(musicbrainz).to be_definitive
    end

    it 'is false when it was too busy to answer' do
      route('slow down', status: 503)
      musicbrainz.release_id(artist: 'Radiohead', album: 'OK Computer')

      expect(musicbrainz).not_to be_definitive
    end

    it 'is false before anything has been asked' do
      expect(musicbrainz).not_to be_definitive
    end
  end

  describe 'politeness' do
    it 'defaults to a client that waits a second between requests' do
      limiter = described_class.default_client.instance_variable_get(:@limiter)

      expect(limiter).to be_a(Loamp::Http::RateLimiter)
      expect(limiter.interval).to be >= 1.0
    end
  end
end
