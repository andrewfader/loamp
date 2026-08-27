# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Loamp::Podcast::Directory do
  let(:client) { instance_double(Loamp::Http::Client) }
  let(:directory) { described_class.new(client: client) }

  describe '#search' do
    let(:body) do
      JSON.generate(
        'results' => [{
          'collectionName' => 'Reply All',
          'artistName' => 'Gimlet',
          'feedUrl' => 'https://feeds.test/replyall',
          'artworkUrl100' => 'https://art.test/ra.jpg',
          'primaryGenreName' => 'Technology',
          'collectionId' => 1,
        }]
      )
    end
    let(:response) { Loamp::Http::Client::Response.new(status: 200, body: body) }

    before { allow(client).to receive(:get).and_return(response) }

    it 'searches Apple’s podcast directory' do
      listing = directory.search('reply all').first

      expect(client).to have_received(:get).with(a_string_including('term=reply+all', 'media=podcast'))
      expect(listing.title).to eq('Reply All')
      expect(listing.artist).to eq('Gimlet')
      expect(listing.feed_url).to eq('https://feeds.test/replyall')
      expect(listing).to be_browsable
    end

    it 'does not request an empty query' do
      expect(directory.search('  ')).to eq([])
      expect(client).not_to have_received(:get)
    end

    it 'drops rows without a feed URL' do
      allow(client).to receive(:get).and_return(
        Loamp::Http::Client::Response.new(
          status: 200,
          body: JSON.generate('results' => [{ 'collectionName' => 'No Feed' }])
        )
      )

      expect(directory.search('x')).to eq([])
    end
  end

  describe '#popular' do
    let(:top) do
      Loamp::Http::Client::Response.new(
        status: 200,
        body: JSON.generate(
          'feed' => { 'entry' => [{ 'id' => { 'attributes' => { 'im:id' => '99' } } }] }
        )
      )
    end
    let(:lookup) do
      Loamp::Http::Client::Response.new(
        status: 200,
        body: JSON.generate(
          'results' => [{
            'collectionName' => 'The Daily',
            'artistName' => 'NYT',
            'feedUrl' => 'https://feeds.test/daily',
            'collectionId' => 99,
          }]
        )
      )
    end

    before do
      allow(client).to receive(:get).and_return(top, lookup)
    end

    it 'loads top charts then resolves feed URLs' do
      listing = directory.popular.first

      expect(client).to have_received(:get).with(a_string_including('toppodcasts'))
      expect(client).to have_received(:get).with(a_string_including('lookup', 'id=99'))
      expect(listing.title).to eq('The Daily')
      expect(listing.feed_url).to eq('https://feeds.test/daily')
    end

    it 'returns an empty list when the network fails' do
      allow(client).to receive(:get).and_raise(SocketError)

      expect(directory.popular).to eq([])
    end
  end
end
