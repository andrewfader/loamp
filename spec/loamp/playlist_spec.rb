# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Playlist do
  let(:playlist) { described_class.new }
  let(:test_file1) { '/tmp/song1.mp3' }
  let(:test_file2) { '/tmp/song2.mp3' }
  let(:test_file3) { '/tmp/song3.flac' }

  before do
    # Mock File operations
    allow(File).to receive(:exist?).and_return(true)
    allow(File).to receive(:file?).and_return(true)
    
    # Mock Dir operations for directory scanning
    allow(Dir).to receive(:exist?).and_return(true)
    allow(Dir).to receive(:glob).and_return([test_file1, test_file2, test_file3])
    
    # Mock Track creation
    allow(Loamp::Track).to receive(:new).and_call_original
  end

  describe '#initialize' do
    it 'creates an empty playlist' do
      expect(playlist.tracks).to be_empty
      expect(playlist.current_index).to eq(0)
    end
  end

  describe '#add_track' do
    it 'adds a track to the playlist' do
      track = playlist.add_track(test_file1)
      
      expect(playlist.tracks.size).to eq(1)
      expect(track).to be_a(Loamp::Track)
      expect(track.file_path).to eq(test_file1)
    end

    it 'returns the created track' do
      track = playlist.add_track(test_file1)
      expect(track).to be_a(Loamp::Track)
    end
  end

  describe '#add_directory' do
    let(:test_directory) { '/tmp/music' }

    context 'when directory exists' do
      before do
        allow(Dir).to receive(:exist?).with(test_directory).and_return(true)
        allow(Dir).to receive(:glob).with(File.join(test_directory, '**', '*'))
                                   .and_return([test_file1, test_file2, test_file3])
      end

      it 'adds all audio files from the directory' do
        playlist.add_directory(test_directory)
        expect(playlist.tracks.size).to eq(3)
      end
    end

    context 'when directory does not exist' do
      before do
        allow(Dir).to receive(:exist?).with(test_directory).and_return(false)
      end

      it 'does not add any tracks' do
        playlist.add_directory(test_directory)
        expect(playlist.tracks).to be_empty
      end
    end
  end

  describe '#current_track' do
    context 'with empty playlist' do
      it 'returns nil' do
        expect(playlist.current_track).to be_nil
      end
    end

    context 'with tracks in playlist' do
      before do
        playlist.add_track(test_file1)
        playlist.add_track(test_file2)
      end

      it 'returns the current track' do
        track = playlist.current_track
        expect(track).to be_a(Loamp::Track)
        expect(track.file_path).to eq(test_file1)
      end
    end
  end

  describe '#next_track' do
    before do
      playlist.add_track(test_file1)
      playlist.add_track(test_file2)
      playlist.add_track(test_file3)
    end

    it 'advances to the next track' do
      playlist.next_track
      expect(playlist.current_index).to eq(1)
      expect(playlist.current_track.file_path).to eq(test_file2)
    end

    it 'wraps around to the first track at the end' do
      playlist.instance_variable_set(:@current_index, 2)
      playlist.next_track
      expect(playlist.current_index).to eq(0)
      expect(playlist.current_track.file_path).to eq(test_file1)
    end

    context 'with empty playlist' do
      let(:empty_playlist) { described_class.new }

      it 'returns nil' do
        expect(empty_playlist.next_track).to be_nil
      end
    end
  end

  describe '#previous_track' do
    before do
      playlist.add_track(test_file1)
      playlist.add_track(test_file2)
      playlist.add_track(test_file3)
      playlist.instance_variable_set(:@current_index, 1)
    end

    it 'goes back to the previous track' do
      playlist.previous_track
      expect(playlist.current_index).to eq(0)
      expect(playlist.current_track.file_path).to eq(test_file1)
    end

    it 'wraps around to the last track at the beginning' do
      playlist.instance_variable_set(:@current_index, 0)
      playlist.previous_track
      expect(playlist.current_index).to eq(2)
      expect(playlist.current_track.file_path).to eq(test_file3)
    end
  end

  describe '#set_current_track' do
    before do
      playlist.add_track(test_file1)
      playlist.add_track(test_file2)
      playlist.add_track(test_file3)
    end

    context 'with valid index' do
      it 'sets the current track to the specified index' do
        track = playlist.set_current_track(2)
        expect(playlist.current_index).to eq(2)
        expect(track.file_path).to eq(test_file3)
      end
    end

    context 'with invalid index' do
      it 'returns nil for negative index' do
        expect(playlist.set_current_track(-1)).to be_nil
      end

      it 'returns nil for index beyond playlist size' do
        expect(playlist.set_current_track(10)).to be_nil
      end
    end
  end

  describe '#remove_at' do
    before do
      3.times { playlist.add_track(test_file1) }
    end

    it 'removes the track at the given index' do
      playlist.remove_at(1)

      expect(playlist.size).to eq(2)
    end

    it 'returns the removed track' do
      removed = playlist.remove_at(0)

      expect(removed).to be_a(Loamp::Track)
    end

    it 'keeps the cursor on the same track when an earlier one is removed' do
      playlist.set_current_track(2)
      current = playlist.current_track

      playlist.remove_at(0)

      expect(playlist.current_track).to equal(current)
      expect(playlist.current_index).to eq(1)
    end

    it 'leaves the cursor in place when a later track is removed' do
      playlist.set_current_track(0)

      playlist.remove_at(2)

      expect(playlist.current_index).to eq(0)
    end

    it 'clamps the cursor when the last track is removed' do
      playlist.set_current_track(2)

      playlist.remove_at(2)

      expect(playlist.current_index).to eq(1)
    end

    it 'resets the cursor when the playlist empties' do
      3.times { playlist.remove_at(0) }

      expect(playlist).to be_empty
      expect(playlist.current_index).to eq(0)
    end

    it 'ignores an index that is out of range' do
      expect(playlist.remove_at(99)).to be_nil
      expect(playlist.size).to eq(3)
    end

    it 'ignores a nil index' do
      expect(playlist.remove_at(nil)).to be_nil
      expect(playlist.size).to eq(3)
    end
  end

  describe '#clear' do
    before do
      playlist.add_track(test_file1)
      playlist.add_track(test_file2)
      playlist.instance_variable_set(:@current_index, 1)
    end

    it 'removes all tracks from the playlist' do
      playlist.clear
      expect(playlist.tracks).to be_empty
      expect(playlist.current_index).to eq(0)
    end
  end

  describe '#empty?' do
    it 'returns true for empty playlist' do
      expect(playlist.empty?).to be true
    end

    it 'returns false for playlist with tracks' do
      playlist.add_track(test_file1)
      expect(playlist.empty?).to be false
    end
  end

  describe '#size' do
    it 'returns the number of tracks' do
      expect(playlist.size).to eq(0)
      
      playlist.add_track(test_file1)
      playlist.add_track(test_file2)
      
      expect(playlist.size).to eq(2)
    end
  end

  describe '#each' do
    before do
      playlist.add_track(test_file1)
      playlist.add_track(test_file2)
    end

    it 'iterates over all tracks' do
      count = 0
      playlist.each { |track| count += 1 }
      expect(count).to eq(2)
    end

    it 'yields track objects' do
      playlist.each do |track|
        expect(track).to be_a(Loamp::Track)
      end
    end
  end

  describe '#[]' do
    before do
      playlist.add_track(test_file1)
      playlist.add_track(test_file2)
    end

    it 'returns track at specified index' do
      track = playlist[1]
      expect(track).to be_a(Loamp::Track)
      expect(track.file_path).to eq(test_file2)
    end
  end

  describe 'factory' do
    it 'creates an empty playlist' do
      playlist = build(:playlist, :empty)
      expect(playlist).to be_a(described_class)
      expect(playlist.empty?).to be true
    end

    it 'creates playlist with tracks' do
      playlist = build(:playlist)
      
      # Add tracks after creation
      3.times do |i|
        allow(File).to receive(:exist?).with("/tmp/track_#{i}.mp3").and_return(true)
        playlist.add_track("/tmp/track_#{i}.mp3")
      end
      
      expect(playlist).to be_a(described_class)
      expect(playlist.size).to eq(3)
    end

    it 'creates playlist with many tracks' do
      playlist = build(:playlist)
      
      # Add many tracks after creation
      10.times do |i|
        allow(File).to receive(:exist?).with("/tmp/many_track_#{i}.mp3").and_return(true)
        playlist.add_track("/tmp/many_track_#{i}.mp3")
      end
      
      expect(playlist).to be_a(described_class)
      expect(playlist.size).to eq(10)
    end
  end

  describe 'shuffle functionality' do
    before do
      playlist.add_track(test_file1)
      playlist.add_track(test_file2)
      playlist.add_track(test_file3)
    end

    describe '#enable_shuffle' do
      it 'enables shuffle mode' do
        playlist.enable_shuffle
        expect(playlist.shuffle?).to be(true)
      end

      it 'creates shuffle indices for all tracks' do
        playlist.enable_shuffle
        shuffle_indices = playlist.instance_variable_get(:@shuffle_indices)
        expect(shuffle_indices.length).to eq(3)
        expect(shuffle_indices.sort).to eq([0, 1, 2])
      end

      it 'sets shuffle position based on current index' do
        playlist.instance_variable_set(:@current_index, 1)
        playlist.enable_shuffle
        shuffle_indices = playlist.instance_variable_get(:@shuffle_indices)
        shuffle_position = playlist.instance_variable_get(:@shuffle_position)
        expect(shuffle_indices[shuffle_position]).to eq(1)
      end
    end

    describe '#disable_shuffle' do
      before { playlist.enable_shuffle }

      it 'disables shuffle mode' do
        playlist.disable_shuffle
        expect(playlist.shuffle?).to be(false)
      end

      it 'clears shuffle indices' do
        playlist.disable_shuffle
        shuffle_indices = playlist.instance_variable_get(:@shuffle_indices)
        expect(shuffle_indices).to be_empty
      end

      it 'resets shuffle position' do
        playlist.disable_shuffle
        shuffle_position = playlist.instance_variable_get(:@shuffle_position)
        expect(shuffle_position).to eq(0)
      end
    end

    describe '#shuffle_next' do
      before { playlist.enable_shuffle }

      it 'advances to next position in shuffle order' do
        initial_position = playlist.instance_variable_get(:@shuffle_position)
        track = playlist.shuffle_next
        new_position = playlist.instance_variable_get(:@shuffle_position)
        expect(new_position).to eq((initial_position + 1) % 3)
        expect(track).to be_a(Loamp::Track)
      end

      it 'wraps around at end of shuffle order' do
        # Set to last position
        playlist.instance_variable_set(:@shuffle_position, 2)
        playlist.shuffle_next
        new_position = playlist.instance_variable_get(:@shuffle_position)
        expect(new_position).to eq(0)
      end

      it 'returns nil for empty playlist' do
        empty_playlist = described_class.new
        empty_playlist.enable_shuffle
        expect(empty_playlist.shuffle_next).to be_nil
      end

      it 'returns nil when shuffle is disabled' do
        playlist.disable_shuffle
        expect(playlist.shuffle_next).to be_nil
      end
    end

    describe '#shuffle_previous' do
      before { playlist.enable_shuffle }

      it 'goes to previous position in shuffle order' do
        # Start at position 1
        playlist.instance_variable_set(:@shuffle_position, 1)
        track = playlist.shuffle_previous
        new_position = playlist.instance_variable_get(:@shuffle_position)
        expect(new_position).to eq(0)
        expect(track).to be_a(Loamp::Track)
      end

      it 'wraps around at beginning of shuffle order' do
        # Set to first position
        playlist.instance_variable_set(:@shuffle_position, 0)
        playlist.shuffle_previous
        new_position = playlist.instance_variable_get(:@shuffle_position)
        expect(new_position).to eq(2)
      end

      it 'returns nil for empty playlist' do
        empty_playlist = described_class.new
        empty_playlist.enable_shuffle
        expect(empty_playlist.shuffle_previous).to be_nil
      end

      it 'returns nil when shuffle is disabled' do
        playlist.disable_shuffle
        expect(playlist.shuffle_previous).to be_nil
      end
    end

    describe '#shuffle=' do
      it 'enables shuffle when set to true' do
        expect(playlist).to receive(:enable_shuffle)
        playlist.shuffle = true
      end

      it 'disables shuffle when set to false' do
        playlist.enable_shuffle
        expect(playlist).to receive(:disable_shuffle)
        playlist.shuffle = false
      end

      it 'handles truthy values' do
        expect(playlist).to receive(:enable_shuffle)
        playlist.shuffle = 'yes'
      end

      it 'handles falsy values' do
        playlist.enable_shuffle
        expect(playlist).to receive(:disable_shuffle)
        playlist.shuffle = nil
      end
    end

    describe 'integration with normal navigation' do
      before { playlist.enable_shuffle }

      it 'updates current_index when shuffle navigation is used' do
        old_index = playlist.current_index
        playlist.shuffle_next
        new_index = playlist.current_index
        expect(new_index).not_to eq(old_index)
      end

      it 'maintains shuffle state when tracks are added' do
        playlist.add_track('/tmp/new_track.mp3')
        expect(playlist.shuffle?).to be(true)
        # Shuffle indices should be updated but we don't test the exact order
        # since it's randomized
      end
    end
  end

  describe 'navigation helpers' do
    before do
      playlist.add_track(test_file1)
      playlist.add_track(test_file2)
      playlist.add_track(test_file3)
    end

    describe '#has_next?' do
      it 'returns true when not at last track' do
        playlist.instance_variable_set(:@current_index, 0)
        expect(playlist.has_next?).to be(true)
      end

      it 'returns false when at last track' do
        playlist.instance_variable_set(:@current_index, 2)
        expect(playlist.has_next?).to be(false)
      end

      it 'returns false for empty playlist' do
        empty_playlist = described_class.new
        expect(empty_playlist.has_next?).to be(false)
      end
    end

    describe '#has_previous?' do
      it 'returns true when not at first track' do
        playlist.instance_variable_set(:@current_index, 1)
        expect(playlist.has_previous?).to be(true)
      end

      it 'returns false when at first track' do
        playlist.instance_variable_set(:@current_index, 0)
        expect(playlist.has_previous?).to be(false)
      end

      it 'returns false for empty playlist' do
        empty_playlist = described_class.new
        expect(empty_playlist.has_previous?).to be(false)
      end
    end

    describe '#select_track' do
      it 'is an alias for set_current_track' do
        expect(playlist.method(:select_track)).to eq(playlist.method(:set_current_track))
      end
    end
  end
end
