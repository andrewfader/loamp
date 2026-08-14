# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Provider::Subsonic do
  let(:body) do
    { 'subsonic-response' => { 'status' => 'ok', 'searchResult3' => {
      'song' => [{ 'id' => '1', 'title' => 'Song', 'artist' => 'Artist', 'duration' => 123 }]
    } } }
  end
  let(:response) { Loamp::Http::Client::Response.new(status: 200, body: JSON.generate(body)) }
  let(:client) { instance_double(Loamp::Http::Client, get: response) }
  let(:provider) do
    described_class.new(url: 'https://music.test', username: 'me', password: 'secret', client: client)
  end

  it 'searches for playable songs' do
    item = provider.search('song').first
    expect(item.title).to eq('Song')
    expect(item).to be_playable
  end

  it 'resolves an authenticated stream URL without exposing the password' do
    uri = provider.resolve_stream_uri(provider.search('song').first)
    expect(uri).to include('/rest/stream.view?', 'id=1', 't=', 's=')
    expect(uri).not_to include('secret')
  end
end
