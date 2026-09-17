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

    it 'says so, in the list, when a search matches nothing' do
      view.search_for('zzzz')
      placeholder = view.instance_variable_get(:@track_placeholder)

      expect(placeholder.get_property('visible')).to be(true)
      expect(placeholder.text).to include('zzzz')
    end

    it 'takes the message away once there is something to show' do
      view.search_for('zzzz')
      view.search_for('svefn')

      expect(view.instance_variable_get(:@track_placeholder)
                 .get_property('visible')).to be(false)
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

  describe 'album art' do
    let(:art_cache) { Loamp::ArtCache.new(directory: File.join(root, 'art')) }
    let(:view) { described_class.new(library, playlist, player, art_cache: art_cache) }

    after { art_cache.shutdown }

    # Building a cover reads a tag and decodes an image. Doing that for every
    # album while filling the pane froze the window for as long as the
    # collection was large, and a window frozen that long loses its Wayland
    # connection: the listener sees the player disappear.
    it 'fills the pane without building a single cover' do
      stock_library
      view

      expect(art_cache).not_to receive(:thumbnail_for)
      expect(art_cache).to receive(:cached_thumbnail).at_least(:once).and_call_original
      view.refresh
    end

    it 'hands the covers it is missing to the cache to build off the main loop' do
      stock_library
      view.refresh
      art_cache.wait

      expect(art_cache).to receive(:warm_thumbnails) do |tracks, **|
        expect(tracks.map(&:album)).to contain_exactly('Days Are Gone', 'WIMPIII', 'Ágætis byrjun')
        false
      end
      view.refresh
    end

    it 'asks for no covers at all without an art cache' do
      stock_library

      expect { described_class.new(library, playlist, player).shutdown }.not_to raise_error
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

    it 'indexes a batch of folders as one scan' do
      one = File.join(root, 'one')
      two = File.join(root, 'two')
      [one, two].each { |dir| FileUtils.mkdir_p(dir) }
      FileUtils.cp(AudioFixtures.sample_mp3, File.join(one, 'a.mp3'))
      FileUtils.cp(AudioFixtures.sample_mp3, File.join(two, 'b.mp3'))
      message = nil
      view.on_notify { |text| message = text }

      expect(view.index_folders([one, two])).to be true
      pump_main_loop { !message.nil? }

      expect(library.stored_watch_folders).to eq([one, two])
      expect(library.count).to eq(2)
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

  describe 'empty library state' do
    it 'shows a status page until music is indexed' do
      empty = view.instance_variable_get(:@empty)
      panes = view.instance_variable_get(:@panes)

      expect(empty).to be_a(Adw::StatusPage)
      expect(empty.get_property('visible')).to be(true)
      expect(panes.get_property('visible')).to be(false)

      stock_library
      view.refresh

      expect(empty.get_property('visible')).to be(false)
      expect(panes.get_property('visible')).to be(true)
    end
  end

  describe '#enqueue_track' do
    before { stock_library }

    it 'appends without replacing the queue' do
      notices = []
      view.on_notify { |text| notices << text }
      playlist.add_track(AudioFixtures.sample_mp3)
      row = track_row(0)

      view.send(:enqueue_track, row)

      expect(playlist.size).to eq(2)
      expect(notices.last).to start_with('Queued')
    end
  end

  describe 'the row menu' do
    before { stock_library }

    # A destroyed window still holds its child while Ruby holds a reference to
    # it, so the view has to be let go of here or the outer teardown cannot
    # take it.
    after do
      @menu&.shutdown
      next unless @menu_window

      @menu_window.set_child(nil)
      @menu_window.destroy
    end

    it 'hangs off every pane' do
      expect(view.instance_variable_get(:@menus).keys).to contain_exactly(:artist, :album, :track)
    end

    it 'runs the action the listener picked against the row they picked it on' do
      menu = menu_on_a_window(:track)
      menu.show(track_row(0), 1, 1)

      menu.instance_variable_get(:@popover).child.last_child.signal_emit('clicked')

      expect(playlist.size).to eq(1)
      expect(playlist[0].title).to eq(track_row(0).item.title)
    end

    it 'names the row it was opened on, so a whole album is not a guess' do
      menu = menu_on_a_window(:album)
      row = album_row('Days Are Gone')

      view.send(:show_row_menu, :album, row, nil, 4, 6)

      expect(menu.instance_variable_get(:@popover).child.first_child.text).to eq('Days Are Gone')
    end

    it 'stays shut on a right-click that found no row' do
      menu_on_a_window(:album)

      expect(view.send(:show_row_menu, :album, nil, nil, 4, 6)).to be(false)
    end

    # The gesture lives on the row rather than on the list, so the menu opens
    # on the album under the pointer and not on whatever is selected.
    it 'opens on the row the click landed on' do
      on_screen
      3.times { GC.start }
      right_click(album_pane_rows[2])

      menu = view.instance_variable_get(:@menus)[:album]
      expect(menu).to be_open
      expect(menu.instance_variable_get(:@popover).child.first_child.text)
        .to eq(view.visible_albums[2])
      menu.instance_variable_get(:@popover).popdown
    end
  end

  # Which albums exist depends only on the artist, so choosing one must not
  # refill the pane it was chosen in -- the splice would carry off the
  # selection, and with it the pane's only way of saying what it is showing.
  describe 'choosing an album' do
    before { stock_library }

    it 'leaves the album pane showing which album it is narrowed to' do
      position = view.visible_albums.index('Days Are Gone')
      select_in(:@albums, position)

      expect(view.instance_variable_get(:@albums)[:selection].selected).to eq(position)
      expect(view.visible_tracks.map(&:title)).to eq(['Falling', 'The Wire'])
    end

    # A different artist does change which albums there are, so that pane has
    # to be refilled even though the same method makes both changes.
    it 'still refills the pane when the artist changes' do
      view.browse(artist: 'Sigur Rós')

      expect(view.visible_albums).to eq([:any, 'Ágætis byrjun'])
    end
  end

  # Play Next and Add to Queue were mouse-only until the panes answered to the
  # keys GTK gives every other context menu. With no pointer to go on, the row
  # is the selected one -- what the arrow keys just moved to.
  describe 'the row menu from the keyboard' do
    before { stock_library }

    after do
      @keyboard_menu&.instance_variable_get(:@popover)&.popdown
      next unless @menu_window

      @menu_window.set_child(nil)
      @menu_window.destroy
    end

    it 'opens on the selected row when the Menu key is pressed' do
      on_screen
      select_in(:@albums, 2)

      expect(press_menu_key(:@albums)).to be(true)
      expect(opened_menu(:album)).to be_open
      expect(heading_of(:album)).to eq(view.visible_albums[2])
    end

    it 'answers to Shift+F10 as well, for keyboards with no Menu key' do
      on_screen
      select_in(:@artists, 1)

      expect(press_menu_key(:@artists, Gdk::Keyval::KEY_F10,
                            Gdk::ModifierType::SHIFT_MASK.to_i)).to be(true)
      expect(opened_menu(:artist)).to be_open
      expect(heading_of(:artist)).to eq(view.visible_artists[1])
    end

    it 'reaches the track list too' do
      on_screen
      select_in(:@tracks, 0)

      expect(press_menu_key(:@tracks)).to be(true)
      expect(opened_menu(:track)).to be_open
    end

    # The queue is what the menu is for, so the actions it offers have to work
    # the same however the menu was reached.
    it 'queues the album it opened on' do
      on_screen
      select_in(:@albums, album_position('Days Are Gone'))
      press_menu_key(:@albums)

      buttons_of(:album).last.signal_emit('clicked')

      expect(playlist.tracks.map(&:title)).to eq(['Falling', 'The Wire'])
    end

    # F10 alone belongs to the menubar, so the pane has to leave it be.
    it 'leaves F10 on its own to whoever else wants it' do
      on_screen
      select_in(:@albums, 2)

      expect(press_menu_key(:@albums, Gdk::Keyval::KEY_F10)).to be(false)
      expect(view.instance_variable_get(:@menus)[:album]).not_to be_open
    end

    # An empty library has rows but no selection in the track pane, and a
    # menu over nothing would be three actions that cannot do anything.
    it 'opens nothing when the pane has no row selected' do
      view.instance_variable_get(:@tracks)[:selection].unselect_all
      on_screen

      expect(press_menu_key(:@tracks)).to be(false)
      expect(view.instance_variable_get(:@menus)[:track]).not_to be_open
    end
  end

  describe 'queueing a whole album' do
    before { stock_library }

    it 'plays every track on it, in playing order' do
      view.send(:act_on_row, :album, :play, album_row('Days Are Gone'))

      expect(playlist.tracks.map(&:title)).to eq(['Falling', 'The Wire'])
      expect(playlist.current_track.title).to eq('Falling')
    end

    it 'appends the album without disturbing what is queued' do
      playlist.add_track(AudioFixtures.sample_mp3)

      view.send(:act_on_row, :album, :enqueue, album_row('Days Are Gone'))

      expect(playlist.size).to eq(3)
      expect(playlist.tracks.drop(1).map(&:title)).to eq(['Falling', 'The Wire'])
    end

    it 'says how much it queued' do
      notices = []
      view.on_notify { |text| notices << text }

      view.send(:act_on_row, :album, :enqueue, album_row('Days Are Gone'))

      expect(notices.last).to eq('Queued Days Are Gone · 2 tracks')
    end

    it 'lands after the current track, still in its own order' do
      playlist.add_track(AudioFixtures.sample_mp3)
      playlist.add_track(AudioFixtures.sample_mp3)
      playlist.set_current_track(0)

      view.send(:act_on_row, :album, :play_next, album_row('Days Are Gone'))

      expect(playlist.tracks[1..2].map(&:title)).to eq(['Falling', 'The Wire'])
    end

    it 'follows the artist the pane is narrowed to' do
      view.browse(artist: 'Haim')

      view.send(:act_on_row, :album, :enqueue, album_row(Loamp::UI::LibraryView::ALL_ALBUMS))

      expect(playlist.tracks.map(&:title)).to eq(['Falling', 'The Wire', 'The Steps'])
    end
  end

  describe 'queueing a whole artist' do
    before { stock_library }

    it 'queues everything the index holds for them' do
      view.send(:act_on_row, :artist, :enqueue, artist_row('Haim'))

      expect(playlist.tracks.map(&:title)).to eq(['Falling', 'The Wire', 'The Steps'])
    end

    it 'treats the all-artists row as the whole library' do
      view.send(:act_on_row, :artist, :enqueue, artist_row(Loamp::UI::LibraryView::ALL_ARTISTS))

      expect(playlist.size).to eq(4)
    end

    it 'says so rather than queueing nothing' do
      notices = []
      view.on_notify { |text| notices << text }

      view.send(:act_on_row, :artist, :enqueue, view.send(:row, item: 'Nobody',
                                                               primary: 'Nobody'))

      expect(playlist).to be_empty
      expect(notices.last).to eq('Nothing to queue for Nobody')
    end
  end

  describe '#play_next_track' do
    before { stock_library }

    it 'queues the track straight after the one that is playing' do
      playlist.add_track(AudioFixtures.sample_mp3)
      playlist.add_track(AudioFixtures.sample_mp3)
      playlist.set_current_track(0)

      view.send(:play_next_track, track_row(0))

      expect(playlist[1].title).to eq(track_row(0).item.title)
      expect(playlist.size).to eq(3)
    end

    it 'tells the listener what it did' do
      notices = []
      view.on_notify { |text| notices << text }

      view.send(:play_next_track, track_row(0))

      expect(notices.last).to include('next')
    end

    it 'ignores a row that is not a track' do
      expect { view.send(:play_next_track, nil) }.not_to raise_error
    end
  end

  describe '#focus_search' do
    it 'puts the caret in the search entry' do
      expect(view.focus_search).to be(true)
    end

    it 'does nothing once the view has been shut down' do
      view.shutdown

      expect(view.focus_search).to be(false)
    end
  end

  describe 'row lifetime' do
    # Each pane's fields live on the Ruby object wrapping the row's GObject,
    # and only the pane keeps that wrapper alive. When it did not, a
    # collection between filling a pane and drawing it left every row blank.
    it 'keeps rows readable after a garbage collection' do
      stock_library
      view.refresh
      3.times { GC.start }

      expect(track_row(0).primary).not_to be_nil
      expect(artist_row('Haim')).not_to be_nil
      expect(album_row('Days Are Gone')).not_to be_nil
    end
  end

  def track_row(position)
    view.instance_variable_get(:@tracks)[:store].get_item(position)
  end

  def album_row(title)
    pane_row(:@albums, title)
  end

  def artist_row(name)
    pane_row(:@artists, name)
  end

  def pane_row(pane, primary)
    store = view.instance_variable_get(pane)[:store]
    Array.new(store.n_items) { |index| store.get_item(index) }
      .find { |row| row.primary == primary }
  end

  # Rows are only built once the list is on screen and has been laid out.
  def on_screen
    @menu_window = Gtk::Window.new
    @menu_window.set_default_size(900, 600)
    @menu_window.child = view
    @menu_window.present
    pump_main_loop(timeout: 1) { false }
  end

  def album_pane_rows
    list = view.instance_variable_get(:@albums)[:widget]
    rows = []
    child = list.first_child
    while child
      rows << child.first_child
      child = child.next_sibling
    end
    rows
  end

  # The same trick as #right_click, for the controller the list carries: GTK
  # has no way to inject a real key press either.
  def press_menu_key(pane, keyval = Gdk::Keyval::KEY_Menu, state = 0)
    widget = view.instance_variable_get(pane)[:widget]
    controller = widget.observe_controllers.to_a.grep(Gtk::EventControllerKey).first
    controller.signal_emit('key-pressed', keyval, 0, state)
  end

  def select_in(pane, position)
    view.instance_variable_get(pane)[:selection].selected = position
  end

  def album_position(title)
    view.visible_albums.index(title)
  end

  def opened_menu(kind)
    @keyboard_menu = view.instance_variable_get(:@menus)[kind]
  end

  def heading_of(kind)
    opened_menu(kind).instance_variable_get(:@popover).child.first_child.text
  end

  def buttons_of(kind)
    box = opened_menu(kind).instance_variable_get(:@popover).child
    buttons = []
    child = box.first_child.next_sibling
    while child
      buttons << child
      child = child.next_sibling
    end
    buttons
  end

  # Emitting on the row's own gesture is as close to a right-click as a spec
  # gets; GTK has no way to inject a button press.
  def right_click(row_widget, x_position = 3, y_position = 4)
    gesture = row_widget.observe_controllers.to_a.grep(Gtk::GestureClick).first
    gesture.signal_emit('pressed', 1, x_position.to_f, y_position.to_f)
  end

  # A menu parented to a window of its own, since a popover cannot be popped
  # up from a widget tree that has no toplevel over it.
  def menu_on_a_window(kind)
    host = Gtk::Box.new(:vertical, 0)
    @menu_window = Gtk::Window.new
    @menu_window.child = host
    selection = Gtk::SingleSelection.new(Gio::ListStore.new(Loamp::UI::LibraryView::Row))
    @menu = view.send(:add_row_menu, kind, host, selection)
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
