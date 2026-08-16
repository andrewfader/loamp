# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::MusicbrainzArtist do
  let(:server) { StubHttpServer.new }
  let(:service) do
    described_class.new(client: Loamp::Http::Client.new, endpoint: server.url_for('/artist'))
  end
  let(:mbid) { '12345678-1234-1234-1234-123456789abc' }

  after { server.stop }

  it 'returns the highest-scoring artist above the threshold' do
    server.on('/artist') do |_request|
      body = JSON.generate('artists' => [
                             { 'id' => mbid, 'score' => 95 },
                             { 'id' => 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'score' => 80 },
                           ])
      [200, {}, body]
    end

    expect(service.resolve('Radiohead')).to eq(mbid)
  end

  it 'returns nil when no match is confident enough' do
    server.on('/artist', body: JSON.generate('artists' => [{ 'id' => mbid, 'score' => 20 }]))

    expect(service.resolve('asdf')).to be_nil
  end

  it 'returns nil for a blank name' do
    expect(service.resolve('  ')).to be_nil
  end
end
