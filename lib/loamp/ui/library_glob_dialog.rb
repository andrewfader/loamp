# frozen_string_literal: true

module Loamp
  module UI
    # Add library folders by path pattern, with a dry run first.
    #
    # The chooser in LibraryFoldersDialog asks for one folder at a time, which
    # is the wrong shape for a disk whose music is scattered across mount
    # points. Here the listener types /mnt/**/downloads*, sees exactly which
    # folders that names and how many tracks each holds, unticks the ones
    # they did not mean, and only then adds them. Nothing is written until
    # Add is pressed.
    #
    # The walk happens on a worker thread — a pattern rooted at / spends
    # minutes in Dir.glob, and a frozen window during it looks like a crash.
    # Results come back through GLib::Idle, the only place widgets may be
    # touched.
    class LibraryGlobDialog
      TITLE = 'Add Folders by Pattern'
      DESCRIPTION = 'Shell-style patterns: * matches within one name, ' \
                    '** matches folders recursively. Nothing is added until ' \
                    'you press Add.'
      PLACEHOLDER = '/mnt/**/downloads*'

      def self.present(parent, library:, on_added: nil)
        new(parent, library: library, on_added: on_added).present
      end

      def initialize(parent, library:, on_added: nil)
        @parent = parent
        @library = library
        @on_added = on_added
        @rows = []
        @result = nil
        @dialog = build_dialog
        update_add_button
      end

      def present
        @dialog.transient_for = @parent if @parent.is_a?(Gtk::Window)
        @dialog.present
        @entry&.grab_focus
      end

      # --- Dry run ------------------------------------------------------------

      # Walks the pattern and shows what it matched. Never touches the
      # library, which is the whole point of running it before Add.
      def preview(pattern = @entry&.text.to_s, async: true)
        @glob&.cancel
        glob = Library::FolderGlob.new(pattern, watched: @library.stored_watch_folders)
        @glob = glob
        searching(pattern)

        return show_result(glob.preview) unless async

        walk(glob)
      end

      # Adds the ticked folders as watch roots and hands them to the caller in
      # one batch, so a pattern matching twenty folders starts one scan rather
      # than twenty.
      def add_selected
        paths = selected_paths
        return notify('Nothing selected to add') if paths.empty?

        added = paths.select { |path| @library.add_watch_folder(path) }
        return notify('Those folders could not be added') if added.empty?

        @dialog.close
        @on_added&.call(added.map { |path| File.expand_path(path) })
      end

      def selected_paths
        @rows.select { |check, _path| check.active? }.map { |_check, path| path }
      end

      private

      attr_reader :rows, :summary

      # --- Widgets ------------------------------------------------------------

      def build_dialog
        dialog = Gtk::Window.new
        dialog.title = TITLE
        dialog.set_default_size(560, 420)
        dialog.modal = true
        dialog.child = build_content
        dialog.signal_connect('close-request') do
          @glob&.cancel
          false
        end
        dialog
      end

      def build_content
        box = Gtk::Box.new(:vertical, 12)
        box.margin_top = 16
        box.margin_bottom = 16
        box.margin_start = 16
        box.margin_end = 16

        box.append(description_label)
        box.append(build_search_row)
        box.append(@summary = summary_label)
        box.append(build_results)
        box.append(build_actions)
        box
      end

      def description_label
        label = Gtk::Label.new(DESCRIPTION)
        label.wrap = true
        label.xalign = 0
        label.add_css_class('dim-label')
        label
      end

      def summary_label
        label = Gtk::Label.new('')
        label.wrap = true
        label.xalign = 0
        label.add_css_class('dim-label')
        label
      end

      def build_search_row
        row = Gtk::Box.new(:horizontal, 6)

        @entry = Gtk::Entry.new
        @entry.placeholder_text = PLACEHOLDER
        @entry.hexpand = true
        @entry.activates_default = false
        @entry.signal_connect('activate') { preview }

        @preview_button = Gtk::Button.new(label: 'Preview')
        @preview_button.tooltip_text = 'Show what this pattern matches, without adding anything'
        @preview_button.signal_connect('clicked') { preview }

        row.append(@entry)
        row.append(@preview_button)
        row
      end

      def build_results
        @list = Gtk::ListBox.new
        @list.selection_mode = Gtk::SelectionMode::NONE
        @list.add_css_class('boxed-list')

        scroller = Gtk::ScrolledWindow.new
        scroller.vexpand = true
        scroller.child = @list
        scroller
      end

      def build_actions
        row = Gtk::Box.new(:horizontal, 6)
        row.halign = Gtk::Align::END

        @select_all = Gtk::Button.new(label: 'Select All')
        @select_all.signal_connect('clicked') { set_all_selected(true) }
        none = Gtk::Button.new(label: 'Select None')
        none.signal_connect('clicked') { set_all_selected(false) }

        cancel = Gtk::Button.new(label: 'Cancel')
        cancel.signal_connect('clicked') { @dialog.close }

        @add_button = Gtk::Button.new(label: 'Add')
        @add_button.add_css_class('suggested-action')
        @add_button.signal_connect('clicked') { add_selected }

        [@select_all, none, cancel, @add_button].each { |button| row.append(button) }
        row
      end

      # --- Results ------------------------------------------------------------

      def searching(pattern)
        clear_rows
        @summary.text = "Searching #{pattern}…"
        @preview_button.sensitive = false
        update_add_button
      end

      def show_result(result)
        @result = result
        @preview_button.sensitive = true
        clear_rows

        return show_error(result.error) if result.error?

        result.matches.each { |match| @list.append(match_row(match)) }
        @list.append(label_row(no_matches_text)) if result.empty?
        @summary.text = summary_text(result)
        update_add_button
      end

      def show_error(message)
        @summary.text = message
        @list.append(label_row(message))
        update_add_button
      end

      def summary_text(result)
        return no_matches_text if result.empty?

        parts = ["#{plural(result.matches.size, 'folder')} matched",
                 "#{plural(result.track_count, 'track')} in total"]
        watched = result.matches.count(&:watched?)
        parts << "#{watched} already in the library" if watched.positive?
        parts << "#{plural(result.skipped_files, 'file')} matched but skipped" if
          result.skipped_files.to_i.positive?
        parts << "showing the first #{Library::FolderGlob::MAX_MATCHES}" if result.truncated
        parts.join(' · ')
      end

      def no_matches_text
        'Nothing matched that pattern'
      end

      def match_row(match)
        row = Gtk::Box.new(:horizontal, 8)
        row.margin_top = 6
        row.margin_bottom = 6
        row.margin_start = 8
        row.margin_end = 8

        check = Gtk::CheckButton.new
        check.active = !match.watched?
        check.sensitive = !match.watched?
        check.valign = Gtk::Align::CENTER
        check.signal_connect('toggled') { update_add_button }
        @rows << [check, match.path]

        row.append(check)
        row.append(match_labels(match))
        row.append(count_label(match))
        row
      end

      def match_labels(match)
        labels = Gtk::Box.new(:vertical, 2)
        labels.hexpand = true

        title = Gtk::Label.new(match.watched? ? "#{match.name} (already watched)" : match.name)
        title.xalign = 0
        path = Gtk::Label.new(match.path)
        path.xalign = 0
        path.add_css_class('dim-label')
        path.ellipsize = Pango::EllipsizeMode::START

        labels.append(title)
        labels.append(path)
        labels
      end

      def count_label(match)
        label = Gtk::Label.new(plural(match.track_count.to_i, 'track'))
        label.valign = Gtk::Align::CENTER
        label.add_css_class('dim-label')
        label
      end

      def label_row(text)
        label = Gtk::Label.new(text)
        label.xalign = 0
        label.wrap = true
        label.margin_top = 10
        label.margin_bottom = 10
        label.margin_start = 12
        label.margin_end = 12
        label
      end

      def clear_rows
        @rows = []
        while (child = @list.first_child)
          @list.remove(child)
        end
      end

      def set_all_selected(selected)
        @rows.map(&:first).each { |check| check.active = selected if check.sensitive? }
        update_add_button
      end

      def update_add_button
        count = selected_paths.size
        @add_button.sensitive = count.positive?
        @add_button.label = count.positive? ? "Add #{plural(count, 'Folder')}" : 'Add'
      end

      def plural(count, noun)
        "#{count} #{noun}#{'s' unless count == 1}"
      end

      # --- Threading ----------------------------------------------------------

      # Walks on a worker thread and reports on the main loop. A result from
      # a superseded pattern is dropped rather than drawn: typing a second
      # pattern while the first is still walking should not repaint the list
      # with the first one's answer.
      def walk(glob)
        @thread = Thread.new do
          result = begin
            glob.preview
          rescue StandardError => e
            Library::FolderGlob::Result.new(matches: [], error: e.message)
          end

          idle { show_result(result) if @glob.equal?(glob) }
        end
      end

      def idle(&)
        unless defined?(GLib::Idle)
          yield
          return
        end

        GLib::Idle.add do
          yield
          false
        end
      end

      def notify(message)
        @parent.notify(message) if @parent.respond_to?(:notify)
      end
    end
  end
end
