# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Radio::Store do
  let(:path) { File.join(AudioFixtures.fixture_dir, "radio-#{SecureRandom.hex(4)}.json") }
  let(:store) { described_class.new(path: path) }
  let(:station) do
    Loamp::Radio::Station.new(id: 'abc', name: 'KEXP', stream_uri: 'https://radio.test/live',
                              country: 'United States', tags: ['indie'])
  end

  after { FileUtils.rm_f(path) }

  it 'deduplicates favorites and remembers them across instances' do
    2.times { store.favorite(station) }

    expect(store.favorites.map(&:id)).to eq(['abc'])
    expect(described_class.new(path: path)).to be_favorite(station)

    store.unfavorite(station)
    expect(store).not_to be_favorite(station)
  end

  it 'keeps recent history without the played-at timestamp leaking into Station' do
    store.played(station)

    expect(store.history.first.name).to eq('KEXP')
    expect(store.history.first).not_to respond_to(:played_at)
  end

  it 'starts empty when the file is missing or corrupt' do
    File.write(path, '{nope')
    expect(described_class.new(path: path).favorites).to eq([])
  end
end
