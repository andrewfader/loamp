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
      # How often the album pane is rebuilt while covers are being built for it.
      ART_REDRAW_INTERVAL = 2.0

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
        @menus = {}
        @contexts = {}
        # A view or a column takes ownership of the factory it is given. GTK
        # keeps the factory, but nothing keeps the Ruby object carrying its
        # "setup" and "bind" handlers, and a factory that has lost them
        # builds no cells at all: the panes draw rows of the right height
        # with nothing in them, or a track list that looks empty.
        @factories = []
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
        @menus.each_value(&:shutdown)
        @menus.clear
        @handlers.each { |object, id| object.signal_handler_disconnect(id) }
        @handlers.clear
        [@artists, @albums, @tracks].each do |pane|
          pane[:store].remove_all
          pane[:rows] = []
        end
        @factories.each { |factory| RowGesture.release_for(factory) }
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
        index_folders([path])
      end

      # Same, for a batch — a path pattern that matched twenty folders wants
      # one scan across all of them, not twenty that queue behind each other.
      def index_folders(paths)
        return false if @shutdown

        roots = Array(paths)
        return false if roots.empty?

        roots.each { |path| @library.add_watch_folder(path) }
        scan(roots)
      end

      def scanning?
        @scanner.running?
      end

      # Narrows the view the way clicking the panes does. `:any` means "do not
      # filter on this", which is not the same as filtering on nil — a track
      # with no album tag at all is a real thing to browse to.
      #
      # Which albums exist depends on the artist and nothing else, so picking
      # an album leaves that pane alone. Refilling it would splice out the row
      # that was just chosen and take the selection with it, leaving the pane
      # unable to say which album it is showing — the same reason
      # #redraw_album_art stands down once an album has been picked.
      def browse(artist: :any, album: :any)
        artist_changed = artist != @artist
        @artist = artist
        @album = album
        load_albums if artist_changed
        load_tracks
      end

      # Gtk::SearchEntry debounces its own search-changed signal, which is
      # what makes typing feel right and what makes a programmatic search need
      # to ask for the reload itself.
      def search_for(text)
        @search_entry.text = text.to_s
        load_tracks
      end

      # Ctrl+F reaches the library from anywhere in the window. Where the
      # caret lands is this view's business, not the shortcut handler's.
      def focus_search
        return false if @shutdown || @search_entry.nil?

        @search_entry.grab_focus
        true
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
        @artists = list_pane(:artist) { |row| select_artist(row) }
        @albums = list_pane(:album) { |row| select_album(row) }
        @tracks = track_pane

        browser = split(pane_frame(@artists[:widget]), pane_frame(@albums[:widget]),
                        position: ARTIST_PANE_WIDTH)
        panes = split(browser, track_frame, position: BROWSER_WIDTH)
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

      # The track list with its own "nothing here" message layered over it.
      # An empty Gtk::ColumnView is otherwise indistinguishable from a broken
      # one: a search that matches nothing looks exactly like a search that
      # failed to run.
      def track_frame
        overlay = Gtk::Overlay.new
        overlay.child = pane_frame(@tracks[:widget], scroll_sideways: true)
        overlay.add_overlay(track_placeholder)
        overlay
      end

      def track_placeholder
        @track_placeholder = Gtk::Label.new
        @track_placeholder.add_css_class('dim-label')
        @track_placeholder.wrap = true
        @track_placeholder.justify = :center
        @track_placeholder.halign = :center
        @track_placeholder.valign = :center
        @track_placeholder.margin_start = 18
        @track_placeholder.margin_end = 18
        @track_placeholder.visible = false
        # An overlay child swallows clicks meant for the list underneath it.
        @track_placeholder.can_target = false
        @track_placeholder
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
      def list_pane(kind, &)
        store = Gio::ListStore.new(Row)
        selection = Gtk::SingleSelection.new(store)
        selection.autoselect = false
        selection.can_unselect = false

        view = Gtk::ListView.new(selection, name_factory(kind))
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

        add_row_menu(kind, view, selection)
        { widget: view, store: store, selection: selection, rows: [] }
      end

      # An artist or album row stands for everything under it, so its menu
      # queues exactly the tracks that clicking the row would list.
      def name_factory(kind)
        LibraryNameFactory.build(row_context(kind)).tap { |factory| @factories << factory }
      end

      # One proc per pane, handed to every row that pane builds: a right-click
      # reports the row it landed on, which is what the menu then acts on.
      def row_context(kind)
        @contexts[kind] ||= lambda do |list_item, widget, x_position, y_position|
          show_row_menu(kind, list_item.item, widget, x_position, y_position)
        end
      end

      def add_row_menu(kind, widget, selection)
        menu = LibraryRowMenu.new(widget) { |action, row| act_on_row(kind, action, row) }
        @menus[kind] = menu
        RowGesture.attach_menu_key(widget) { open_row_menu(kind, widget, selection) }
        menu
      end

      # The keyboard has no row under a pointer to go on, so it acts on the
      # row the list has selected — which is the one the arrow keys just moved
      # to, and the one drawn as current. Nothing selected is not a failure
      # worth a toast; it just leaves the key alone.
      def open_row_menu(kind, widget, selection)
        x_position, y_position = RowGesture.focus_point(widget)
        show_row_menu(kind, selection.selected_item, widget, x_position, y_position)
      end

      def show_row_menu(kind, row, widget, x_position, y_position)
        menu = @menus[kind]
        return false unless menu

        menu.show(row, x_position, y_position, source: widget, heading: row&.primary)
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

        add_row_menu(:track, view, selection)
        { widget: view, store: store, selection: selection, rows: [] }
      end

      # The label fills its cell rather than shrinking to its text, so the
      # gesture it carries covers the whole width of the row it is part of.
      def text_column(title, expand: false, fixed_width: nil, align: :start, &value)
        factory = Gtk::SignalListItemFactory.new
        @factories << factory
        gestures = RowGesture.retain_for(factory)

        factory.signal_connect('setup') do |_factory, list_item|
          label = Gtk::Label.new
          label.xalign = align == :end ? 1 : 0
          label.hexpand = true
          label.ellipsize = :end
          label.add_css_class('dim-label') unless title == 'Title'
          gestures[list_item] = RowGesture.attach(label, list_item, row_context(:track))
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
        warm_album_art(albums)
      end

      def load_tracks
        return if @shutdown || @search_entry.nil?

        tracks = matching_tracks

        fill(@tracks, tracks.each_with_index.map do |track, index|
          row(item: track, primary: track.title.to_s.empty? ? track.to_s : track.title,
              secondary: track.artist.to_s, trailing: track.track_number || (index + 1))
        end)

        update_summary(tracks.size)
        update_track_placeholder(tracks.size)
      end

      def matching_tracks
        query = @search_entry.text.to_s.strip
        return @library.search(query, limit: TRACK_LIMIT) unless query.empty?

        @library.tracks(artist: @artist, album: @album, limit: TRACK_LIMIT)
      end

      # One splice rather than a remove_all and two thousand appends: each
      # append emits items-changed, and the list view answers every one of
      # them.
      # The pane keeps the rows as well as the store does. The store holds
      # each row's GObject; the fields it displays live on the Ruby object
      # wrapping it, which nothing on the GObject side keeps alive. Once the
      # last Ruby reference goes the wrapper is collected, the next bind gets
      # a blank replacement built from the surviving GObject, and the pane
      # fills with empty rows.
      def fill(pane, rows)
        @loading = true
        store = pane[:store]
        pane[:rows] = rows
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

      # The cover for an album, but only if one has already been built. Building
      # it reads a tag and decodes an image, and this is asked for every album
      # in the collection: the ones still missing are built by #warm_album_art,
      # off the main loop.
      def album_thumbnail(album)
        return nil unless @art_cache && album.path

        @art_cache.cached_thumbnail(album_track(album))
      end

      # A stand-in for one of the album's files. The art cache keys covers on
      # the album rather than the track, so the fields that key is made of are
      # the only ones that have to be right — and they all come from the album
      # row already in hand, which saves a query per album.
      def album_track(album)
        metadata = Metadata.new(album: album.title, album_artist: album.artist)
        Track.new(album.path, metadata: metadata)
      end

      # Builds the missing covers on a worker thread and fills the pane again
      # as they land. The cache refuses a second warm while one is running, so
      # a redraw part way through a batch costs nothing.
      def warm_album_art(albums)
        return if @art_cache.nil?

        filter = @artist
        tracks = albums.filter_map { |album| album_track(album) if album.path }

        @art_cache.warm_thumbnails(tracks,
                                   on_progress: -> { redraw_album_art(filter) },
                                   on_finished: -> { redraw_album_art(filter, final: true) })
      end

      # Covers have arrived, so the pane is filled again — by now every one of
      # them is a file on disk, which makes that a couple of hundred stats.
      #
      # Rows are rebuilt rather than given their new art where they stand:
      # writing to a row the store already holds means writing to a GObject
      # whose Ruby half GTK may have let go of, which segfaults rather than
      # misbehaves.
      #
      # Throttled, because warming a cold collection reports every batch and
      # rebuilding two thousand rows is a fifth of a second each time. The last
      # report is never dropped, so the pane always ends up showing everything.
      def redraw_album_art(filter, final: false)
        return if @shutdown || @albums.nil? || @artist != filter || @album != :any

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return if !final && @album_art_drawn && now - @album_art_drawn < ART_REDRAW_INTERVAL

        @album_art_drawn = now
        load_albums
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

      def update_track_placeholder(count)
        return unless @track_placeholder

        query = @search_entry.text.to_s.strip
        @track_placeholder.text =
          if query.empty?
            'No tracks here'
          else
            "No tracks match \u201C#{query}\u201D\n" \
              'Try fewer words, or clear the search.'
          end
        @track_placeholder.visible = count.zero?
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

      # --- Row actions --------------------------------------------------------

      # A track row acts on itself. An artist or album row stands for
      # everything the index holds under it, so its menu acts on exactly the
      # list that clicking the row would show in the pane to its right —
      # queueing an album no longer means selecting it and then acting on the
      # tracks it revealed.
      def act_on_row(kind, action, row)
        return unless row
        return act_on_track(action, row) if kind == :track

        tracks = row_tracks(kind, row)
        return notify("Nothing to queue for #{row.primary}") if tracks.empty?

        case action
        when :play then play_tracks(tracks)
        when :play_next then play_next_tracks(tracks, row.primary)
        when :enqueue then enqueue_tracks(tracks, row.primary)
        end
      end

      def act_on_track(action, row)
        case action
        when :play then play_track(row)
        when :play_next then play_next_track(row)
        when :enqueue then enqueue_track(row)
        end
      end

      # `:any` is the "All Artists"/"All Albums" row, and asking the index for
      # it means "do not filter on this" — the same query the pane itself ran.
      def row_tracks(kind, row)
        return [] if @library.nil?

        case kind
        when :artist then @library.tracks(artist: row.item, limit: TRACK_LIMIT)
        when :album then @library.tracks(artist: @artist, album: row.item, limit: TRACK_LIMIT)
        else []
        end
      end

      # --- Playing ------------------------------------------------------------

      # Activating a track queues the whole visible list and starts at the one
      # that was chosen, which is what double-clicking a song in a library has
      # always meant. Right-click enqueues without replacing Up Next.
      def play_track(row)
        return unless row&.item.is_a?(Track)

        tracks = visible_tracks
        index = tracks.index { |track| track.file_path == row.item.file_path } || 0
        play_tracks(tracks, index: index)
      end

      def enqueue_track(row)
        track = row&.item
        return unless track.is_a?(Track)

        enqueue_tracks([track], track.title)
      end

      def play_next_track(row)
        track = row&.item
        return unless track.is_a?(Track)

        play_next_tracks([track], track.title)
      end

      def play_tracks(tracks, index: 0)
        @playlist.clear
        # The tracks came out of the index with their tags already read;
        # #append keeps it that way rather than reopening every file.
        tracks.each { |track| @playlist.append(track) }
        @playlist.set_current_track(index)

        announce_playlist_change
        @player.stop
        @player.play
      end

      def enqueue_tracks(tracks, description)
        tracks.each { |track| @playlist.append(track) }
        announce_playlist_change
        notify("Queued #{queued_label(tracks, description)}")
      end

      # Queue immediately after whatever is playing. Appending and then
      # promoting keeps one definition of "next" — Playlist#insert_next is
      # also what teaches the shuffle order about the choice. Promoting the
      # last of what was just appended, once per track, leaves a whole album
      # sitting after the current track in its own order.
      #
      # Nothing is promoted into an empty queue: there is no current track for
      # the group to follow, and the first of them would be it.
      def play_next_tracks(tracks, description)
        playing = @playlist.size.positive?
        tracks.each { |track| @playlist.append(track) }
        tracks.size.times { @playlist.insert_next(@playlist.size - 1) } if playing

        announce_playlist_change
        notify("Playing #{queued_label(tracks, description)} next")
      end

      def queued_label(tracks, description)
        return description.to_s if tracks.size == 1

        "#{description} · #{track_count_label(tracks.size)}"
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
