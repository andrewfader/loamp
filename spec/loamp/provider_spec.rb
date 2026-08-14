# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Provider do
  let(:item) do
    Loamp::Provider::Item.new(id: '1', title: 'Song', artist: 'Artist', album: 'Album',
                              duration: 42, playable: true, provider: :music)
  end

  it 'turns playable provider items into tracks' do
    provider = Class.new(Loamp::Provider::Base) do
      def resolve_stream_uri(_item) = 'https://music.test/stream'
    end.new

    track = provider.track_for(item)
    expect(track.file_path).to eq('https://music.test/stream')
    expect(track).to have_attributes(title: 'Song', artist: 'Artist', album: 'Album', duration: 42)
  end

  it 'supports non-playable metadata providers' do
    expect(Loamp::Provider::Base.new.track_for(item)).to be_nil
  end

  it 'aggregates providers and isolates a failing provider' do
    good = instance_double(Loamp::Provider::Base, search: [item], track_for: :track)
    bad = instance_double(Loamp::Provider::Base)
    allow(bad).to receive(:search).and_raise('offline')
    registry = Loamp::Provider::Registry.new
    registry.register(:music, good)
    registry.register(:bad, bad)

    expect(registry.search('song')).to eq([item])
    expect(registry.track_for(item)).to eq(:track)
    expect(registry[:missing]).to be_nil
    expect(registry.to_a.map(&:first)).to eq(%i[music bad])
  end
end
