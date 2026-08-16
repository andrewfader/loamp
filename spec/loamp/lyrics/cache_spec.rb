# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Lyrics::Cache do
  let(:directory) { File.join(AudioFixtures.fixture_dir, "lyrics-#{SecureRandom.hex(4)}") }
  let(:remote) { instance_double(Loamp::Lyrics::Lrclib, fetch: document, definitive?: true) }
  let(:resolver) { Loamp::Lyrics::Resolver.new(remote: remote) }
  let(:cache) { described_class.new(directory: directory, resolver: resolver) }
  let(:track) { AudioFixtures.track_with(title: 'Song', artist: 'Artist', album: 'Album', duration: 90) }
  let(:document) { Loamp::Lyrics::Document.new(plain: 'Hello', lines: [[1.0, 'Hello']], source: :lrclib) }

  after do
    cache.shutdown
    FileUtils.rm_rf(directory)
  end

  def pump
    context = GLib::MainContext.default
    context.iteration(false) while context.pending?
  end

  def fetch
    delivered = Queue.new
    started = cache.fetch_remote(track) { |result| delivered << result }
    return :not_started unless started

    cache.instance_variable_get(:@threads).each { |thread| thread.join(2) }
    pump
    delivered.empty? ? nil : delivered.pop
  end

  it 'returns embedded lyrics without hitting the network' do
    local = Loamp::Track.new('/tmp/song.mp3', metadata: Loamp::Metadata.new(lyrics: 'inside'))

    expect(cache.for(local).plain).to eq('inside')
    expect(cache.fetch_remote(local)).to be(false)
  end

  it 'writes a remote document so the next lookup is local' do
    expect(fetch.plain).to eq('Hello')
    expect(cache.for(track).source).to eq(:cache)
    expect(cache.for(track).plain).to eq('Hello')
  end

  it 'records a confirmed miss and does not look again' do
    allow(remote).to receive_messages(fetch: nil, definitive?: true)

    expect(fetch).to be_nil
    expect(cache.fetch_remote(track)).to be(false)
  end

  it 'does not start a second lookup for the same track' do
    allow(remote).to receive(:fetch) do
      sleep 0.05
      document
    end

    expect(cache.fetch_remote(track)).to be(true)
    expect(cache.fetch_remote(track)).to be(false)
    cache.instance_variable_get(:@threads).each { |thread| thread.join(2) }
    pump
  end
end
