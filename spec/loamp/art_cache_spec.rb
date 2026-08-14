# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Loamp::ArtCache do
  let(:cache_dir) { File.join(AudioFixtures.fixture_dir, "art-cache-#{SecureRandom.hex(4)}") }
  let(:cache) { described_class.new(directory: cache_dir) }

  after { FileUtils.rm_rf([cache_dir, @album_dir].compact) }

  describe '#url_for' do
    it 'returns nil without a track' do
      expect(cache.url_for(nil)).to be_nil
    end

    it 'writes embedded artwork out and points at the file' do
      track = Loamp::Track.new(AudioFixtures.sample_mp3_with_tags)

      url = cache.url_for(track)

      expect(url).to start_with('file://')
      expect(File.size(Loamp::FileUri.to_path(url))).to be_positive
    end

    it 'points straight at a cover image sitting beside the track' do
      track = Loamp::Track.new(track_in_album_folder)

      expect(Loamp::FileUri.to_path(cache.url_for(track))).to eq(File.join(album_dir, 'cover.png'))
    end

    it 'returns nil for a track with no art anywhere' do
      expect(cache.url_for(Loamp::Track.new(AudioFixtures.sample_mp3))).to be_nil
    end

    it 'answers a repeat lookup without reading the file again' do
      track = Loamp::Track.new(AudioFixtures.sample_mp3_with_tags)
      first = cache.url_for(track)

      expect(Loamp::Artwork).not_to receive(:embedded)
      expect(cache.url_for(track)).to eq(first)
    end

    it 'remembers a miss so it is not looked up again either' do
      track = Loamp::Track.new(AudioFixtures.sample_mp3)
      cache.url_for(track)

      expect(Loamp::Artwork).not_to receive(:embedded)
      expect(cache.url_for(track)).to be_nil
    end

    it 'shares one cached file between tracks from the same album' do
      first = AudioFixtures.track_with(album: 'Kid A', album_artist: 'Radiohead')
      second = AudioFixtures.track_with(file_path: '/tmp/other.mp3', album: 'Kid A',
                                        album_artist: 'Radiohead')
      allow(Loamp::Artwork).to receive_messages(find_folder_art: nil, embedded: image)

      expect(cache.url_for(first)).to eq(cache.url_for(second))
      expect(Dir.children(cache_dir).size).to eq(1)
    end

    it 'names the cached file after the image type' do
      track = AudioFixtures.track_with(album: 'Kid A')
      allow(Loamp::Artwork).to receive_messages(find_folder_art: nil, embedded: image)

      expect(cache.url_for(track)).to end_with('.png')
    end
  end

  # The network half. Lookups run on a worker thread and report back on the
  # main loop; outside one, ArtCache runs the callback where it stands, so a
  # spec only has to wait for the thread.
  describe '#fetch_remote' do
    subject(:cache) { described_class.new(directory: cache_dir, fetcher: fetcher, miss_log: miss_log) }

    let(:fetcher) { instance_double(Loamp::CoverArt::Fetcher, fetch: nothing_found) }
    let(:miss_log) { Loamp::CoverArt::MissLog.new(path: File.join(cache_dir, 'misses.json')) }

    let(:track) { AudioFixtures.track_with(artist: 'Radiohead', album: 'OK Computer') }
    let(:found) { result(image: image, definitive: true) }
    let(:nothing_found) { result(definitive: true) }
    let(:unreachable) { result(definitive: false) }

    def result(image: nil, definitive: true)
      Loamp::CoverArt::Fetcher::Result.new(image: image, definitive: definitive)
    end

    after { cache.shutdown }

    # Waits for the worker, then returns whatever the callback was given.
    def fetch(for_track = track)
      delivered = Queue.new
      started = cache.fetch_remote(for_track) { |url| delivered << [url] }
      return :not_started unless started

      cache.wait
      pump
      delivered.empty? ? :nothing_delivered : delivered.pop.first
    end

    # Results are delivered on the GLib main loop, and no spec runs one, so it
    # has to be turned by hand.
    def pump
      context = GLib::MainContext.default
      context.iteration(false) while context.pending?
    end

    it 'writes what it found and points at the file' do
      allow(fetcher).to receive(:fetch).and_return(found)

      url = fetch

      expect(url).to start_with('file://')
      expect(File.binread(Loamp::FileUri.to_path(url))).to eq(png_bytes)
    end

    it 'makes what it found the answer to the next local lookup' do
      allow(fetcher).to receive(:fetch).and_return(found)
      fetch

      expect(cache.url_for(track)).to start_with('file://')
    end

    # Art is keyed by album, so one lookup covers every track on it.
    it 'answers for another track of the same album without asking again' do
      allow(fetcher).to receive(:fetch).and_return(found)
      fetch

      sibling = AudioFixtures.track_with(file_path: '/tmp/other.mp3', artist: 'Radiohead', album: 'OK Computer')

      expect(cache.url_for(sibling)).to start_with('file://')
    end

    it 'reports nothing found as nil rather than as an error' do
      expect(fetch).to be_nil
    end

    it 'does not look at all when the art is already known' do
      local = Loamp::Track.new(AudioFixtures.sample_mp3_with_tags)

      expect(cache.fetch_remote(local)).to be false
      expect(fetcher).not_to have_received(:fetch)
    end

    it 'does not look for a track with nothing to look it up by' do
      expect(cache.fetch_remote(AudioFixtures.track_with(artist: 'Someone'))).to be false
    end

    it 'looks for a tagged track even with no album title' do
      tagged = AudioFixtures.track_with(musicbrainz_album_id: AudioFixtures::MUSICBRAINZ_ALBUM_ID)

      expect(cache.fetch_remote(tagged)).to be true
    end

    it 'does nothing without a track' do
      expect(cache.fetch_remote(nil)).to be false
    end

    # An album with no cover anywhere must not cost a rate-limited search on
    # every play.
    describe 'remembering a miss' do
      it 'writes down a miss the services confirmed' do
        fetch

        expect(miss_log.size).to eq(1)
        expect(cache.fetch_remote(track)).to be false
      end

      it 'does not write down a miss the network caused' do
        allow(fetcher).to receive(:fetch).and_return(unreachable)

        fetch

        expect(miss_log.size).to eq(0)
        expect(cache.fetch_remote(track)).to be true
      end

      it 'does not write down a lookup that raised' do
        allow(fetcher).to receive(:fetch).and_raise('the network went away')

        expect(fetch).to be_nil
        expect(miss_log.size).to eq(0)
      end
    end

    it 'looks once for an album however many of its tracks ask at once' do
      allow(fetcher).to receive(:fetch) { sleep 0.05 and found }
      sibling = AudioFixtures.track_with(file_path: '/tmp/other.mp3', artist: 'Radiohead', album: 'OK Computer')

      expect(cache.fetch_remote(track)).to be true
      expect(cache.fetch_remote(sibling)).to be false

      cache.wait
      expect(fetcher).to have_received(:fetch).once
    end

    it 'can look again once the first lookup has finished' do
      fetch

      miss_log.forget

      expect(cache.fetch_remote(track)).to be true
    end

    # A result arriving at a window that has been closed is a crash, not an
    # error.
    it 'delivers nothing after it has been shut down' do
      cache.shutdown

      expect(cache.fetch_remote(track)).to be false
    end
  end

  describe '#forget' do
    it 'drops the memoised answer' do
      track = Loamp::Track.new(AudioFixtures.sample_mp3)
      cache.url_for(track)
      cache.forget

      expect(Loamp::Artwork).to receive(:embedded).and_return(nil)
      cache.url_for(track)
    end
  end

  def image
    Loamp::Metadata::Artwork.new(data: png_bytes, mime_type: 'image/png')
  end

  def png_bytes
    Base64.decode64(<<~PNG.delete("\n"))
      iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmM
      pgAAAABJRU5ErkJggg==
    PNG
  end

  def album_dir
    @album_dir ||= File.join(AudioFixtures.fixture_dir, "album-#{SecureRandom.hex(4)}").tap do |dir|
      FileUtils.mkdir_p(dir)
    end
  end

  def track_in_album_folder
    path = File.join(album_dir, 'track.mp3')
    FileUtils.cp(AudioFixtures.sample_mp3, path)
    File.binwrite(File.join(album_dir, 'cover.png'), png_bytes)
    path
  end
end
