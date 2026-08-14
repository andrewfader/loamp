# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::ListenBrainz do
  let(:response) do
    body = [{ 'artist_mbid' => 'related', 'score' => 0.8 }]
    Loamp::Http::Client::Response.new(status: 200, body: JSON.generate(body))
  end
  let(:client) { instance_double(Loamp::Http::Client, get: response, post: response) }
  let(:service) { described_class.new(token: 'token', client: client) }

  it 'normalizes similar artists from the public Labs endpoint' do
    stub_const('Loamp::Metadata::MBID', /\A[a-f0-9-]{36}\z/i)
    allow(client).to receive(:get).and_return(response)
    expect(service.similar_artists('12345678-1234-1234-1234-123456789abc')).to eq([['related', 0.8]])
    expect(service.similar_artists('not-an-mbid')).to eq([])
  end

  it 'submits now-playing and completed listens with authorization' do
    track = Loamp::Track.new('/tmp/song.mp3', metadata: Loamp::Metadata.new(
      title: 'Song', artist: 'Artist', album: 'Album', duration: 60
    ))

    expect(service.submit(track, listened_at: 123, now_playing: true)).to be(true)
    expect(service.submit(track, listened_at: 123)).to be(true)
    expect(client).to have_received(:post).twice.with(
      include('/submit-listens'), body: kind_of(String),
                                  headers: include('Authorization' => 'Token token')
    )
  end
end
