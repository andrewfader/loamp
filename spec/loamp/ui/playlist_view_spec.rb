# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::PlaylistView do
  before { skip_if_no_gtk }

  let(:playlist) { Loamp::Playlist.new }
  let(:engine) { AudioFixtures.silent_engine }
  let(:player) { Loamp::Player.new(playlist, engine: engine) }
  let(:playlist_view) { described_class.new(playlist, player) }

  let(:first_track) { AudioFixtures.tone(seconds: 2, name: 'view-one.wav') }
  let(:second_track) { AudioFixtures.tone(seconds: 2, frequency: 660, name: 'view-two.wav') }

  after do
    # The view parents a popover by hand, and an orphan widget tree is only
    # torn down whenever Ruby's GC gets to it. Tearing it down here runs that
    # while everything it touches is still alive.
    playlist_view.shutdown
    engine.shutdown
  end

  def store
    playlist_view.instance_variable_get(:@store)
  end

  def selection
    playlist_view.instance_variable_get(:@selection)
  end

  def add_two_tracks
    playlist.add_track(first_track)
    playlist.add_track(second_track)
    playlist_view.refresh
  end

  describe '#initialize' do
    it 'is a scrolled window holding a column view' do
      expect(playlist_view).to be_a(Gtk::ScrolledWindow)
      expect(playlist_view.child).to be_a(Gtk::ColumnView)
    end

    it 'builds a column for position, title and length' do
      columns = playlist_view.instance_variable_get(:@column_view).columns

      expect(columns.n_items).to eq(3)
      expect(columns.get_item(0).title).to eq('#')
      expect(columns.get_item(1).title).to eq('Title')
      expect(columns.get_item(2).title).to eq('Length')
    end

    it 'never scrolls horizontally' do
      expect(playlist_view.hscrollbar_policy).to eq(:never)
    end

    it 'starts empty for an empty playlist' do
      expect(store.n_items).to eq(0)
    end
  end

  describe '#refresh' do
    it 'mirrors the tracks in the playlist' do
      add_two_tracks

      expect(store.n_items).to eq(2)
    end

    it 'numbers rows from one' do
      add_two_tracks

      expect(store.get_item(0).position).to eq(1)
      expect(store.get_item(1).position).to eq(2)
    end

    it 'carries the track itself on each row' do
      add_two_tracks

      expect(store.get_item(0).track).to equal(playlist[0])
    end

    it 'picks up tracks added after construction' do
      playlist_view
      playlist.add_track(first_track)
      playlist_view.refresh

      expect(store.n_items).to eq(1)
    end

    it 'empties when the playlist is cleared' do
      add_two_tracks
      playlist.clear
      playlist_view.refresh

      expect(store.n_items).to eq(0)
    end
  end

  describe 'activating a row' do
    it 'makes that track current and starts playing it' do
      add_two_tracks

      playlist_view.send(:play_track_at, 1)
      engine.wait_for_state(:playing, timeout: 5)

      expect(playlist.current_index).to eq(1)
      expect(player).to be_playing
    end

    it 'ignores an activation beyond the end of the playlist' do
      add_two_tracks

      expect { playlist_view.send(:play_track_at, 99) }.not_to raise_error
    end
  end

  describe 'current track highlighting' do
    it 'selects the row for the playing track' do
      add_two_tracks
      playlist.set_current_track(1)

      playlist_view.send(:update_current_track_highlight)

      expect(selection.selected).to eq(1)
    end

    it 'follows the player when the track changes' do
      add_two_tracks
      playlist.set_current_track(1)

      player.notify_track_changed

      expect(selection.selected).to eq(1)
    end

    it 'does nothing when the playlist is empty' do
      expect { player.notify_track_changed(nil) }.not_to raise_error
    end
  end

  describe 'removing a track' do
    it 'removes the selected row from the playlist' do
      add_two_tracks
      selection.selected = 0

      playlist_view.send(:remove_selected)

      expect(playlist.size).to eq(1)
      expect(store.n_items).to eq(1)
    end

    it 'stops playback when the playing track is removed' do
      add_two_tracks
      playlist.set_current_track(0)
      player.play
      engine.wait_for_state(:playing, timeout: 5)
      selection.selected = 0

      playlist_view.send(:remove_selected)

      expect(player).to be_stopped
    end

    it 'does nothing when nothing is selected' do
      add_two_tracks
      selection.unselect_all

      expect { playlist_view.send(:remove_selected) }.not_to raise_error
    end
  end

  describe '#selected_index' do
    it 'reports the selected row' do
      add_two_tracks
      selection.selected = 1

      expect(playlist_view.selected_index).to eq(1)
    end

    it 'reports nothing when there is no selection' do
      add_two_tracks
      selection.unselect_all

      expect(playlist_view.selected_index).to be_nil
    end
  end

  describe 'context menu' do
    it 'builds a GTK4 popover rather than a removed Gtk::Menu' do
      expect(playlist_view.instance_variable_get(:@context_menu)).to be_a(Gtk::PopoverMenu)
    end

    it 'stays put when the view is not inside a window yet' do
      add_two_tracks

      expect { playlist_view.send(:show_context_menu, 10, 10) }.not_to raise_error
    end

    it 'points at the click once the view is inside a window' do
      add_two_tracks
      window = Gtk::Window.new
      window.child = playlist_view

      playlist_view.send(:show_context_menu, 37, 21)

      pointing_to = playlist_view.instance_variable_get(:@context_menu).pointing_to
      expect([pointing_to.x, pointing_to.y]).to eq([37, 21])
    ensure
      window&.destroy
    end
  end
end
