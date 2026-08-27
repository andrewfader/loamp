# frozen_string_literal: true

module Loamp
  module UI
    # Manage the folders LOAMP auto-scans into the library.
    #
    # Each path is an entire tree: adding one indexes every audio file under
    # it, remembers the root for Rescan, and (on launch) picks up anything
    # new without the listener having to ask again.
    class LibraryFoldersDialog
      TITLE = 'Library Folders'
      DESCRIPTION = 'Entire folder trees are indexed into the library and ' \
                    'scanned again on launch.'

      def self.present(parent, library:, on_changed: nil)
        new(parent, library: library, on_changed: on_changed).present
      end

      def initialize(parent, library:, on_changed: nil)
        @parent = parent
        @library = library
        @on_changed = on_changed
        @dialog = build_dialog
        rebuild_rows
      end

      def present
        @dialog.transient_for = @parent if @parent.is_a?(Gtk::Window)
        @dialog.present
      end

      private

      def build_dialog
        dialog = Gtk::Window.new
        dialog.title = TITLE
        dialog.set_default_size(480, 360)
        dialog.modal = true
        dialog.child = build_content
        dialog
      end

      def build_content
        box = Gtk::Box.new(:vertical, 12)
        box.margin_top = 16
        box.margin_bottom = 16
        box.margin_start = 16
        box.margin_end = 16

        description = Gtk::Label.new(DESCRIPTION)
        description.wrap = true
        description.xalign = 0
        description.add_css_class('dim-label')
        box.append(description)

        toolbar = Gtk::Box.new(:horizontal, 6)
        add = Gtk::Button.new(label: 'Add Folder')
        add.signal_connect('clicked') { choose_folder }
        close = Gtk::Button.new(label: 'Close')
        close.signal_connect('clicked') { @dialog.close }
        toolbar.append(add)
        toolbar.append(close)
        box.append(toolbar)

        @list = Gtk::ListBox.new
        @list.selection_mode = Gtk::SelectionMode::NONE
        @list.add_css_class('boxed-list')

        scroller = Gtk::ScrolledWindow.new
        scroller.vexpand = true
        scroller.child = @list
        box.append(scroller)
        box
      end

      def rebuild_rows
        while (child = @list.first_child)
          @list.remove(child)
        end

        paths = @library.stored_watch_folders
        if paths.empty?
          @list.append(label_row('No folders yet — add a music folder to auto-scan'))
          return
        end

        paths.each { |path| @list.append(folder_row(path)) }
      end

      def label_row(text)
        label = Gtk::Label.new(text)
        label.xalign = 0
        label.margin_top = 10
        label.margin_bottom = 10
        label.margin_start = 12
        label.margin_end = 12
        label.wrap = true
        label
      end

      def folder_row(path)
        row = Gtk::Box.new(:horizontal, 8)
        row.margin_top = 6
        row.margin_bottom = 6
        row.margin_start = 8
        row.margin_end = 8

        labels = Gtk::Box.new(:vertical, 2)
        labels.hexpand = true
        title = Gtk::Label.new(File.basename(path))
        title.xalign = 0
        subtitle = Gtk::Label.new(path)
        subtitle.xalign = 0
        subtitle.add_css_class('dim-label')
        subtitle.ellipsize = Pango::EllipsizeMode::START
        labels.append(title)
        labels.append(subtitle)

        remove = Gtk::Button.new
        remove.icon_name = 'list-remove-symbolic'
        remove.tooltip_text = 'Stop scanning this folder'
        remove.valign = Gtk::Align::CENTER
        remove.add_css_class('flat')
        remove.signal_connect('clicked') { remove_folder(path) }

        row.append(labels)
        row.append(remove)
        row
      end

      def choose_folder
        picker = Gtk::FileDialog.new
        picker.title = 'Add Music Folder to Library'

        picker.select_folder(@dialog) do |source, result|
          folder = source.select_folder_finish(result)
          next unless folder&.path

          add_folder(folder.path)
        rescue StandardError => e
          notify("Could not add folder: #{e.message}")
        end
      end

      def add_folder(path)
        return notify('That path is not a folder') unless @library.add_watch_folder(path)

        rebuild_rows
        @on_changed&.call(:added, File.expand_path(path))
      end

      def remove_folder(path)
        dialog = Adw::AlertDialog.new(
          'Remove library folder?',
          "Stop scanning #{File.basename(path)} and remove its tracks from the library?"
        )
        dialog.add_response('cancel', 'Cancel')
        dialog.add_response('remove', 'Remove')
        dialog.set_response_appearance('remove', :destructive)
        dialog.default_response = 'cancel'
        dialog.close_response = 'cancel'
        dialog.signal_connect('response') do |_dialog, response|
          apply_remove_folder(path) if response == 'remove'
        end
        dialog.present(@dialog)
      end

      def apply_remove_folder(path)
        return unless @library.remove_watch_folder(path)

        rebuild_rows
        @on_changed&.call(:removed, File.expand_path(path))
      end

      def notify(message)
        @parent.notify(message) if @parent.respond_to?(:notify)
      end
    end
  end
end
