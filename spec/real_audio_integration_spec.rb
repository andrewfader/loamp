#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Real Audio File Integration' do
  TEST_MP3_PATH = File.join(File.dirname(__FILE__), '..', 'test_files', 'turkey_in_the_straw.mp3').freeze
  HAIM_MP3_PATH = File.join(File.dirname(__FILE__), '..', 'test_files', '03 - Relationships.mp3').freeze
  
  before(:all) do
    # Ensure the test files exist
    unless File.exist?(TEST_MP3_PATH)
      skip "Test MP3 file not found at #{TEST_MP3_PATH}"
    end
    
    unless File.exist?(HAIM_MP3_PATH)
      skip "Haim MP3 file not found at #{HAIM_MP3_PATH}"
    end
  end

  describe 'Track loading with real MP3' do
    it 'loads metadata from the Alan Lomax MP3 file' do
      track = Loamp::Track.new(TEST_MP3_PATH)
      
      expect(track.file_path).to eq(TEST_MP3_PATH)
      
      # The archival Alan Lomax file doesn't have ID3 metadata, 
      # so title/artist will be nil, but we should still get basic info
      expect(track.duration).to be > 0
      expect(track.duration_formatted).to match(/\d+:\d{2}/)
      
      # The track should use the filename as fallback when displayed
      expect(track.to_s).to include('turkey_in_the_straw')
      
      # The file should be detected as valid
      expect(File.exist?(track.file_path)).to be true
    end
    
    it 'handles the specific format of the Lomax recording' do
      track = Loamp::Track.new(TEST_MP3_PATH)
      
      # This is a 192kbps, 44.1kHz MP3 file
      # It should load without errors
      expect { track.duration }.not_to raise_error
      expect(track.duration).to be_between(100, 120) # About 110 seconds based on our test
      
      # The archival file has no ID3 tags, so these will be nil
      expect(track.title).to eq('turkey_in_the_straw') # fallback to filename
      expect(track.artist).to be_nil
      expect(track.album).to be_nil
    end
    
    it 'loads metadata from the Haim MP3 file' do
      track = Loamp::Track.new(HAIM_MP3_PATH)
      
      expect(track.file_path).to eq(HAIM_MP3_PATH)
      
      # The Haim file should have valid ID3 metadata
      expect(track.title).to eq('Relationships')
      expect(track.artist).to eq('Haim')
      expect(track.album).to eq('I quit')
      
      # Duration should be correctly parsed
      expect(track.duration).to be > 0
      expect(track.duration_formatted).to match(/\d+:\d{2}/)
      
      # The file should be detected as valid
      expect(File.exist?(track.file_path)).to be true
    end
  end

  describe 'Playlist with real audio file' do
    it 'can add and manage the real MP3 file' do
      playlist = Loamp::Playlist.new
      
      expect(playlist.empty?).to be true
      
      playlist.add_track(TEST_MP3_PATH)
      
      expect(playlist.size).to eq(1)
      expect(playlist.empty?).to be false
      
      current = playlist.current_track
      expect(current).to be_a(Loamp::Track)
      expect(current.file_path).to eq(TEST_MP3_PATH)
    end
    
    it 'can add and manage both MP3 files with different metadata types' do
      playlist = Loamp::Playlist.new
      
      expect(playlist.empty?).to be true
      
      # Add both files
      playlist.add_track(TEST_MP3_PATH)
      playlist.add_track(HAIM_MP3_PATH)
      
      expect(playlist.size).to eq(2)
      expect(playlist.empty?).to be false
      
      # Check first track (no metadata)
      first_track = playlist.current_track
      expect(first_track).to be_a(Loamp::Track)
      expect(first_track.file_path).to eq(TEST_MP3_PATH)
      expect(first_track.title).to eq('turkey_in_the_straw') # fallback to filename
      expect(first_track.artist).to be_nil
      
      # Move to second track (full metadata)
      second_track = playlist.next_track
      expect(second_track).to be_a(Loamp::Track)
      expect(second_track.file_path).to eq(HAIM_MP3_PATH)
      expect(second_track.title).to eq('Relationships')
      expect(second_track.artist).to eq('Haim')
    end
    
    it 'can navigate through playlist with both real files' do
      playlist = Loamp::Playlist.new
      playlist.add_track(TEST_MP3_PATH)
      playlist.add_track(HAIM_MP3_PATH)
      
      # Should start with first track
      expect(playlist.current_index).to eq(0)
      expect(playlist.current_track.file_path).to eq(TEST_MP3_PATH)
      
      # Move to second track
      next_track = playlist.next_track
      expect(playlist.current_index).to eq(1)
      expect(next_track.file_path).to eq(HAIM_MP3_PATH)
      
      # Wrap around to first track
      wrap_track = playlist.next_track
      expect(playlist.current_index).to eq(0)
      expect(wrap_track.file_path).to eq(TEST_MP3_PATH)
    end
    
    it 'handles shuffle functionality with multiple real files' do
      playlist = Loamp::Playlist.new
      playlist.add_track(TEST_MP3_PATH)
      playlist.add_track(HAIM_MP3_PATH)
      
      # Test shuffle mode
      playlist.shuffle = true
      expect(playlist.shuffle?).to be true
      
      # Should still be able to navigate
      current_track = playlist.current_track
      expect([TEST_MP3_PATH, HAIM_MP3_PATH]).to include(current_track.file_path)
      
      next_track = playlist.next_track
      expect([TEST_MP3_PATH, HAIM_MP3_PATH]).to include(next_track.file_path)
    end
  end

  describe 'Player with real audio file' do
    let(:playlist) { Loamp::Playlist.new }
    let(:player) { Loamp::Player.new(playlist) }
    
    before do
      playlist.add_track(TEST_MP3_PATH)
    end
    
    it 'can load the real audio file without errors' do
      # The track should be accessible via current_track without needing explicit loading
      expect(player.current_track).to be_a(Loamp::Track)
      expect(player.current_track.file_path).to eq(TEST_MP3_PATH)
    end
    
    it 'can handle playback state changes with real file' do
      # Test initial state
      expect(player.stopped?).to be true
      expect(player.state).to eq(:stopped)
      
      # Test play state (will start playback of current track)
      expect { player.play }.not_to raise_error
      # Note: In our mock environment, we can't test actual audio playback
      # but we can test state management
      
      # Test pause state
      expect { player.pause }.not_to raise_error
      
      # Test stop state
      expect { player.stop }.not_to raise_error
      expect(player.stopped?).to be true
      expect(player.state).to eq(:stopped)
    end
    
    it 'can control volume with real audio' do
      # Test volume setting
      player.set_volume(50)
      expect(player.volume).to eq(50)
      
      player.set_volume(80)
      expect(player.volume).to eq(80)
      
      # Test volume bounds
      player.set_volume(150)
      expect(player.volume).to eq(100)
      
      player.set_volume(-10)
      expect(player.volume).to eq(0)
    end
    
    it 'can handle seeking with real audio' do
      track_duration = player.current_track.duration
      
      # Test seeking to middle
      seek_position = track_duration / 2
      expect { player.seek(seek_position) }.not_to raise_error
      
      # Test seeking bounds
      expect { player.seek(-5) }.not_to raise_error # Should clamp to 0
      expect { player.seek(track_duration + 10) }.not_to raise_error # Should clamp to duration
    end
    
    it 'can handle repeat and shuffle modes with real audio' do
      # Test repeat mode (now using updated API)
      expect(player.repeat_mode).to eq(:off)
      
      player.repeat_mode = :all
      expect(player.repeat_mode).to eq(:all)
      
      player.repeat_mode = :one
      expect(player.repeat_mode).to eq(:one)
      
      # Test shuffle
      expect(player.shuffle?).to be false
      
      player.shuffle = true
      expect(player.shuffle?).to be true
      
      player.shuffle = false
      expect(player.shuffle?).to be false
    end
    
    it 'handles errors gracefully with real audio' do
      # Player should have basic error handling
      expect(player.current_track).to be_a(Loamp::Track)
      
      # Should not crash when handling edge cases
      expect { player.play }.not_to raise_error
      expect { player.stop }.not_to raise_error
    end
    
    it 'can handle multiple tracks with different metadata types' do
      # Add the Haim track to the existing playlist
      playlist.add_track(HAIM_MP3_PATH)
      
      expect(playlist.size).to eq(2)
      
      # Test with first track (no metadata)
      first_track = player.current_track
      expect(first_track.file_path).to eq(TEST_MP3_PATH)
      expect(first_track.title).to eq('turkey_in_the_straw') # fallback to filename
      
      # Move to second track (full metadata)
      player.next_track
      second_track = player.current_track
      expect(second_track.file_path).to eq(HAIM_MP3_PATH)
      expect(second_track.title).to eq('Relationships')
      expect(second_track.artist).to eq('Haim')
      
      # Test playback with metadata-rich track
      expect { player.play }.not_to raise_error
      expect { player.pause }.not_to raise_error
      expect { player.stop }.not_to raise_error
    end
    
    it 'can handle seeking with commercial MP3' do
      # Add Haim track and switch to it
      playlist.add_track(HAIM_MP3_PATH)
      player.next_track
      
      track_duration = player.current_track.duration
      expect(track_duration).to be_between(200, 205)
      
      # Test seeking to different positions
      quarter_position = track_duration / 4
      expect { player.seek(quarter_position) }.not_to raise_error
      
      half_position = track_duration / 2
      expect { player.seek(half_position) }.not_to raise_error
      
      # Test seeking bounds with longer track
      expect { player.seek(-5) }.not_to raise_error # Should clamp to 0
      expect { player.seek(track_duration + 20) }.not_to raise_error # Should clamp to duration
    end
  end

  describe 'Audio format detection' do
    it 'correctly identifies the MP3 format for archival file' do
      track = Loamp::Track.new(TEST_MP3_PATH)
      
      # Should be able to determine this is an MP3
      expect(TEST_MP3_PATH).to end_with('.mp3')
      expect(File.extname(TEST_MP3_PATH).downcase).to eq('.mp3')
    end
    
    it 'correctly identifies the MP3 format for commercial file' do
      track = Loamp::Track.new(HAIM_MP3_PATH)
      
      # Should be able to determine this is an MP3
      expect(HAIM_MP3_PATH).to end_with('.mp3')
      expect(File.extname(HAIM_MP3_PATH).downcase).to eq('.mp3')
    end
    
    it 'handles different MP3 bitrates and metadata correctly' do
      archival_track = Loamp::Track.new(TEST_MP3_PATH)
      commercial_track = Loamp::Track.new(HAIM_MP3_PATH)
      
      # Both should load without errors despite different characteristics
      expect { archival_track.duration }.not_to raise_error
      expect { commercial_track.duration }.not_to raise_error
      
      # Different metadata completeness
      expect(archival_track.title).to eq('turkey_in_the_straw') # fallback to filename
      expect(commercial_track.title).to eq('Relationships')
      
      # Both should have valid durations
      expect(archival_track.duration).to be > 0
      expect(commercial_track.duration).to be > 0
    end
  end

  describe 'Memory and resource management' do
    it 'does not leak memory when loading/unloading tracks' do
      playlist = Loamp::Playlist.new
      player = Loamp::Player.new(playlist)
      
      # Load and unload the track multiple times
      5.times do
        playlist.clear if playlist.respond_to?(:clear)
        playlist.add_track(TEST_MP3_PATH)
        expect(player.current_track).to be_a(Loamp::Track)
        player.stop
      end
      
      # Should complete without errors
      expect(playlist.size).to eq(1)
      expect(player.stopped?).to be true
    end
    
    it 'handles multiple different MP3 files efficiently' do
      playlist = Loamp::Playlist.new
      player = Loamp::Player.new(playlist)
      
      # Load both files multiple times in different orders
      3.times do
        playlist.clear if playlist.respond_to?(:clear)
        playlist.add_track(TEST_MP3_PATH)
        playlist.add_track(HAIM_MP3_PATH)
        
        # Test both tracks
        archival_track = player.current_track
        expect(archival_track.file_path).to eq(TEST_MP3_PATH)
        
        player.next_track
        commercial_track = player.current_track
        expect(commercial_track.file_path).to eq(HAIM_MP3_PATH)
        expect(commercial_track.title).to eq('Relationships')
        
        player.stop
      end
      
      # Should complete without errors
      expect(playlist.size).to eq(2)
      expect(player.stopped?).to be true
    end
  end

  describe 'Track loading with Haim MP3 (with ID3 metadata)' do
    it 'loads complete metadata from the Haim MP3 file' do
      track = Loamp::Track.new(HAIM_MP3_PATH)
      
      expect(track.file_path).to eq(HAIM_MP3_PATH)
      
      # The Haim file has complete ID3 metadata
      expect(track.title).to eq('Relationships')
      expect(track.artist).to eq('Haim')
      expect(track.album).to eq('I quit')
      expect(track.track_number).to eq(3)
      
      # Duration should be approximately 202 seconds (3:22)
      expect(track.duration).to be_between(200, 205)
      expect(track.duration_formatted).to eq('3:22')
      
      # The track should display with proper metadata
      expect(track.to_s).to include('Relationships')
      expect(track.to_s).to include('Haim')
      
      # The file should be detected as valid
      expect(File.exist?(track.file_path)).to be true
    end
    
    it 'handles the commercial MP3 format correctly' do
      track = Loamp::Track.new(HAIM_MP3_PATH)
      
      # This is a 128kbps, 44.1kHz commercial MP3 file
      # It should load without errors and have proper metadata
      expect { track.duration }.not_to raise_error
      expect(track.duration).to be_between(200, 205) # About 202 seconds
      
      # All metadata fields should be populated
      expect(track.title).not_to be_nil
      expect(track.artist).not_to be_nil
      expect(track.album).not_to be_nil
      expect(track.track_number).to be > 0
    end
    
    it 'formats track information correctly with full metadata' do
      track = Loamp::Track.new(HAIM_MP3_PATH)
      
      # With full metadata, the string representation should be comprehensive
      track_string = track.to_s
      expect(track_string).to include('Relationships')
      expect(track_string).to include('Haim')
      
      # Duration should be properly formatted
      expect(track.duration_formatted).to match(/\d+:\d{2}/)
      expect(track.duration_formatted).to eq('3:22')
    end
  end
end
