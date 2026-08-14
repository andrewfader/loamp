# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Loamp::Track do
  describe '#initialize' do
    context 'with existing file' do
      let(:temp_file) { Tempfile.new(['test_track', '.mp3']) }
      
      after { temp_file.unlink }
      
      it 'creates a track with file path' do
        track = described_class.new(temp_file.path)
        expect(track.file_path).to eq(temp_file.path)
      end
      
      it 'loads metadata for existing file' do
        track = described_class.new(temp_file.path)
        expect(track.title).to include('test_track') # Tempfile creates unique names
        expect(track.duration).to eq(0) # Empty file causes error, fallback to 0
      end
    end
    
    context 'with non-existing file' do
      it 'falls back to the filename without inventing metadata' do
        track = described_class.new('/tmp/nonexistent.mp3')
        expect(track.title).to eq('nonexistent')
        expect(track.artist).to be_nil
        expect(track.album).to be_nil
        expect(track.track_number).to be_nil
        expect(track.duration).to eq(0)
      end
    end

    context 'with a fully tagged file' do
      let(:track) { described_class.new(AudioFixtures.sample_mp3_with_tags) }

      it 'reads real tags through taglib' do
        expect(track.title).to eq('Relationships')
        expect(track.artist).to eq('Haim')
        expect(track.album).to eq('I quit')
        expect(track.track_number).to eq(3)
        expect(track.year).to eq(2025)
      end

      it 'exposes the fields a music library needs' do
        expect(track.album_artist).to eq('Haim')
        expect(track.disc_number).to eq(1)
        expect(track.duration).to be_within(0.5).of(202.0)
      end

      it 'knows it has embedded artwork' do
        expect(track).to be_artwork
      end

      it 'loads the artwork only when asked' do
        expect(track.artwork.data.bytesize).to be > 10_000
      end
    end
  end
  
  describe '#to_s' do
    context 'with artist and title' do
      it 'returns formatted string' do
        track = AudioFixtures.track_with(artist: 'Test Artist', title: 'Test Song')

        expect(track.to_s).to eq('Test Artist - Test Song')
      end
    end

    context 'with title only' do
      it 'returns title' do
        track = AudioFixtures.track_with(title: 'Test Song', artist: nil)

        expect(track.to_s).to eq('Test Song')
      end
    end

    context 'with no metadata' do
      it 'returns filename without extension' do
        track = AudioFixtures.track_with(file_path: '/tmp/test_file.mp3', title: nil, artist: nil)

        expect(track.to_s).to eq('test_file')
      end
    end
  end
  
  describe '#duration_formatted' do
    it 'formats duration in M:SS format' do
      track = described_class.new('/tmp/test.mp3')
      track.duration = 125
      
      expect(track.duration_formatted).to eq('2:05')
    end
    
    it 'handles zero duration' do
      track = described_class.new('/tmp/test.mp3')
      track.duration = 0
      
      expect(track.duration_formatted).to eq('0:00')
    end
    
    it 'handles nil duration' do
      track = described_class.new('/tmp/test.mp3')
      track.duration = nil
      
      expect(track.duration_formatted).to eq('0:00')
    end
    
    it 'handles long durations' do
      track = described_class.new('/tmp/test.mp3')
      track.duration = 3665 # 1 hour, 1 minute, 5 seconds
      
      expect(track.duration_formatted).to eq('61:05')
    end
  end
  
  describe 'metadata loading' do
    context 'when the file cannot be parsed' do
      it 'falls back to the filename instead of raising' do
        invalid_file = Tempfile.new(['invalid', '.mp3'])
        invalid_file.write('invalid mp3 content')
        invalid_file.close

        track = described_class.new(invalid_file.path)

        expect(track.title).to include('invalid')
        expect(track.duration).to eq(0)

        invalid_file.unlink
      end
    end
    
    context 'with different file extensions' do
      it 'handles .flac files' do
        track = described_class.new('/tmp/test.flac')
        expect(track.title).to eq('test')
      end
      
      it 'handles .ogg files' do
        track = described_class.new('/tmp/test.ogg')
        expect(track.title).to eq('test')
      end
      
      it 'handles unknown extensions' do
        # Create a real file with unknown extension
        temp_file = Tempfile.new(['test', '.unknown'])
        temp_file.close
        
        track = described_class.new(temp_file.path)
        expect(track.title).to include('test') # Tempfile creates unique names
        expect(track.duration).to eq(0)
        
        temp_file.unlink
      end
    end
  end
  
  describe 'attribute access' do
    let(:track) { described_class.new('/tmp/test.mp3') }
    
    it 'allows reading file_path' do
      expect(track.file_path).to eq('/tmp/test.mp3')
    end
    
    it 'allows reading title' do
      expect(track.title).to be_a(String)
    end
    
    it 'reports no artist for an untagged file' do
      expect(track.artist).to be_nil
    end

    it 'reports no album for an untagged file' do
      expect(track.album).to be_nil
    end

    it 'reads typed values from a tagged file' do
      tagged = described_class.new(AudioFixtures.sample_mp3_with_tags)

      expect(tagged.artist).to be_a(String)
      expect(tagged.album).to be_a(String)
      expect(tagged.track_number).to be_a(Integer)
    end
    
    it 'allows reading and writing duration' do
      track.duration = 240
      expect(track.duration).to eq(240)
    end
  end
end
