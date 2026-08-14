# frozen_string_literal: true

# Shared test helpers and utilities

module TestHelpers
  # Helper method to create mock GTK widgets
  def mock_gtk_widget(widget_class, methods = {})
    widget = double(widget_class.to_s)
    
    # Common GTK widget methods
    common_methods = {
      show: nil,
      hide: nil,
      show_all: nil,
      destroy: nil,
      signal_connect: nil,
      set_size_request: nil,
      set_property: nil
    }
    
    common_methods.merge(methods).each do |method, return_value|
      allow(widget).to receive(method).and_return(return_value)
    end
    
    widget
  end
  
  # Helper to create a temporary audio file for testing
  def create_temp_audio_file(filename = 'test.mp3', metadata = {})
    temp_path = File.join('/tmp', filename)
    
    # Mock file existence
    allow(File).to receive(:exist?).with(temp_path).and_return(true)
    allow(File).to receive(:file?).with(temp_path).and_return(true)
    
    # Mock TagLib metadata
    if metadata.any?
      mock_tag = double('TagLib::Tag')
      metadata.each { |key, value| allow(mock_tag).to receive(key).and_return(value) }
      
      mock_properties = double('TagLib::AudioProperties', 
        length: metadata[:duration] || 180
      )
      
      mock_fileref = double('TagLib::FileRef',
        tag: mock_tag,
        audio_properties: mock_properties
      )
      
      allow(TagLib::FileRef).to receive(:open).with(temp_path).and_yield(mock_fileref)
    end
    
    temp_path
  end
  
  # Helper to suppress stdout during tests
  def silence_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original_stdout
  end
  
  # Helper to create a playlist with test tracks
  def create_test_playlist(track_count = 3)
    playlist = Loamp::Playlist.new
    
    track_count.times do |i|
      file_path = "/tmp/test_track_#{i}.mp3"
      track = double('Track',
        file_path: file_path,
        title: "Test Song #{i + 1}",
        artist: "Test Artist #{i + 1}",
        album: "Test Album",
        duration: 180 + i * 30,
        duration_formatted: "#{3 + i}:#{format('%02d', i * 30)}",
        track_number: i + 1,
        to_s: "Test Artist #{i + 1} - Test Song #{i + 1}"
      )
      
      playlist.instance_variable_get(:@tracks) << track
    end
    
    playlist
  end
end

# Include helpers in RSpec
RSpec.configure do |config|
  config.include TestHelpers
end
