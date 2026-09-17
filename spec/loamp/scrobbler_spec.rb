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
      scrobbler.wait
      expect(JSON.parse(File.read(path)).length).to eq(1)

      allow(service).to receive(:submit).and_return(true)
      time += Loamp::Scrobbler::RETRY_INTERVAL
      scrobbler.flush
      expect(JSON.parse(File.read(path))).to eq([])
      scrobbler.shutdown
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

  it 'does not count a seek as listening to the skipped part' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'queue.json')
      service = double('service', submit: false)
      scrobbler = described_class.new([service], path: path, clock: -> { 100 })
      scrobbler.track_started(track)
      scrobbler.tick(10, 300)
      scrobbler.seeked(200)
      scrobbler.tick(201, 300)
      expect(File).not_to exist(path)
      scrobbler.seeked(0)
      scrobbler.tick(139, 300)
      scrobbler.wait
      expect(JSON.parse(File.read(path)).length).to eq(1)
      scrobbler.shutdown
    end
  end

  it 'keeps the playback tick responsive while a submission is blocked' do
    Dir.mktmpdir do |directory|
      started = Queue.new
      release = Queue.new
      service = double('slow service')
      allow(service).to receive(:submit) do |_, now_playing:, **|
        unless now_playing
          started << true
          release.pop
        end
        false
      end
      path = File.join(directory, 'queue.json')
      scrobbler = described_class.new([service], path: path, clock: -> { 100 })
      scrobbler.track_started(track)
      Timeout.timeout(2) { scrobbler.tick(150, 300); started.pop }
      Timeout.timeout(2) { 5.times { scrobbler.tick(151, 300) } }
      release << true
      expect(scrobbler.wait).to be(true)
      expect(JSON.parse(File.read(path)).length).to eq(1)
      scrobbler.shutdown
    ensure
      release << true
      scrobbler&.shutdown
    end
  end

  it 'keeps a now-playing network error from escaping its worker' do
    Dir.mktmpdir do |directory|
      service = double('broken service')
      allow(service).to receive(:submit).and_raise(IOError, 'offline')
      scrobbler = described_class.new([service], path: File.join(directory, 'queue.json'))
      scrobbler.track_started(track)
      expect { scrobbler.wait }.not_to raise_error
      scrobbler.track_started(nil)
      scrobbler.shutdown
    end
  end
end
