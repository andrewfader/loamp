# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::MainWindow do
  before(:each) do
    skip_if_no_gtk
  end

  let(:playlist) { build(:playlist) }
  let(:engine) { AudioFixtures.silent_engine }
  let(:player) { Loamp::Player.new(playlist, engine: engine) }
  let(:windows) { [] }
  let(:main_window) { build_window(player, playlist) }

  after do
    windows.each do |window|
      window.shutdown
      window.destroy
    end
    engine.shutdown
  end

  # Every window built by an example goes through here so it can be shut down
  # afterwards. A window that is merely dropped is torn down whenever Ruby's GC
  # gets to it, which is long after the example: the popover PlaylistView
  # parents by hand outlives its parent, and GTK complains at process exit
  # about finalizing a widget that still has children.
  #
  # #shutdown is called by hand because ::destroy does not fire for a window
  # something still references — see MainWindow#setup_teardown.
  def build_window(...)
    described_class.new(...).tap { |window| windows << window }
  end

  # Puts the player at a known, real playback position so relative seek
  # shortcuts can be checked against something other than zero.
  def play_to_position(seconds)
    playlist.add_track(AudioFixtures.sample_mp3)
    playlist.set_current_track(playlist.size - 1)
    player.play
    engine.wait_for_state(:playing, timeout: 5)
    player.seek(seconds)
  end

  describe '#initialize' do
    it 'creates a main window' do
      expect(main_window).to be_a(described_class)
      expect(main_window).to be_a(Gtk::Window)
    end

    it 'sets window properties' do
      expect(main_window.title).to eq('LOAMP - Linux Open Audio Music Player')
      expect(main_window.default_width).to eq(Loamp::UI::MainWindow::DEFAULT_WIDTH)
      expect(main_window.default_height).to eq(Loamp::UI::MainWindow::DEFAULT_HEIGHT)
    end

    it 'is an Adwaita window' do
      expect(main_window).to be_a(Adw::Window)
    end

    it 'creates UI components' do
      # Access instance variables to verify components were created
      expect(main_window.instance_variable_get(:@player_controls)).to be_a(Loamp::UI::PlayerControls)
      expect(main_window.instance_variable_get(:@track_info)).to be_a(Loamp::UI::TrackInfo)
      expect(main_window.instance_variable_get(:@playlist_view)).to be_a(Loamp::UI::PlaylistView)
    end

    it 'wraps its content in a toast overlay' do
      expect(main_window.instance_variable_get(:@toast_overlay)).to be_a(Adw::ToastOverlay)
    end

    it 'lays the playlist and now-playing panes out in a split view' do
      split_view = main_window.instance_variable_get(:@split_view)
      expect(split_view).to be_a(Adw::OverlaySplitView)
    end

    it 'shows a toast without raising' do
      expect { main_window.notify('Hello') }.not_to raise_error
    end
  end

  describe 'the library page' do
    let(:library) { Loamp::Library.new(path: Loamp::Library::IN_MEMORY) }
    let(:with_library) { build_window(player, playlist, library: library) }

    after { library.close }

    it 'is absent when the window was built without an index' do
      expect(main_window.instance_variable_get(:@library_view)).to be_nil
    end

    it 'appears when the window was built with one' do
      expect(with_library.instance_variable_get(:@library_view)).to be_a(Loamp::UI::LibraryView)
    end

    it 'shares the view stack with the now-playing page' do
      stack = with_library.instance_variable_get(:@view_stack)

      expect(stack.pages.n_items).to eq(4)
    end

    it 'refreshes the playlist pane when the library queues something' do
      view = with_library.instance_variable_get(:@library_view)
      playlist_view = with_library.instance_variable_get(:@playlist_view)

      expect(playlist_view).to receive(:refresh)
      view.send(:announce_playlist_change)
    end
  end

  describe 'keyboard shortcuts' do
    before do
      # Add tracks to playlist for testing navigation
      playlist.add_track('/tmp/track1.mp3')
      playlist.add_track('/tmp/track2.mp3')
    end

    it 'handles space key for play/pause' do
      expect(player).to receive(:play_pause)
      result = main_window.send(:handle_key_press, Gdk::Keyval::KEY_space, 0)
      expect(result).to be(true)
    end

    it 'handles right arrow key for seek forward' do
      play_to_position(30)
      expect(player).to receive(:seek).with(be_within(1.0).of(40)) # 30 + 10 seconds
      result = main_window.send(:handle_key_press, Gdk::Keyval::KEY_Right, 0)
      expect(result).to be(true)
    end

    it 'handles left arrow key for seek backward' do
      play_to_position(30)
      expect(player).to receive(:seek).with(be_within(1.0).of(20)) # 30 - 10 seconds
      result = main_window.send(:handle_key_press, Gdk::Keyval::KEY_Left, 0)
      expect(result).to be(true)
    end

    it 'handles left arrow key for seek backward with minimum position' do
      play_to_position(5)
      expect(player).to receive(:seek).with(0) # Don't go below 0
      result = main_window.send(:handle_key_press, Gdk::Keyval::KEY_Left, 0)
      expect(result).to be(true)
    end

    it 'handles Ctrl+Right arrow for next track' do
      expect(player).to receive(:next_track)
      result = main_window.send(:handle_key_press, Gdk::Keyval::KEY_Right, Gdk::ModifierType::CONTROL_MASK)
      expect(result).to be(true)
    end

    it 'handles Ctrl+Left arrow for previous track' do
      expect(player).to receive(:previous_track)
      result = main_window.send(:handle_key_press, Gdk::Keyval::KEY_Left, Gdk::ModifierType::CONTROL_MASK)
      expect(result).to be(true)
    end

    it 'handles up arrow key for volume increase' do
      player.set_volume(50)
      expect(player).to receive(:set_volume).with(55) # 50 + 5
      result = main_window.send(:handle_key_press, Gdk::Keyval::KEY_Up, 0)
      expect(result).to be(true)
    end

    it 'handles up arrow key for volume increase with maximum limit' do
      player.set_volume(98)
      expect(player).to receive(:set_volume).with(100) # Don't go above 100
      result = main_window.send(:handle_key_press, Gdk::Keyval::KEY_Up, 0)
      expect(result).to be(true)
    end

    it 'handles down arrow key for volume decrease' do
      player.set_volume(50)
      expect(player).to receive(:set_volume).with(45) # 50 - 5
      result = main_window.send(:handle_key_press, Gdk::Keyval::KEY_Down, 0)
      expect(result).to be(true)
    end

    it 'handles down arrow key for volume decrease with minimum limit' do
      player.set_volume(3)
      expect(player).to receive(:set_volume).with(0) # Don't go below 0
      result = main_window.send(:handle_key_press, Gdk::Keyval::KEY_Down, 0)
      expect(result).to be(true)
    end

    it 'returns false for unhandled keys' do
      result = main_window.send(:handle_key_press, Gdk::Keyval::KEY_a, 0)
      expect(result).to be(false)
    end

    it 'handles key combinations correctly' do
      # Test that modifier state is properly checked
      result = main_window.send(:handle_key_press, Gdk::Keyval::KEY_Right, Gdk::ModifierType::SHIFT_MASK)
      expect(result).to be(true) # Should be handled as normal right arrow (seek)
    end
  end

  describe 'CSS styling' do
    it 'loads CSS theme' do
      # The initialize method should load CSS without errors
      expect { build_window(player, playlist) }.not_to raise_error
    end

    it 'handles missing CSS file gracefully' do
      # Stub File.exist? to return false for CSS file
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('assets/style.css').and_return(false)

      expect { build_window(player, playlist) }.not_to raise_error
    end

    it 'handles CSS loading errors gracefully' do
      # Mock CSS provider to raise error on load_from_path
      css_provider = instance_double(Gtk::CssProvider)
      allow(Gtk::CssProvider).to receive(:new).and_return(css_provider)
      allow(css_provider).to receive(:load_from_path).and_raise(StandardError.new('CSS error'))

      expect { build_window(player, playlist) }.not_to raise_error
    end
  end

  describe 'window management' do
    it 'shows window without starting main loop' do
      # In tests, we don't want to actually show the window
      expect { main_window }.not_to raise_error
    end

    it 'shuts its views down when the window is closed' do
      playlist_view = main_window.instance_variable_get(:@playlist_view)

      expect(playlist_view).to receive(:shutdown).and_call_original
      main_window.signal_emit('close-request')
    end

    it 'still closes after handling the close request' do
      # A close-request handler that returns true would veto the close.
      expect(main_window.signal_emit('close-request')).to be(false)
    end

    it 'shuts down only once however many times it is asked' do
      playlist_view = main_window.instance_variable_get(:@playlist_view)

      expect(playlist_view).to receive(:shutdown).once.and_call_original
      main_window.signal_emit('close-request')
      main_window.shutdown
    end

    it 'sets up key press event handling' do
      # Verify that key press handling is set up
      expect(main_window.respond_to?(:handle_key_press, true)).to be(true)
    end
  end

  describe 'component integration' do
    it 'passes player to player controls' do
      controls = main_window.instance_variable_get(:@player_controls)
      expect(controls.instance_variable_get(:@player)).to eq(player)
    end

    it 'passes playlist to playlist view' do
      playlist_view = main_window.instance_variable_get(:@playlist_view)
      expect(playlist_view.instance_variable_get(:@playlist)).to eq(playlist)
    end

    it 'connects components to player callbacks' do
      # Verify that the components are receiving player state updates
      track_info = main_window.instance_variable_get(:@track_info)
      expect(track_info).to be_a(Loamp::UI::TrackInfo)
      
      # Test that track info gets updated when player track changes
      test_track = build(:track)
      test_track.instance_variable_set(:@title, 'Test Track')
      expect(track_info).to receive(:update_track).with(test_track)
      player.notify_track_changed(test_track)
    end
  end

  describe 'file dialog functionality' do
    it 'adds real Gio file selections and captures the resulting window' do
      files = Gio::ListStore.new(Gio::File.gtype)
      files.append(Gio::File.new_for_path(AudioFixtures.sample_mp3))
      main_window.present

      expect { main_window.send(:add_files, files) }.to change(playlist, :size).from(0).to(1)
      settle_gtk

      expect(playlist.current_track.file_path).to eq(AudioFixtures.sample_mp3)
      expect(capture_widget(main_window, 'main-window-file-added')).to end_with('.png')
    end

    it 'can create file dialog without errors' do
      expect do
        dialog = Gtk::FileDialog.new
        dialog.title = 'Test Dialog'
        
        # Create file filters like in the real code
        audio_filter = Gtk::FileFilter.new
        audio_filter.name = 'Audio Files'
        audio_filter.add_mime_type('audio/*')
        
        all_filter = Gtk::FileFilter.new
        all_filter.name = 'All Files'
        all_filter.add_pattern('*')
        
        filter_list = Gio::ListStore.new(Gtk::FileFilter)
        filter_list.append(audio_filter)
        filter_list.append(all_filter)
        dialog.filters = filter_list
      end.not_to raise_error
    end

    it 'has proper callback structure for file dialog' do
      # Test that the open_file_dialog method exists and doesn't error on setup
      expect(main_window.respond_to?(:open_file_dialog, true)).to be(true)
      expect(main_window.respond_to?(:open_folder_dialog, true)).to be(true)
      
      # Verify the file dialog can be created (testing the fix for the async error)
      expect do
        main_window.send(:open_file_dialog)
      end.not_to raise_error(/must be.*GAsyncResult.*object/)
    end

    it 'has header bar buttons for file operations' do
      header_bar = main_window.instance_variable_get(:@header_bar)
      expect(header_bar).to be_a(Adw::HeaderBar)

      # Check that the add file and folder buttons exist
      add_file_button = main_window.instance_variable_get(:@add_file_button)
      add_folder_button = main_window.instance_variable_get(:@add_folder_button)

      expect(add_file_button).to be_a(Gtk::Button)
      expect(add_folder_button).to be_a(Gtk::Button)
      expect(add_file_button.icon_name).to eq('list-add-symbolic')
      expect(add_folder_button.icon_name).to eq('folder-open-symbolic')
    end
  end
end
