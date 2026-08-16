# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Radio::Similarity do
  let(:graph) { Loamp::Radio::GraphStore.new(path: ':memory:') }
  let(:listenbrainz) { instance_double(Loamp::ListenBrainz, similar_artists: []) }
  let(:musicbrainz) { instance_double(Loamp::MusicbrainzArtist, resolve: nil) }
  let(:similarity) do
    described_class.new(graph: graph, listenbrainz: listenbrainz, lastfm: lastfm,
                        musicbrainz: musicbrainz, library: library)
  end
  let(:lastfm) { nil }
  let(:library) { nil }

  after { graph.close }

  it 'uses ListenBrainz when an MBID is known and caches the names' do
    allow(listenbrainz).to receive(:similar_artists).and_return(
      [['mbid-b', 0.9, 'Slowdive']],
    )

    expect(similarity.expand(artist: 'MBV', mbid: 'mbid-a')).to eq([['mbid-b', 0.9, 'Slowdive']])
    expect(similarity.expand(artist: 'MBV', mbid: 'mbid-a')).to eq([['mbid-b', 0.9, 'Slowdive']])
    expect(listenbrainz).to have_received(:similar_artists).once
  end

  it 'falls back to Last.fm when there is no MBID' do
    lastfm = instance_double(Loamp::Lastfm)
    allow(lastfm).to receive(:similar_artists).and_return([['Slowdive', 0.8, 'mbid-b']])
    service = described_class.new(graph: graph, listenbrainz: listenbrainz, lastfm: lastfm,
                                  musicbrainz: musicbrainz)

    expect(service.expand(artist: 'MBV')).to eq([['mbid-b', 0.8, 'Slowdive']])
  end

  it 'merges ListenBrainz, Last.fm and local library edges' do
    lastfm = instance_double(Loamp::Lastfm)
    allow(listenbrainz).to receive(:similar_artists).and_return([['mbid-b', 90, 'Slowdive']])
    allow(lastfm).to receive(:similar_artists).and_return([['Ride', 0.5, 'mbid-c']])
    library = instance_double(
      Loamp::Library,
      identify_artist: true, artist_index: { 'B' => true },
      tracks: [
        AudioFixtures.track_with(artist: 'MBV', genre: 'shoegaze'),
        AudioFixtures.track_with(file_path: '/tmp/b.mp3', artist: 'B', genre: 'shoegaze'),
      ]
    )
    service = described_class.new(graph: graph, listenbrainz: listenbrainz, lastfm: lastfm,
                                  musicbrainz: musicbrainz, library: library)

    names = service.expand(artist: 'MBV', mbid: 'mbid-a').map(&:last)
    expect(names).to include('Slowdive', 'Ride', 'B')
    expect(service).to be_local('B')
  end

  it 'builds local genre edges when remote services have nothing' do
    library = instance_double(
      Loamp::Library,
      tracks: [
        AudioFixtures.track_with(artist: 'A', genre: 'shoegaze'),
        AudioFixtures.track_with(file_path: '/tmp/b.mp3', artist: 'B', genre: 'shoegaze, dream pop'),
        AudioFixtures.track_with(file_path: '/tmp/c.mp3', artist: 'C', genre: 'jazz'),
      ],
    )
    service = described_class.new(graph: graph, listenbrainz: listenbrainz,
                                  musicbrainz: musicbrainz, library: library)

    expect(service.expand(artist: 'A')).to eq([['B', 1.0, 'B']])
  end
end
