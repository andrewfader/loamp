# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Scrobbler do
  let(:track) do
    Loamp::Track.new('/tmp/song.mp3', metadata: Loamp::Metadata.new(
      title: 'Song', artist: 'Artist', album: 'Album', duration: 300
    ))
  end

  it 'queues a listen at half the track and retries durable failures' do
    Dir.mktmpdir do |directory|
      time = 100
      service = double('scrobble service') # rubocop:disable RSpec/VerifiedDoubles
      allow(service).to receive(:submit).and_return(false)
      path = File.join(directory, 'queue.json')
      scrobbler = described_class.new([service], path: path, clock: -> { time })

      scrobbler.track_started(track)
      scrobbler.tick(149, 300)
      expect(File).not_to exist(path)
      scrobbler.tick(150, 300)
      expect(JSON.parse(File.read(path)).length).to eq(1)

      allow(service).to receive(:submit).and_return(true)
      time += Loamp::Scrobbler::RETRY_INTERVAL
      scrobbler.flush
      expect(JSON.parse(File.read(path))).to eq([])
    end
  end

  it 'restores a pending queue and preserves it when no matching service exists' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'queue.json')
      File.write(path, JSON.generate([{ 'track' => { 'title' => 'Old', 'artist' => 'Artist',
                                                     'album' => '', 'duration' => 60 },
                                       'listened_at' => 10, 'pending' => [2] }]))
      scrobbler = described_class.new([], path: path, clock: -> { 100 })

      scrobbler.flush
      scrobbler.shutdown
      expect(JSON.parse(File.read(path)).first['pending']).to eq([2])
    end
  end

  it 'ignores short tracks and invalid queue files' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'queue.json')
      File.write(path, 'not json')
      service = double('service', submit: true) # rubocop:disable RSpec/VerifiedDoubles
      scrobbler = described_class.new([service], path: path, clock: -> { 100 })
      scrobbler.track_started(track)
      scrobbler.tick(20, 20)
      scrobbler.shutdown

      expect(JSON.parse(File.read(path))).to eq([])
    end
  end
end
