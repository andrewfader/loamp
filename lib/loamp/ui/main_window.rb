# frozen_string_literal: true

module Loamp
  module UI
    # The application window.
    #
    # Built from libadwaita primitives so it looks and behaves like a native
    # GNOME application: an AdwToolbarView holding an AdwHeaderBar, an
    # adaptive split view for the playlist, and toasts instead of a status bar.
    class MainWindow < Adw::Window
      include SecondaryViews
      include PlaybackObservers
      include KeyboardShortcuts

      TITLE = 'LOAMP'
      SUBTITLE = 'Linux Open Audio Music Player'
      WINDOW_TITLE = "#{TITLE} - #{SUBTITLE}".freeze
      CSS_PATH = File.expand_path('../../../assets/style.css', __dir__)

      DEFAULT_WIDTH = 900
      DEFAULT_HEIGHT = 620

      # Below this width the playlist collapses into an overlay instead of
      # squeezing the now-playing pane.
      COLLAPSE_BREAKPOINT = 700

      # The library is optional: the player works perfectly well as a
      # queue-what-you-drop-in player, and a window built without one simply
      # has no Library page.
      def initialize(player, playlist, library: nil, **services)
        super()
        @player = player
        @playlist = playlist
        @library = library
        @radio_browser = services[:radio_browser]
        @podcasts = services[:podcasts]
        @providers = services[:providers]
        @radio_services = services[:radio_services]
        @art_cache = services[:art_cache]

        setup_window
        create_widgets
        layout_widgets
        setup_actions
        setup_keyboard_shortcuts
        setup_player_callbacks
        setup_teardown
      end

      # Tells the views to let go of the things GTK will not clean up on their
      # behalf — a scan in flight, a hand-parented popover. Closing the window
      # does not reach its children, so the window has to say when it is done.
      #
      # Runs at most once: the window can be closed by its button, by app.quit,
      # or by both in that order.
      def shutdown
        return if @shutdown

        @shutdown = true
        @playlist_view.shutdown
        @library_view&.shutdown
        @radio_view&.shutdown
        @podcast_view&.shutdown
        @provider_view&.shutdown
        @graph_view&.shutdown
        @visualizer_view.shutdown
      end

      # Cover art that was not on this machine when the track started, and has
      # since been fetched. Drawn only if that track is still the one showing.
      def artwork_arrived(track, url)
        @track_info.show_artwork_from(track, url)
      end

      def show_lyrics(track, document)
        return unless @player.current_track.equal?(track)

        @lyrics_view.show_document(track, document)
      end

      # Shows a transient message. Replaces the old status bar, which GTK4
      # deprecated and which had nowhere sensible to live in an Adwaita layout.
      def notify(message)
        @toast_overlay.add_toast(Adw::Toast.new(message))
      end

      private

      # Not GtkWidget::destroy: in GTK4 that signal is emitted from dispose, so
      # it does not fire while anything still holds a reference to the window —
      # which Ruby always does. close-request fires when the window is actually
      # closed. Returning false lets the default handler close it as usual.
      #
      # Quitting through app.quit closes no window at all, so Application calls
      # #shutdown directly as well.
      def setup_teardown
        signal_connect('close-request') do
          shutdown
          false
        end
      end

      def setup_window
        set_title(WINDOW_TITLE)
        set_default_size(DEFAULT_WIDTH, DEFAULT_HEIGHT)
        Style.load_css(CSS_PATH)
      end

      def create_widgets
        create_header_bar

        @playlist_view = PlaylistView.new(@playlist, @player)
        @track_info = TrackInfo.new
        @lyrics_view = LyricsView.new
        @player_controls = PlayerControls.new(@player)
        @visualizer_view = VisualizerView.new(@player)

        @view_stack = Adw::ViewStack.new
        @split_view = Adw::OverlaySplitView.new
        @toolbar_view = Adw::ToolbarView.new
        @toast_overlay = Adw::ToastOverlay.new

        create_library_view
        create_radio_view
        create_podcast_view
        create_provider_view
        create_graph_view
      end

      def create_header_bar
        @header_bar = Adw::HeaderBar.new
        @header_bar.add_css_class('loamp-header')
        @window_title = Adw::WindowTitle.new(TITLE, SUBTITLE)
        @header_bar.title_widget = @window_title

        @sidebar_button = Gtk::ToggleButton.new
        @sidebar_button.icon_name = 'sidebar-show-symbolic'
        @sidebar_button.tooltip_text = 'Toggle Playlist'
        @sidebar_button.active = true
        @header_bar.pack_start(@sidebar_button)

        @add_file_button = build_button('list-add-symbolic', 'Add Files') { open_file_dialog }
        @header_bar.pack_start(@add_file_button)

        @add_folder_button = build_button('folder-open-symbolic', add_folder_tooltip) do
          open_folder_dialog
        end
        @header_bar.pack_start(@add_folder_button)

        @header_bar.pack_end(build_menu_button)
        return unless @radio_services

        @header_bar.pack_end(build_button('system-search-symbolic',
                                          'Similar to current track') do
                                            discover_similar(@player.current_track)
                                          end)
      end

      def build_button(icon_name, tooltip, &)
        button = Gtk::Button.new
        button.icon_name = icon_name
        button.tooltip_text = tooltip
        button.signal_connect('clicked', &)
        button
      end

      def build_menu_button
        @menu_button = Gtk::MenuButton.new
        @menu_button.icon_name = 'open-menu-symbolic'
        @menu_button.tooltip_text = 'Main Menu'

        menu = Gio::Menu.new
        menu.append('Clear Playlist', 'win.clear')
        menu.append('Rescan Library', 'win.rescan') if @library
        menu.append('Internet Radio', 'win.show-radio') if @radio_browser
        menu.append('Similar Artists', 'win.show-discovery') if @radio_services
        PlaybackMenu.append_to(menu)
        menu.append('About LOAMP', 'win.about')
        menu.append('Quit', 'app.quit')

        @menu_button.menu_model = menu
        @menu_button
      end

      def layout_widgets
        @split_view.sidebar = wrap_sidebar(@playlist_view)
        @split_view.content = build_views
        @split_view.min_sidebar_width = 260
        @split_view.max_sidebar_width = 420

        @sidebar_button.bind_property('active', @split_view, 'show-sidebar',
                                      GLib::BindingFlags::BIDIRECTIONAL |
                                      GLib::BindingFlags::SYNC_CREATE)

        @toolbar_view.add_top_bar(@header_bar)
        @toolbar_view.content = @split_view
        @toolbar_view.add_bottom_bar(build_view_switcher) if switchable_views?

        @toast_overlay.child = @toolbar_view
        self.content = @toast_overlay

        install_breakpoint
      end

      # Keeps the window usable when it is narrow, which is what makes an
      # Adwaita app feel at home on a tiling compositor or a small screen.
      # Named to avoid shadowing Adw::Window#add_breakpoint.
      def install_breakpoint
        condition = Adw::BreakpointCondition.parse("max-width: #{COLLAPSE_BREAKPOINT}px")
        breakpoint = Adw::Breakpoint.new(condition)
        breakpoint.add_setter(@split_view, 'collapsed', true)
        add_breakpoint(breakpoint)
      rescue StandardError => e
        warn "Adaptive breakpoint unavailable: #{e.message}"
      end

      def wrap_sidebar(child)
        page = Gtk::Box.new(:vertical, 0)
        page.add_css_class('loamp-sidebar')

        heading = Gtk::Box.new(:horizontal, 8)
        heading.add_css_class('loamp-sidebar-heading')

        title = Gtk::Label.new('UP NEXT')
        title.add_css_class('loamp-kicker')
        title.xalign = 0
        title.hexpand = true

        hint = Gtk::Label.new('DOUBLE-CLICK TO PLAY')
        hint.add_css_class('loamp-microcopy')
        heading.append(title)
        heading.append(hint)

        page.append(heading)
        page.append(child)
        child.vexpand = true
        page
      end

      # Now Playing and Library are pages of one stack rather than two
      # windows, so switching between them keeps the transport where it is.
      def build_views
        @view_stack.add_titled_with_icon(build_now_playing, 'playing', 'Now Playing',
                                         'media-playback-start-symbolic')
        @view_stack.add_titled_with_icon(@lyrics_view, 'lyrics', 'Lyrics',
                                         'document-edit-symbolic')
        @view_stack.add_titled_with_icon(@visualizer_view, 'visualizer', 'Visualizer',
                                         'applications-graphics-symbolic')
        if @library_view
          @view_stack.add_titled_with_icon(@library_view, 'library', 'Library',
                                           'view-list-symbolic')
        end
        if @radio_view
          @view_stack.add_titled_with_icon(@radio_view, 'radio', 'Radio',
                                           'network-wireless-symbolic')
        end
        if @podcast_view
          @view_stack.add_titled_with_icon(@podcast_view, 'podcasts', 'Podcasts',
                                           'audio-x-generic-symbolic')
        end
        if @provider_view
          @view_stack.add_titled_with_icon(@provider_view, 'streaming', 'Streaming',
                                           'folder-remote-symbolic')
        end
        if @graph_view
          @view_stack.add_titled_with_icon(@graph_view, 'discovery', 'Discover',
                                           'find-location-symbolic')
        end
        @view_stack
      end

      def build_view_switcher
        bar = Adw::ViewSwitcherBar.new
        bar.stack = @view_stack
        bar.reveal = true
        bar
      end

      # The track details scroll; the transport controls stay put, because
      # controls you have to scroll to reach are not controls.
      def build_now_playing
        scroller = Gtk::ScrolledWindow.new
        scroller.hscrollbar_policy = :never
        scroller.vexpand = true
        scroller.child = @track_info

        box = Gtk::Box.new(:vertical, 12)
        box.add_css_class('loamp-now-playing')
        box.margin_top = 20
        box.margin_bottom = 20
        box.margin_start = 20
        box.margin_end = 20

        box.append(scroller)
        box.append(@player_controls)
        box
      end

      def setup_actions
        group = Gio::SimpleActionGroup.new
        group.add_action(build_action('clear') { clear_playlist })
        group.add_action(build_action('about') { show_about_dialog })
        group.add_action(build_action('rescan') { rescan_library }) if @library
        group.add_action(build_action('show-radio') { show_view('radio') }) if @radio_view
        group.add_action(build_action('show-discovery') { show_discovery }) if @graph_view
        PlaybackMenu.install_actions(group, @player)
        insert_action_group('win', group)
      end

      def build_action(name, &)
        action = Gio::SimpleAction.new(name)
        action.signal_connect('activate', &)
        action
      end

      def show_view(name)
        @view_stack.visible_child_name = name
      end

      def open_file_dialog
        dialog = Gtk::FileDialog.new
        dialog.title = 'Add Audio Files'
        dialog.filters = audio_filters

        dialog.open_multiple(self) do |source, result|
          files = source.open_multiple_finish(result)
          add_files(files) if files
        rescue StandardError => e
          notify("Could not add files: #{e.message}")
        end
      end

      def add_files(files)
        selected = if files.respond_to?(:n_items) && files.respond_to?(:get_item)
                     Array.new(files.n_items) { |index| files.get_item(index) }
                   else
                     files.to_a
                   end
        paths = selected.filter_map(&:path)
        paths.each { |path| @playlist.add_track(path) }
        @playlist_view.refresh
        notify(paths.size == 1 ? 'Added 1 track' : "Added #{paths.size} tracks")
      end

      def audio_filters
        audio = Gtk::FileFilter.new
        audio.name = 'Audio Files'
        audio.add_mime_type('audio/*')
        Playlist::AUDIO_EXTENSIONS.each { |extension| audio.add_pattern("*#{extension}") }

        everything = Gtk::FileFilter.new
        everything.name = 'All Files'
        everything.add_pattern('*')

        Gio::ListStore.new(Gtk::FileFilter).tap do |filters|
          filters.append(audio)
          filters.append(everything)
        end
      end

      def open_folder_dialog
        dialog = Gtk::FileDialog.new
        dialog.title = @library ? 'Add Music Folder to Library' : 'Add Music Folder'

        dialog.select_folder(self) do |source, result|
          folder = source.select_folder_finish(result)
          add_folder(folder) if folder
        rescue StandardError => e
          notify("Could not add folder: #{e.message}")
        end
      end

      def add_folder(folder)
        path = folder.path
        return queue_folder(path) unless @library_view

        show_view('library')
        started = @library_view.index_folder(path)
        notify(started ? "Indexing #{File.basename(path)}" : 'A library scan is already running')
      end

      def queue_folder(path)
        before = @playlist.size
        @playlist.add_directory(path)
        @playlist_view.refresh
        notify("Added #{@playlist.size - before} tracks")
      end

      def clear_playlist
        @player.stop
        @playlist.clear
        @playlist_view.refresh
        @track_info.clear
        update_window_title(nil)
        notify('Playlist cleared')
      end

      def add_folder_tooltip
        @library ? 'Add Folder to Library' : 'Add Folder'
      end

      def rescan_library
        folders = @library.watch_folders
        return notify('The library is empty — add a folder first') if folders.empty?

        show_view('library')
        notify('Rescanning the library')
        @library_view.scan(folders)
      end

      def show_about_dialog
        dialog = Adw::AboutDialog.new
        dialog.application_name = TITLE
        dialog.version = Loamp::VERSION
        dialog.comments = SUBTITLE
        dialog.license_type = Gtk::License::MIT_X11
        dialog.developer_name = 'LOAMP contributors'
        dialog.present(self)
      rescue StandardError => e
        warn "Could not show about dialog: #{e.message}"
      end

      # The header shows what is playing; the window title is what the
      # compositor and window switcher display.
      def update_window_title(track)
        if track
          @window_title.title = track.title.to_s
          @window_title.subtitle = track.artist.to_s
          set_title("#{track} - #{TITLE}")
        else
          @window_title.title = TITLE
          @window_title.subtitle = SUBTITLE
          set_title(WINDOW_TITLE)
        end
      end
    end
  end
end
