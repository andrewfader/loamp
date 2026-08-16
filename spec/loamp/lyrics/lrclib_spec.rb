# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Lyrics::Lrclib do
  let(:server) { StubHttpServer.new }
  let(:client) { described_class.new(client: Loamp::Http::Client.new, endpoint: server.url_for('/get')) }
  let(:track) { AudioFixtures.track_with(title: 'Song', artist: 'Artist', album: 'Album', duration: 90) }

  after { server.stop }

  it 'parses synced lyrics from a successful reply' do
    server.on('/get', body: JSON.generate('syncedLyrics' => "[00:01.00]Hello\n[00:02.00]There\n"))

    document = client.fetch(track)

    expect(document.source).to eq(:lrclib)
    expect(document.lines).to eq([[1.0, 'Hello'], [2.0, 'There']])
    expect(client).to be_definitive
  end

  it 'falls back to plain lyrics when nothing is timed' do
    server.on('/get', body: JSON.generate('syncedLyrics' => '', 'plainLyrics' => 'Hello There'))

    document = client.fetch(track)

    expect(document.plain).to eq('Hello There')
    expect(document).not_to be_synced
  end

  it 'returns nil for a track with no title or artist' do
    expect(client.fetch(AudioFixtures.track_with(title: '', artist: ''))).to be_nil
  end

  it 'returns nil when the service has no lyrics' do
    server.on('/get', status: 404, body: '{}')

    expect(client.fetch(track)).to be_nil
    expect(client).to be_definitive
  end
end
