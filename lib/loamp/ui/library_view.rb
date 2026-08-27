# frozen_string_literal: true

module Loamp
  module UI
    # Browsing the collection: artists, then their albums, then the tracks.
    #
    # Three linked lists rather than one tree, because a column browser is
    # what a music library has wanted since iTunes: each pane narrows the one
    # to its right, and searching cuts straight past all of them.
    #
    # Every list is virtualised, and the queries behind them are indexed, so
    # this stays the same speed at ten thousand tracks as at ten.
    class LibraryView < Gtk::Box
      # One GObject per row, so tracks and albums can live in a Gio::ListModel.
      class Row < GLib::Object
        type_register

        attr_accessor :item, :primary, :secondary, :trailing, :art_url
      end

      ALL_ARTISTS = 'All Artists'
      ALL_ALBUMS = 'All Albums'
      TRACK_LIMIT = 2_000

      # Starting widths only: the panes are draggable, because how much room
      # artists deserve against titles depends entirely on the collection.
      ARTIST_PANE_WIDTH = 170
      BROWSER_WIDTH = 350

      def initialize(library, playlist, player, art_cache: nil)
        super(:vertical, 0)
        add_css_class('loamp-library')
        @library = library
        @playlist = playlist
        @player = player
        @art_cache = art_cache
        @scanner = Library::Scanner.new(library)
        @callbacks = {}
        @handlers = []
        @artist = :any
        @album = :any

        build_toolbar
        build_panes
        refresh
      end

      # Stops any scan in flight and detaches its callbacks. The search entry
      # debounces its own signal, so a keystroke can still be in flight after
      # the view is finished with — after this it is ignored rather than asked
      # to search a library that may already be closed.
      # Lets go of everything GTK will not clean up on the view's behalf: the
      # scan in flight, and every signal handler.
      #
      # Handlers matter more than they look. A widget outlives the Ruby object
      # that built it whenever something else still holds a reference — the
      # search entry's own debounce timer, say — and a handler firing then
      # runs Ruby code against a half-collected object, or worse, during the
      # garbage collection that is collecting it.
      def shutdown
        @shutdown = true
        @scanner.shutdown
        @track_menu&.unparent
        @track_menu = nil
        @handlers.each { |object, id| object.signal_handler_disconnect(id) }
        @handlers.clear
        [@artists, @albums, @tracks].each { |pane| pane[:store].remove_all }
      end

      # Fires when tracks have been added to the playlist, so the playlist
      # pane can catch up.
      def on_playlist_changed(&block)
        @callbacks[:playlist_changed] = block
      end

      # Fires with a message worth putting in front of the listener.
      def on_notify(&block)
        @callbacks[:notify] = block
      end

      # Reloads every pane from the index.
      def refresh
        @search_entry.text = ''
        @artist = :any
        @album = :any
        load_artists
        load_albums
        load_tracks
        update_summary
        update_empty_state
      end

      # Indexes folders in the background; the UI stays live throughout.
      def scan(directories)
        return false if @shutdown || @scanner.running?

        @progress.fraction = 0
        @progress.visible = true

        @scanner.start(directories,
                       on_progress: method(:scan_progressed),
                       on_finished: method(:scan_finished))
      end

      # Remembers the folder as a watch root, then indexes it. Rescan walks
      # these roots so a new album next to an existing one is not missed.
      def index_folder(path)
        return false if @shutdown

        @library.add_watch_folder(path)
        scan([path])
      end

      def scanning?
        @scanner.running?
      end

      # Narrows the view the way clicking the panes does. `:any` means "do not
      # filter on this", which is not the same as filtering on nil — a track
      # with no album tag at all is a real thing to browse to.
      def browse(artist: :any, album: :any)
        @artist = artist
        @album = album
        load_albums
        load_tracks
      end

      # Gtk::SearchEntry debounces its own search-changed signal, which is
      # what makes typing feel right and what makes a programmatic search need
      # to ask for the reload itself.
      def search_for(text)
        @search_entry.text = text.to_s
        load_tracks
      end

      # What each pane is showing, in order.
      def visible_tracks
        items_of(@tracks)
      end

      def visible_artists
        items_of(@artists)
      end

      def visible_albums
        items_of(@albums)
      end

      private

      # Every connection is remembered so that #shutdown can undo it.
      def connect(object, signal, &)
        @handlers << [object, object.signal_connect(signal, &)]
      end

      def items_of(pane)
        Array.new(pane[:store].n_items) { |index| pane[:store].get_item(index).item }
      end

      def build_toolbar
        @search_entry = Gtk::SearchEntry.new
        @search_entry.placeholder_text = 'Search the library'
        @search_entry.add_css_class('loamp-search')
        @search_entry.hexpand = true
        connect(@search_entry, 'search-changed') { load_tracks }

        @add_button = Gtk::Button.new(label: 'Add Folder')
        @add_button.tooltip_text = 'Add a folder to auto-scan into the library'
        connect(@add_button, 'clicked') { choose_folder }

        @summary = Gtk::Label.new
        @summary.add_css_class('dim-label')
        @summary.xalign = 0

        append(toolbar_box)
        append(progress_bar)
        append(empty_state)
      end

      def empty_state
        @empty = Adw::StatusPage.new
        @empty.icon_name = 'folder-music-symbolic'
        @empty.title = 'No music yet'
        @empty.description = 'Add a music folder to build your library. ' \
                             'Entire trees are indexed and scanned again on launch.'
        button = Gtk::Button.new(label: 'Add Folder')
        button.add_css_class('pill')
        button.add_css_class('suggested-action')
        button.halign = :center
        connect(button, 'clicked') { choose_folder }
        @empty.child = button
        @empty.vexpand = true
        @empty
      end

      def toolbar_box
        box = Gtk::Box.new(:horizontal, 6)
        box.margin_top = 6
        box.margin_bottom = 6
        box.margin_start = 6
        box.margin_end = 6
        box.append(@search_entry)
        box.append(@add_button)
        box
      end

      def progress_bar
        @progress = Gtk::ProgressBar.new
        @progress.visible = false
        @progress.show_text = true
        @progress
      end

      def build_panes
        @artists = list_pane { |row| select_artist(row) }
        @albums = list_pane { |row| select_album(row) }
        @tracks = track_pane

        browser = split(pane_frame(@artists[:widget]), pane_frame(@albums[:widget]),
                        position: ARTIST_PANE_WIDTH)
        panes = split(browser, pane_frame(@tracks[:widget], scroll_sideways: true),
                      position: BROWSER_WIDTH)
        panes.vexpand = true
        @panes = panes

        append(panes)
        append(summary_bar)
        update_empty_state
      end

      def summary_bar
        box = Gtk::Box.new(:horizontal, 6)
        box.margin_start = 6
        box.margin_end = 6
        box.margin_bottom = 6
        box.append(@summary)
        box
      end

      def split(start_child, end_child, position:)
        Gtk::Paned.new(:horizontal).tap do |paned|
          paned.start_child = start_child
          paned.end_child = end_child
          paned.position = position
          # Only the rightmost pane grows with the window; dragging is how the
          # others change size.
          paned.resize_start_child = false
          paned.shrink_start_child = false
          paned.shrink_end_child = false
        end
      end

      def pane_frame(child, scroll_sideways: false)
        scroller = Gtk::ScrolledWindow.new
        scroller.hscrollbar_policy = scroll_sideways ? :automatic : :never
        scroller.vexpand = true
        scroller.hexpand = true
        # Without this the scroller demands its child's full natural width and
        # the pane refuses to be dragged any narrower.
        scroller.propagate_natural_width = false
        scroller.child = child
        scroller
      end

      # A two-line list row: name on top, what it holds underneath.
      def list_pane(&)
        store = Gio::ListStore.new(Row)
        selection = Gtk::SingleSelection.new(store)
        selection.autoselect = false
        selection.can_unselect = false

        view = Gtk::ListView.new(selection, LibraryNameFactory.build)
        view.signal_connect('activate') do |_view, position|
          yield(store.get_item(position))
        end

        # Emptying a store emits selection-changed, and answering it by
        # reloading another pane re-enters GTK while this model is still
        # mutating — which crashes rather than misbehaves. Reloads therefore
        # announce themselves and are ignored here.
        selection.signal_connect('selection-changed') do
          next if @loading

          item = store.get_item(selection.selected)
          yield(item) if item
        end

        { widget: view, store: store, selection: selection }
      end

      def track_pane
        store = Gio::ListStore.new(Row)
        selection = Gtk::SingleSelection.new(store)
        selection.autoselect = false
        selection.can_unselect = true

        view = Gtk::ColumnView.new(selection)
        view.append_column(text_column('#', fixed_width: 40, align: :end, &:trailing))
        view.append_column(text_column('Title', expand: true, &:primary))
        view.append_column(text_column('Artist', fixed_width: 130, &:secondary))
        view.append_column(text_column('Length', fixed_width: 60, align: :end) do |row|
          row.item.duration_formatted
        end)

        connect(view, 'activate') { |_view, position| play_track(store.get_item(position)) }

        gesture = Gtk::GestureClick.new
        gesture.button = 3
        gesture.signal_connect('pressed') do |_gesture, _n, x, y|
          item = store.get_item(selection.selected) if selection.n_items.positive?
          show_track_menu(item, view, x, y) if item
        end
        view.add_controller(gesture)

        { widget: view, store: store, selection: selection }
      end

      def show_track_menu(row, widget, x, y)
        popover = Gtk::Popover.new
        box = Gtk::Box.new(:vertical, 0)
        play = Gtk::Button.new(label: 'Play')
        play.add_css_class('flat')
        play.signal_connect('clicked') do
          popover.popdown
          play_track(row)
        end
        queue = Gtk::Button.new(label: 'Add to Queue')
        queue.add_css_class('flat')
        queue.signal_connect('clicked') do
          popover.popdown
          enqueue_track(row)
        end
        box.append(play)
        box.append(queue)
        popover.child = box
        popover.set_parent(widget)
        popover.pointing_to = Gdk::Rectangle.new(x.to_i, y.to_i, 1, 1)
        popover.popup
        @track_menu = popover
      end

      def text_column(title, expand: false, fixed_width: nil, align: :start, &value)
        factory = Gtk::SignalListItemFactory.new

        factory.signal_connect('setup') do |_factory, list_item|
          label = Gtk::Label.new
          label.halign = align
          label.ellipsize = :end
          label.add_css_class('dim-label') unless title == 'Title'
          list_item.child = label
        end

        factory.signal_connect('bind') do |_factory, list_item|
          list_item.child.text = yield(list_item.item).to_s
        end

        Gtk::ColumnViewColumn.new(title, factory).tap do |column|
          column.expand = expand
          column.fixed_width = fixed_width if fixed_width
          column.resizable = true
        end
      end

      # --- Loading ------------------------------------------------------------

      def load_artists
        return if @shutdown || @library.nil?

        rows = [row(item: :any, primary: ALL_ARTISTS, secondary: track_count_label(@library.count))]

        rows += @library.artists.map do |artist|
          row(item: artist.name, primary: artist.display_name,
              secondary: album_count_label(artist.album_count))
        end

        fill(@artists, rows)
      end

      def load_albums
        return if @shutdown || @library.nil?

        albums = @library.albums(artist: @artist)
        rows = [row(item: :any, primary: ALL_ALBUMS, secondary: album_count_label(albums.size))]

        rows += albums.map do |album|
          row(item: album.title, primary: album.display_title, secondary: album_subtitle(album),
              art_url: album_thumbnail(album))
        end

        fill(@albums, rows)
      end

      def load_tracks
        return if @shutdown || @search_entry.nil?

        tracks = matching_tracks

        fill(@tracks, tracks.each_with_index.map do |track, index|
          row(item: track, primary: track.title.to_s.empty? ? track.to_s : track.title,
              secondary: track.artist.to_s, trailing: track.track_number || (index + 1))
        end)

        update_summary(tracks.size)
      end

      def matching_tracks
        query = @search_entry.text.to_s.strip
        return @library.search(query, limit: TRACK_LIMIT) unless query.empty?

        @library.tracks(artist: @artist, album: @album, limit: TRACK_LIMIT)
      end

      # One splice rather than a remove_all and two thousand appends: each
      # append emits items-changed, and the list view answers every one of
      # them.
      def fill(pane, rows)
        @loading = true
        store = pane[:store]
        store.splice(0, store.n_items, rows)
      ensure
        @loading = false
      end

      def row(item:, primary:, secondary: nil, trailing: nil, art_url: nil)
        Row.new.tap do |built|
          built.item = item
          built.primary = primary
          built.secondary = secondary
          built.trailing = trailing
          built.art_url = art_url
        end
      end

      def album_thumbnail(album)
        return nil unless @art_cache && album.path

        track = @library.track(album.path)
        @art_cache.thumbnail_for(track)
      end

      def album_subtitle(album)
        [album.year, track_count_label(album.track_count)].compact.join(' · ')
      end

      def track_count_label(count)
        count == 1 ? '1 track' : "#{count} tracks"
      end

      def album_count_label(count)
        count == 1 ? '1 album' : "#{count} albums"
      end

      def update_summary(shown = nil)
        total = @library.count
        text = "#{track_count_label(total)} in the library"
        text += " · showing #{shown}" if shown && shown < total

        @summary.text = text
      end

      def update_empty_state
        empty = @library.empty?
        @empty.visible = empty
        @panes.visible = !empty
        @summary.visible = !empty
        @search_entry.sensitive = !empty
      end

      # --- Selection ----------------------------------------------------------

      def select_artist(row)
        browse(artist: row.item) if row
      end

      def select_album(row)
        browse(artist: @artist, album: row.item) if row
      end

      # --- Playing ------------------------------------------------------------

      # Activating a track queues the whole visible list and starts at the one
      # that was chosen, which is what double-clicking a song in a library has
      # always meant. Right-click enqueues without replacing Up Next.
      def play_track(row)
        return unless row&.item.is_a?(Track)

        tracks = visible_tracks
        index = tracks.index { |track| track.file_path == row.item.file_path } || 0

        @playlist.clear
        # The tracks came out of the index with their tags already read;
        # #append keeps it that way rather than reopening every file.
        tracks.each { |track| @playlist.append(track) }
        @playlist.set_current_track(index)

        announce_playlist_change
        @player.stop
        @player.play
      end

      def enqueue_track(row)
        track = row&.item
        return unless track.is_a?(Track)

        @playlist.append(track)
        announce_playlist_change
        notify("Queued #{track.title}")
      end

      def announce_playlist_change
        @callbacks[:playlist_changed]&.call
      end

      def notify(message)
        @callbacks[:notify]&.call(message)
      end

      # --- Scanning -----------------------------------------------------------

      def choose_folder
        dialog = Gtk::FileDialog.new
        dialog.title = 'Add Music Folder to Library'

        dialog.select_folder(root) do |source, result|
          folder = source.select_folder_finish(result)
          index_folder(folder.path) if folder
        rescue StandardError => e
          notify("Could not add folder: #{e.message}")
        end
      end

      def scan_progressed(progress)
        @progress.visible = true
        @progress.fraction = progress.fraction
        @progress.text = "Indexing #{progress.scanned} of #{progress.total}"
      end

      def scan_finished(result)
        @progress.visible = false

        return notify("Could not index folder: #{result.message}") if result.is_a?(Exception)

        refresh
        notify(scan_summary(result))
      end

      def scan_summary(result)
        return 'Nothing new to index' if result.added.zero? && result.updated.zero?

        parts = []
        parts << "#{result.added} added" if result.added.positive?
        parts << "#{result.updated} updated" if result.updated.positive?
        "Library updated: #{parts.join(', ')}"
      end
    end
  end
end
