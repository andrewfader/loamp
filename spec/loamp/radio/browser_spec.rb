# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Radio::Browser do
  let(:response) { Loamp::Http::Client::Response.new(status: 200, body: JSON.generate(rows)) }
  let(:client) { instance_double(Loamp::Http::Client, get: response) }
  let(:browser) { described_class.new(client: client, endpoint: 'https://radio.test/search') }
  let(:rows) do
    [{
      'stationuuid' => 'abc', 'name' => ' KEXP ', 'url' => 'http://old.test/live',
      'url_resolved' => 'https://stream.test/live', 'country' => 'United States',
      'language' => 'English', 'tags' => 'indie, alternative', 'codec' => 'AAC',
      'bitrate' => 128, 'votes' => 900
    }]
  end

  it 'searches for healthy stations and normalizes the response' do
    station = browser.search('kexp').first

    expect(client).to have_received(:get).with(a_string_including('name=kexp', 'hidebroken=true'))
    expect(station.name).to eq('KEXP')
    expect(station.stream_uri).to eq('https://stream.test/live')
    expect(station.tags).to eq(%w[indie alternative])
    expect(station.bitrate).to eq(128)
  end

  it 'loads popular stations without requiring a search term' do
    station = browser.popular.first

    expect(client).to have_received(:get).with(a_string_including('order=votes', 'reverse=true'))
    expect(client).to have_received(:get).with(satisfy { |url| !url.include?('name=') })
    expect(station.name).to eq('KEXP')
  end

  it 'builds a playable track without asking TagLib to read the URL' do
    track = browser.search('kexp').first.to_track

    expect(track.file_path).to eq('https://stream.test/live')
    expect(track.title).to eq('KEXP')
    expect(track.artist).to eq('United States')
    expect(track.duration).to eq(0)
  end

  it 'does not make a request for an empty search' do
    expect(browser.search('  ')).to eq([])
    expect(client).not_to have_received(:get)
  end

  it 'drops malformed and unplayable results' do
    rows.first['url_resolved'] = 'javascript:alert(1)'
    expect(browser.search('bad')).to eq([])
  end

  it 'turns network and JSON failures into an empty result' do
    allow(client).to receive(:get).and_raise(SocketError)
    expect(browser.search('offline')).to eq([])
  end
end
