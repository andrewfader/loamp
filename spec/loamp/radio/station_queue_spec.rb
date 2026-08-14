# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Radio::StationQueue do
  let(:library) { instance_double(Loamp::Library, tracks: tracks) }
  let(:graph) do
    instance_double(Loamp::Radio::GraphStore, neighbours: [], artist_banned?: false,
                                              score: 0, feedback: nil, ban_artist: nil)
  end
  let(:tracks) do
    8.times.map do |index|
      AudioFixtures.track_with(file_path: "/tmp/#{index}.mp3", title: "Track #{index}",
                               artist: "Artist #{index}", album: "Album #{index}")
    end
  end

  it 'does not repeat tracks or recently played artists' do
    station = described_class.new(library: library, graph: graph, seed: nil,
                                  seed_type: :library, random: Random.new(1))
    played = 8.times.filter_map { station.next_track }
    expect(played.map(&:file_path).uniq.size).to eq(played.size)
    expect(played.map(&:artist).uniq.size).to eq(played.size)
  end

  it 'persists steering feedback' do
    station = described_class.new(library: library, graph: graph, seed: nil, seed_type: :library)
    station.thumbs_down(tracks.first)
    station.ban_artist(tracks.first.artist)
    expect(graph).to have_received(:feedback).with(tracks.first, -1)
    expect(graph).to have_received(:ban_artist).with(tracks.first.artist)
  end
end
