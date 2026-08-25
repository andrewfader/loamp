# frozen_string_literal: true

module Loamp
  module UI
    # The playlist, as a virtualised column list.
    #
    # Gtk::ColumnView only builds rows for what is on screen, so a playlist of
    # ten thousand tracks costs the same to display as one of ten. It replaces
    # Gtk::TreeView, which GTK4 deprecated.
    class PlaylistView < Gtk::ScrolledWindow
      # A GObject wrapper so tracks can live in a Gio::ListModel.
      class Row < GLib::Object
        type_register

        attr_accessor :track, :position
      end

      SIDEBAR_MIN_WIDTH = 280

      def initialize(playlist, player)
        super()
        @playlist = playlist
        @player = player

        create_model
        create_column_view
        build_columns
        connect_signals
        setup_player_callbacks

        set_policy(:never, :automatic)
        set_size_request(SIDEBAR_MIN_WIDTH, -1)
        # Without this the scroller demands the columns' full natural width and
        # the last column ends up clipped by the sidebar edge.
        self.propagate_natural_width = false
        self.child = @column_view

        refresh
      end

      # Rebuilds the model from the playlist.
      def refresh
        @store.remove_all

        @playlist.each_with_index do |track, index|
          row = Row.new
          row.track = track
          row.position = index + 1
          @store.append(row)
        end

        update_current_track_highlight
      end

      # A popover parented by hand has to be unparented by hand: GTK4 warns
      # about "finalizing a widget that still has children left" otherwise,
      # and the dangling parent pointer it leaves behind turns into a crash
      # somewhere else entirely. GtkWidget::destroy does not fire for a child
      # widget, so the owner of the view has to say when it is finished.
      def shutdown
        @context_menu&.unparent
        @context_menu = nil
      end

      def selected_index
        position = @selection.selected
        position == Gtk::INVALID_LIST_POSITION ? nil : position
      end

      private

      def create_model
        @store = Gio::ListStore.new(Row)
        @selection = Gtk::SingleSelection.new(@store)
        # Selecting a row should not start playback; that is what activation is
        # for. Autoselect would also fight the current-track highlight.
        @selection.autoselect = false
        @selection.can_unselect = true
      end

      def create_column_view
        @column_view = Gtk::ColumnView.new(@selection)
        @column_view.add_css_class('loamp-queue')
        @column_view.show_row_separators = false
      end

      def build_columns
        @column_view.append_column(number_column)
        @column_view.append_column(title_column)
        @column_view.append_column(duration_column)
      end

      def number_column
        factory = text_factory(css_classes: %w[dim-label numeric], align: :end) do |row|
          row.position.to_s
        end

        column('#', factory, fixed_width: 44)
      end

      def title_column
        factory = text_factory(ellipsize: true) { |row| row.track.to_s }

        column('Title', factory, expand: true)
      end

      def duration_column
        factory = text_factory(css_classes: %w[dim-label numeric], align: :end) do |row|
          row.track.duration_formatted
        end

        column('Length', factory, fixed_width: 64)
      end

      def column(title, factory, expand: false, fixed_width: nil)
        Gtk::ColumnViewColumn.new(title, factory).tap do |col|
          col.expand = expand
          col.fixed_width = fixed_width if fixed_width
          col.resizable = true
        end
      end

      # ColumnView builds cells lazily: "setup" creates a reusable widget and
      # "bind" fills it in for whichever row is scrolling into view.
      def text_factory(css_classes: [], align: :start, ellipsize: false)
        factory = Gtk::SignalListItemFactory.new

        factory.signal_connect('setup') do |_factory, list_item|
          label = Gtk::Label.new
          label.halign = align
          label.ellipsize = :end if ellipsize
          css_classes.each { |name| label.add_css_class(name) }
          list_item.child = label
        end

        factory.signal_connect('bind') do |_factory, list_item|
          list_item.child.text = yield(list_item.item).to_s
        end

        factory
      end

      def connect_signals
        @column_view.signal_connect('activate') do |_view, position|
          play_track_at(position)
        end

        add_context_menu
      end

      def play_track_at(position)
        return unless @playlist.set_current_track(position)

        @player.stop
        @player.play
      end

      # GTK4 has no Gtk::Menu; a popover anchored to the click is the
      # replacement.
      def add_context_menu
        @context_menu = build_context_menu

        gesture = Gtk::GestureClick.new
        gesture.button = 3
        gesture.signal_connect('pressed') do |_gesture, _presses, x, y|
          show_context_menu(x, y)
        end
        @column_view.add_controller(gesture)
      end

      def build_context_menu
        menu = Gio::Menu.new
        menu.append('Play', 'playlist.play')
        menu.append('Play Next', 'playlist.play-next')
        menu.append('Move Up', 'playlist.move-up')
        menu.append('Move Down', 'playlist.move-down')
        menu.append('Remove from Playlist', 'playlist.remove')

        popover = Gtk::PopoverMenu.new(menu)
        # set_parent, not parent=: Gtk::Popover exposes a struct field of the
        # same name through introspection, and assigning to it segfaults.
        popover.set_parent(self)
        popover.has_arrow = false
        popover.halign = :start

        install_context_actions
        popover
      end

      def install_context_actions
        group = Gio::SimpleActionGroup.new
        group.add_action(action('play') { play_selected })
        group.add_action(action('play-next') { play_selected_next })
        group.add_action(action('move-up') { move_selected(-1) })
        group.add_action(action('move-down') { move_selected(1) })
        group.add_action(action('remove') { remove_selected })
        insert_action_group('playlist', group)

        keys = Gtk::EventControllerKey.new
        keys.signal_connect('key-pressed') do |_controller, keyval, _keycode, state|
          handle_queue_key(keyval, state)
        end
        @column_view.add_controller(keys)
      end

      def action(name, &)
        Gio::SimpleAction.new(name).tap do |simple_action|
          simple_action.signal_connect('activate', &)
        end
      end

      # Popping up a popover whose widget is not yet inside a toplevel window
      # crashes GTK rather than failing politely, so check before asking.
      def show_context_menu(x_position, y_position)
        return unless root

        rectangle = Gdk::Rectangle.new(x_position.to_i, y_position.to_i, 1, 1)
        @context_menu.pointing_to = rectangle
        @context_menu.popup
      end

      def play_selected
        index = selected_index
        play_track_at(index) if index
      end

      def play_selected_next
        index = selected_index
        return unless index

        new_index = @playlist.insert_next(index)
        refresh_and_select(new_index)
      end

      def move_selected(offset)
        index = selected_index
        return unless index

        new_index = @playlist.move(index, offset)
        refresh_and_select(new_index)
      end

      def refresh_and_select(index)
        refresh
        @selection.selected = index if index
      end

      def handle_queue_key(keyval, state)
        return remove_selected || true if keyval == Gdk::Keyval::KEY_Delete

        alt = state.to_i.anybits?(Gdk::ModifierType::ALT_MASK.to_i)
        return false unless alt
        return move_selected(-1) || true if keyval == Gdk::Keyval::KEY_Up
        return move_selected(1) || true if keyval == Gdk::Keyval::KEY_Down

        false
      end

      def remove_selected
        index = selected_index
        return unless index

        playing_removed = index == @playlist.current_index
        @player.stop if playing_removed

        @playlist.remove_at(index)
        refresh
      end

      def setup_player_callbacks
        @player.on_track_changed { |_track| update_current_track_highlight }
      end

      def update_current_track_highlight
        index = @playlist.current_index
        return if index.nil? || index >= @store.n_items

        @selection.selected = index
        @column_view.scroll_to(index, nil, :none, nil) if @column_view.respond_to?(:scroll_to)
      rescue StandardError
        # Scrolling is a convenience; never let it break the refresh.
        nil
      end
    end
  end
end
