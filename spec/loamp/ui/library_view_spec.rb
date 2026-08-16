# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Loamp::UI::LibraryView do
  let(:root) do
    dir = File.join(AudioFixtures.fixture_dir, "library-view-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(dir)
    @root = dir
  end

  let(:library) { Loamp::Library.new(path: Loamp::Library::IN_MEMORY) }
  let(:playlist) { Loamp::Playlist.new }
  let(:engine) { AudioFixtures.silent_engine }
  let(:player) { Loamp::Player.new(playlist, engine: engine) }
  let(:view) { described_class.new(library, playlist, player) }

  after do
    view.shutdown
    # An orphan widget tree is only torn down whenever Ruby's GC gets to it,
    # which at process exit means ruby-gnome unwinding hundreds of widgets at
    # once. Giving the view a window to be destroyed with disposes of it here,
    # while GTK is still in a fit state to do it.
    Gtk::Window.new.tap { |window| window.child = view }.destroy
    engine.shutdown
    library.close
    FileUtils.rm_rf(@root) if @root
  end

  # A small collection with two artists, one of whom has two albums.
  def stock_library
    index('Falling', artist: 'Haim', album: 'Days Are Gone', year: 2013, number: 1)
    index('The Wire', artist: 'Haim', album: 'Days Are Gone', year: 2013, number: 2)
    index('The Steps', artist: 'Haim', album: 'WIMPIII', year: 2020, number: 1)
    index('Svefn-g-englar', artist: 'Sigur Rós', album: 'Ágætis byrjun', year: 1999, number: 1)
  end

  def index(title, artist:, album:, year:, number:)
    path = File.join(root, "#{artist} - #{title}.mp3")
    FileUtils.cp(AudioFixtures.tone(seconds: 1), path)
    library.add(path, metadata: Loamp::Metadata.new(title: title, artist: artist,
                                                    album_artist: artist, album: album,
                                                    year: year, track_number: number,
                                                    duration: 100 + number))
    path
  end

  describe 'building the panes' do
    it 'lists every artist, with a row for all of them' do
      stock_library

      expect(view.visible_artists).to eq([:any, 'Haim', 'Sigur Rós'])
    end

    it 'lists every album until an artist is chosen' do
      stock_library

      expect(view.visible_albums.size).to eq(4) # three albums plus the "all" row
    end

    it 'lists every track' do
      stock_library

      expect(view.visible_tracks.map(&:title)).to include('Falling', 'Svefn-g-englar')
    end

    it 'copes with an empty library' do
      expect(view.visible_tracks).to be_empty
      expect(view.visible_artists).to eq([:any])
    end
  end

  describe '#browse' do
    before { stock_library }

    it 'narrows the albums to one artist' do
      view.browse(artist: 'Haim')

      expect(view.visible_albums).to eq([:any, 'Days Are Gone', 'WIMPIII'])
    end

    it 'narrows the tracks to one artist' do
      view.browse(artist: 'Haim')

      expect(view.visible_tracks.map(&:artist).uniq).to eq(['Haim'])
    end

    it 'narrows the tracks to one album, in playing order' do
      view.browse(artist: 'Haim', album: 'Days Are Gone')

      expect(view.visible_tracks.map(&:title)).to eq(['Falling', 'The Wire'])
    end

    it 'widens again' do
      view.browse(artist: 'Haim', album: 'Days Are Gone')
      view.browse

      expect(view.visible_tracks.size).to eq(4)
    end
  end

  describe 'searching' do
    before { stock_library }

    it 'shows only what matches' do
      view.search_for('svefn')

      expect(view.visible_tracks.map(&:title)).to eq(['Svefn-g-englar'])
    end

    it 'searches the whole library, not just the chosen artist' do
      view.browse(artist: 'Haim')
      view.search_for('sigur')

      expect(view.visible_tracks.map(&:artist)).to eq(['Sigur Rós'])
    end

    it 'goes back to browsing when the search is cleared' do
      view.search_for('svefn')
      view.search_for('')

      expect(view.visible_tracks.size).to eq(4)
    end

    it 'shows nothing for a search that matches nothing' do
      view.search_for('zzzz')

      expect(view.visible_tracks).to be_empty
    end
  end

  describe '#refresh' do
    it 'picks up tracks indexed since it was built' do
      view
      stock_library

      view.refresh

      expect(view.visible_tracks.size).to eq(4)
    end

    it 'clears a search that was in progress' do
      stock_library
      view.search_for('svefn')

      view.refresh

      expect(view.visible_tracks.size).to eq(4)
    end
  end

  describe 'playing from the library' do
    before { stock_library }

    it 'queues what is on screen and starts at the chosen track' do
      view.browse(artist: 'Haim', album: 'Days Are Gone')

      view.send(:play_track, track_row(1))
      engine.wait_for_state(:playing)

      expect(playlist.size).to eq(2)
      expect(playlist.current_track.title).to eq('The Wire')
      expect(player).to be_playing
    end

    it 'replaces whatever was queued before' do
      playlist.add_track(AudioFixtures.sample_mp3)
      view.browse(artist: 'Haim', album: 'Days Are Gone')

      view.send(:play_track, track_row(0))

      expect(playlist.size).to eq(2)
    end

    it 'queues without reading the tags off disk again' do
      view.browse(artist: 'Haim', album: 'Days Are Gone')

      expect(Loamp::Metadata).not_to receive(:read)
      view.send(:play_track, track_row(0))
    end

    it 'tells its owner the playlist changed' do
      changed = false
      view.on_playlist_changed { changed = true }

      view.send(:play_track, track_row(0))

      expect(changed).to be true
    end

    it 'ignores a row that is not a track' do
      expect { view.send(:play_track, nil) }.not_to raise_error
    end
  end

  describe 'scanning' do
    it 'indexes a folder and refreshes itself' do
      FileUtils.cp(AudioFixtures.sample_mp3, File.join(root, 'a.mp3'))
      message = nil
      view.on_notify { |text| message = text }

      view.scan([root])
      pump_main_loop { !message.nil? }

      expect(library.count).to eq(1)
      expect(message).to include('added')
      expect(view.visible_tracks.size).to eq(1)
    end

    it 'remembers the folder so a later rescan can find new files' do
      FileUtils.cp(AudioFixtures.sample_mp3, File.join(root, 'a.mp3'))
      message = nil
      view.on_notify { |text| message = text }

      view.index_folder(root)
      pump_main_loop { !message.nil? }

      expect(library.watch_folders).to eq([File.expand_path(root)])
    end

    it 'says so when there was nothing new' do
      message = nil
      view.on_notify { |text| message = text }

      view.scan([root])
      pump_main_loop { !message.nil? }

      expect(message).to eq('Nothing new to index')
    end

    it 'refuses to start a second scan while one is running' do
      20.times { |i| FileUtils.cp(AudioFixtures.sample_mp3, File.join(root, "#{i}.mp3")) }
      view.scan([root])

      expect(view.scan([root])).to be false
      pump_main_loop { !view.scanning? }
    end
  end

  def track_row(position)
    view.instance_variable_get(:@tracks)[:store].get_item(position)
  end

  # Scanner callbacks arrive through GLib::Idle, so the loop has to turn.
  def pump_main_loop(timeout: 20)
    context = GLib::MainContext.default
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      context.iteration(false)
      sleep 0.01
    end
  end
end
