# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Loamp::PlaylistFile do
  let(:playlist) { Loamp::Playlist.new }
  let(:path) { File.join(Dir.tmpdir, "loamp-#{SecureRandom.hex(4)}.m3u8") }

  after { FileUtils.rm_f(path) }

  it 'round trips local tracks through extended M3U' do
    playlist.add_track(AudioFixtures.sample_mp3)

    expect(described_class.save(path, playlist)).to eq(1)
    expect(described_class.load(path)).to eq([AudioFixtures.sample_mp3])
  end

  it 'resolves relative entries from the playlist location' do
    File.write(path, "#EXTM3U\nmusic/song.mp3\n")

    expect(described_class.load(path)).to eq([File.join(File.dirname(path), 'music/song.mp3')])
  end

  it 'preserves remote stream URIs' do
    File.write(path, "https://radio.example/live\n")

    expect(described_class.load(path)).to eq(['https://radio.example/live'])
  end

  it 'ignores comments and blank lines' do
    File.write(path, "#EXTM3U\n# a comment\n\n/tmp/song.flac\n")

    expect(described_class.load(path)).to eq(['/tmp/song.flac'])
  end

  it 'appends imported entries to an existing queue' do
    File.write(path, "/tmp/one.mp3\n/tmp/two.mp3\n")

    expect(described_class.append_to(playlist, path)).to eq(2)
    expect(playlist.tracks.map(&:file_path)).to eq(['/tmp/one.mp3', '/tmp/two.mp3'])
  end
end
