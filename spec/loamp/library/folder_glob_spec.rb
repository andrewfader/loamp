# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Loamp::Library::FolderGlob do
  let(:root) do
    dir = File.join(AudioFixtures.fixture_dir, "glob-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(dir)
    @root = dir
  end

  after { FileUtils.rm_rf(@root) if @root }

  def folder(*parts)
    File.join(root, *parts).tap { |path| FileUtils.mkdir_p(path) }
  end

  def track(directory, name)
    File.join(directory, name).tap { |path| FileUtils.touch(path) }
  end

  it 'matches folders recursively through **' do
    downloads = folder('mnt', 'one', 'downloads-2024')
    folder('mnt', 'two', 'albums')
    other = folder('mnt', 'three', 'downloads')

    result = described_class.preview(File.join(root, 'mnt', '**', 'downloads*'))

    expect(result.paths).to eq([downloads, other].sort)
  end

  it 'counts the audio files each match would index' do
    downloads = folder('downloads')
    track(downloads, 'a.mp3')
    track(File.join(downloads), 'notes.txt')
    track(folder('downloads', 'nested'), 'b.flac')

    result = described_class.preview(File.join(root, 'downloads'))

    expect(result.track_count).to eq(2)
  end

  it 'collapses a match that sits inside another match' do
    outer = folder('music')
    folder('music', 'music-extra')

    result = described_class.preview(File.join(root, '**', 'music*'))

    expect(result.paths).to eq([outer])
  end

  it 'marks matches the library already watches and leaves them out of addable' do
    watched = folder('watched')
    fresh = folder('fresh')

    result = described_class.preview(File.join(root, '*'), watched: [watched])

    expect(result.matches.select(&:watched?).map(&:path)).to eq([watched])
    expect(result.addable.map(&:path)).to eq([fresh])
  end

  it 'reports files that matched but cannot be watch roots' do
    folder('albums')
    track(root, 'loose.mp3')

    result = described_class.preview(File.join(root, '*'))

    expect(result.paths).to eq([File.join(root, 'albums')])
    expect(result.skipped_files).to eq(1)
  end

  it 'returns an error rather than every folder for an empty pattern' do
    result = described_class.preview('   ')

    expect(result).to be_error
    expect(result.matches).to be_empty
  end

  it 'reports no matches without failing' do
    result = described_class.preview(File.join(root, 'nothing-here', '*'))

    expect(result).to be_empty
    expect(result).not_to be_error
  end

  it 'expands ~ so a home-relative pattern means what it says in a shell' do
    result = described_class.preview('~', count_tracks: false)

    expect(result.paths).to eq([Dir.home])
  end

  it 'skips the track walk when only the folder list is wanted' do
    downloads = folder('downloads')
    track(downloads, 'a.mp3')

    result = described_class.preview(File.join(root, '*'), count_tracks: false)

    expect(result.matches.map(&:track_count)).to eq([nil])
  end

  it 'stops at MAX_MATCHES and says so' do
    stub_const("#{described_class}::MAX_MATCHES", 2)
    3.times { |index| folder("album-#{index}") }

    result = described_class.preview(File.join(root, '*'))

    expect(result.matches.size).to eq(2)
    expect(result.truncated).to be true
  end
end
