# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Application do
  before(:each) do
    skip_if_no_gtk
  end

  # An in-memory index, so the specs neither touch nor need the real one in
  # the user's data directory.
  let(:application) { described_class.new(library_path: Loamp::Library::IN_MEMORY) }

  describe '#initialize' do
    it 'creates a playlist' do
      expect(application.instance_variable_get(:@playlist)).to be_a(Loamp::Playlist)
    end

    it 'opens the library index' do
      expect(application.library).to be_a(Loamp::Library)
    end

    it 'runs without a library rather than failing when the index cannot be opened' do
      allow(Loamp::Library).to receive(:new).and_raise('disk is read-only')

      expect(described_class.new.library).to be_nil
    end

    it 'creates a player with the playlist' do
      player = application.instance_variable_get(:@player)
      playlist = application.instance_variable_get(:@playlist)
      
      expect(player).to be_a(Loamp::Player)
      expect(player.playlist).to eq(playlist)
    end
  end

  describe '#run' do
    let(:gtk_application) do
      instance_double(Adw::Application, run: 0, add_action: nil, set_accels_for_action: nil)
    end
    let(:main_window) do
      instance_double(Loamp::UI::MainWindow, :application= => nil, present: nil, show_lyrics: nil)
    end

    before do
      allow(Adw::Application).to receive(:new).and_return(gtk_application)
      allow(gtk_application).to receive(:signal_connect).with('activate').and_yield
      allow(gtk_application).to receive(:signal_connect).with('shutdown')
      allow(Loamp::UI::MainWindow).to receive(:new).and_return(main_window)

      # Exporting on the real session bus is the service's own business, and
      # taking the MPRIS name here would collide with the specs that test it.
      allow(application.mpris).to receive(:start).and_return(false)
    end

    it 'uses an Adwaita application so the Adwaita stylesheet applies' do
      expect(Adw::Application).to receive(:new).with(Loamp::Application::APPLICATION_ID, :flags_none)

      application.run
    end

    it 'registers the quit action referenced by the main menu' do
      expect(gtk_application).to receive(:add_action)

      application.run
    end

    it 'creates and presents the main window' do
      expect(main_window).to receive(:present)

      application.run

      expect(application.instance_variable_get(:@main_window)).to equal(main_window)
    end

    it 'attaches the window to the GTK application' do
      expect(main_window).to receive(:application=).with(gtk_application)

      application.run
    end

    it 'starts the GTK application' do
      expect(gtk_application).to receive(:run).with([])

      application.run
    end

    # Without this clock nothing drains the GStreamer bus, so track changes and
    # errors would never reach the UI no matter how correct the engine is.
    it 'runs a clock that drives the player' do
      application.run

      ticks = 0
      allow(application.instance_variable_get(:@player)).to receive(:tick) { ticks += 1 }

      application.send(:playback_clock).call

      expect(ticks).to eq(1)
    end

    it 'keeps the clock running after each tick' do
      application.run

      expect(application.send(:playback_clock).call).to be(true)
    end

    # Quitting through app.quit — Ctrl+Q, or the MPRIS Quit method — closes no
    # window, so the window's own close-request handler never fires and nothing
    # else would tell the views to let go of a scan or a hand-parented popover.
    it 'shuts the window down when the application quits' do
      allow(gtk_application).to receive(:signal_connect).with('shutdown').and_yield
      allow(application.mpris).to receive(:stop)

      expect(main_window).to receive(:shutdown)

      application.run
    end

    it 'stops art lookups in flight when the application quits' do
      allow(gtk_application).to receive(:signal_connect).with('shutdown').and_yield
      allow(application.mpris).to receive(:stop)
      allow(main_window).to receive(:shutdown)

      expect(application.art_cache).to receive(:shutdown)

      application.run
    end
  end

  # Cover art that is on neither the file nor the disk beside it is looked for
  # on the network, and arrives long after the track started — if at all.
  describe 'artwork that arrives late' do
    let(:gtk_application) do
      instance_double(Adw::Application, run: 0, add_action: nil, set_accels_for_action: nil)
    end
    let(:main_window) do
      instance_double(Loamp::UI::MainWindow, :application= => nil, present: nil,
                                             artwork_arrived: nil, show_lyrics: nil)
    end
    let(:track) { AudioFixtures.track_with(artist: 'Radiohead', album: 'OK Computer') }

    before do
      allow(Adw::Application).to receive(:new).and_return(gtk_application)
      allow(gtk_application).to receive(:signal_connect).with('activate').and_yield
      allow(gtk_application).to receive(:signal_connect).with('shutdown')
      allow(Loamp::UI::MainWindow).to receive(:new).and_return(main_window)
      allow(application.mpris).to receive(:start).and_return(false)
      application.run
    end

    # The cache is what decides whether a lookup is worth starting at all; the
    # application only has to pass the answer on.
    def deliver(url)
      allow(application.art_cache).to receive(:fetch_remote) { |_track, &block| block.call(url) }
      application.player.notify_track_changed(track)
    end

    it 'draws it in the now-playing pane' do
      expect(main_window).to receive(:artwork_arrived).with(track, 'file:///cache/art.jpg')

      deliver('file:///cache/art.jpg')
    end

    # The desktop widget was told about this track before the cover existed.
    it 'tells the desktop widget again' do
      expect(application.mpris).to receive(:track_changed)

      deliver('file:///cache/art.jpg')
    end

    it 'says nothing when there was no art to find' do
      expect(main_window).not_to receive(:artwork_arrived)

      deliver(nil)
    end

    it 'asks the cache on every track change' do
      expect(application.art_cache).to receive(:fetch_remote).with(track)

      application.player.notify_track_changed(track)
    end
  end

  # MPRIS is what makes the media keys, the lock screen widget and playerctl
  # work, so the wiring is worth asserting even though the bus is not touched.
  describe 'desktop integration' do
    let(:gtk_application) do
      instance_double(Adw::Application, run: 0, add_action: nil, set_accels_for_action: nil,
                                        quit: nil)
    end
    let(:main_window) do
      instance_double(Loamp::UI::MainWindow, :application= => nil, present: nil, show_lyrics: nil)
    end

    before do
      allow(Adw::Application).to receive(:new).and_return(gtk_application)
      allow(gtk_application).to receive(:signal_connect).with('activate').and_yield
      allow(gtk_application).to receive(:signal_connect).with('shutdown')
      allow(Loamp::UI::MainWindow).to receive(:new).and_return(main_window)
      allow(application.mpris).to receive(:start).and_return(false)
    end

    it 'exports the player on the bus' do
      expect(application.mpris).to receive(:start)

      application.run
    end

    it 'presents the window when a client asks the player to raise' do
      application.run

      expect(main_window).to receive(:present)
      application.mpris.adapter.invoke(Loamp::Mpris::ROOT_INTERFACE, 'Raise')
    end

    it 'quits when a client asks the player to quit' do
      application.run

      expect(gtk_application).to receive(:quit)
      application.mpris.adapter.invoke(Loamp::Mpris::ROOT_INTERFACE, 'Quit')
    end

    it 'announces track changes once the service is exported' do
      allow(application.mpris).to receive_messages(start: true, track_changed: nil)
      application.run

      expect(application.mpris).to receive(:track_changed)
      application.player.notify_track_changed(nil)
    end

    it 'leaves the player working when the bus is unreachable' do
      allow(application.mpris).to receive(:start).and_return(false)

      expect { application.run }.not_to raise_error
    end
  end
end
