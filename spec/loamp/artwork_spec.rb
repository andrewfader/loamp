# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Loamp::Artwork do
  # A directory holding a copy of a track plus whatever sidecar images the
  # example needs, so folder-art lookup is exercised against a real layout.
  let(:album_dir) do
    dir = File.join(AudioFixtures.fixture_dir, "album-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(dir)
    dir
  end

  let(:untagged_copy) do
    path = File.join(album_dir, 'track.mp3')
    FileUtils.cp(AudioFixtures.sample_mp3, path)
    path
  end

  def write_image(name)
    path = File.join(album_dir, name)
    # A real, minimal PNG.
    File.binwrite(path, Base64.decode64(<<~PNG.delete("\n")))
      iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmM
      IQAAAABJRU5ErkJggg==
    PNG
    path
  end

  after { FileUtils.rm_rf(album_dir) }

  describe '.for' do
    it 'prefers artwork embedded in the file' do
      track = Loamp::Track.new(AudioFixtures.sample_mp3_with_tags)

      artwork = described_class.for(track)

      expect(artwork.mime_type).to eq('image/jpeg')
      expect(artwork.data.bytesize).to be > 10_000
    end

    it 'falls back to cover art sitting beside the file' do
      write_image('cover.png')
      track = Loamp::Track.new(untagged_copy)

      artwork = described_class.for(track)

      expect(artwork).not_to be_nil
      expect(artwork.mime_type).to eq('image/png')
    end

    it 'recognises the common folder art filenames' do
      write_image('folder.png')
      track = Loamp::Track.new(untagged_copy)

      expect(described_class.for(track)).not_to be_nil
    end

    it 'matches folder art regardless of case' do
      write_image('Cover.PNG')
      track = Loamp::Track.new(untagged_copy)

      expect(described_class.for(track)).not_to be_nil
    end

    it 'ignores unrelated images in the folder' do
      write_image('band-photo.png')
      track = Loamp::Track.new(untagged_copy)

      expect(described_class.for(track)).to be_nil
    end

    it 'returns nil when there is no artwork anywhere' do
      track = Loamp::Track.new(untagged_copy)

      expect(described_class.for(track)).to be_nil
    end

    it 'returns nil for a track whose file is gone' do
      track = Loamp::Track.new('/nonexistent/gone.mp3')

      expect(described_class.for(track)).to be_nil
    end

    it 'returns nil rather than raising for a nil track' do
      expect(described_class.for(nil)).to be_nil
    end
  end
end
