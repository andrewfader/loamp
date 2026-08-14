# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Lyrics::Resolver do
  let(:parser) { Loamp::Lyrics::LrcParser.new }
  let(:remote) { instance_double(Loamp::Lyrics::Lrclib, definitive?: true) }
  let(:resolver) { described_class.new(remote: remote, parser: parser) }

  it 'prefers embedded lyrics' do
    track = Loamp::Track.new('/tmp/song.mp3', metadata: Loamp::Metadata.new(lyrics: 'embedded'))

    expect(resolver.local(track)).to have_attributes(plain: 'embedded', source: :embedded)
  end

  it 'reads an lrc sidecar for local tracks' do
    Dir.mktmpdir do |directory|
      audio = File.join(directory, 'song.flac')
      File.write(File.join(directory, 'song.lrc'), "[00:01.00]First\n")
      track = Loamp::Track.new(audio, metadata: Loamp::Metadata.new)

      expect(resolver.local(track).lines).to eq([[1.0, 'First']])
    end
  end

  it 'delegates remote lookups and records whether a miss is definitive' do
    document = Loamp::Lyrics::Document.new(plain: 'remote', lines: [], source: :lrclib)
    track = Loamp::Track.new('/tmp/song.mp3', metadata: Loamp::Metadata.new)
    allow(remote).to receive(:fetch).with(track).and_return(document)

    expect(resolver.remote(track)).to eq(document)
    expect(resolver.last_definitive).to be(true)
  end
end
