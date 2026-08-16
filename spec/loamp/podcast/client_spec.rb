# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Podcast::Client do
  let(:server) { StubHttpServer.new }
  let(:client) { described_class.new(http: Loamp::Http::Client.new) }

  after { server.stop }

  it 'parses a fetched RSS feed' do
    server.on('/feed', body: <<~XML)
      <rss version="2.0"><channel><title>Show</title>
        <item><title>One</title><enclosure url="https://cdn.test/one.mp3"/></item>
      </channel></rss>
    XML

    feed = client.fetch(server.url_for('/feed'))

    expect(feed.title).to eq('Show')
    expect(feed.episodes.first.title).to eq('One')
    expect(server.requests.first.headers['accept']).to include('application/rss+xml')
  end

  it 'returns nil when the feed cannot be read' do
    server.on('/feed', status: 500, body: 'nope')

    expect(client.fetch(server.url_for('/feed'))).to be_nil
  end
end
