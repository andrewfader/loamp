# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::FileUri do
  describe '.for' do
    it 'turns a local path into an absolute file URI' do
      expect(described_class.for('/home/user/song.mp3')).to eq('file:///home/user/song.mp3')
    end

    it 'expands a relative path against the working directory' do
      expect(described_class.for('song.mp3')).to eq("file://#{Dir.pwd}/song.mp3")
    end

    it 'escapes the spaces and accents real music libraries are full of' do
      uri = described_class.for('/music/Sigur Rós/Ágætis byrjun.flac')

      expect(uri).to eq('file:///music/Sigur%20R%C3%B3s/%C3%81g%C3%A6tis%20byrjun.flac')
    end

    it 'leaves the path separator alone' do
      expect(described_class.for('/a/b/c.mp3')).to include('/a/b/c.mp3')
    end

    it 'passes a URI through untouched' do
      expect(described_class.for('http://stream.example/live')).to eq('http://stream.example/live')
    end
  end

  describe '.uri?' do
    it 'recognises a scheme' do
      expect(described_class.uri?('https://example.com/a')).to be true
    end

    it 'does not mistake a path for a URI' do
      expect(described_class.uri?('/home/user/song.mp3')).to be false
    end
  end

  describe '.to_path' do
    it 'is the inverse of .for' do
      path = '/music/Sigur Rós/Ágætis byrjun.flac'

      expect(described_class.to_path(described_class.for(path))).to eq(path)
    end

    it 'accepts a bare path' do
      expect(described_class.to_path('/music/a.mp3')).to eq('/music/a.mp3')
    end

    it 'drops the host component of a file URI' do
      expect(described_class.to_path('file://localhost/music/a.mp3')).to eq('/music/a.mp3')
    end

    it 'refuses a URI that is not a local file' do
      expect(described_class.to_path('http://stream.example/live')).to be_nil
    end
  end
end
