# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Provider::Jellyfin do
  let(:body) do
    { 'Items' => [
      { 'Id' => 'audio 1', 'Name' => 'Song', 'Type' => 'Audio', 'Album' => 'Record',
        'RunTimeTicks' => 1_230_000_000, 'ArtistItems' => [{ 'Name' => 'Artist' }] },
      { 'Id' => 'album-1', 'Name' => 'Record', 'Type' => 'MusicAlbum' }
    ] }
  end
  let(:response) { Loamp::Http::Client::Response.new(status: 200, body: JSON.generate(body)) }
  let(:client) { instance_double(Loamp::Http::Client, get: response) }
  let(:provider) do
    described_class.new(url: 'https://jellyfin.test/', user_id: 'user', token: 'token', client: client)
  end

  it 'normalizes audio search results' do
    item = provider.search('song').first

    expect(item).to have_attributes(title: 'Song', artist: 'Artist', album: 'Record', duration: 123.0)
    expect(item).to be_playable
    expect(client).to have_received(:get).with(include('SearchTerm=song', 'UserId=user'),
                                               headers: { 'X-Emby-Token' => 'token' })
  end

  it 'browses containers and only marks audio as playable' do
    items = provider.browse('parent')

    expect(items.map(&:title)).to eq(%w[Song Record])
    expect(items.last).not_to be_playable
    expect(client).to have_received(:get).with(include('ParentId=parent'), anything)
  end

  it 'builds a stream URL for playable items only' do
    playable, container = provider.search('song')

    expect(provider.resolve_stream_uri(playable)).to eq(
      'https://jellyfin.test/Audio/audio+1/universal?api_key=token'
    )
    expect(provider.resolve_stream_uri(container)).to be_nil
  end

  it 'degrades to an empty result on an HTTP error' do
    failed = Loamp::Http::Client::Response.new(status: 503, body: '')
    allow(client).to receive(:get).and_return(failed)

    expect(provider.search('song')).to eq([])
  end
end
