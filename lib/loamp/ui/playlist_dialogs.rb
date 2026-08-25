# frozen_string_literal: true

module Loamp
  module UI
    # M3U import/export dialogs shared by the main window's queue.
    module PlaylistDialogs
      private

      def open_playlist_dialog
        dialog = Gtk::FileDialog.new
        dialog.title = 'Open Playlist'
        dialog.filters = playlist_filters
        dialog.open(self) do |source, result|
          file = source.open_finish(result)
          next unless file&.path

          count = PlaylistFile.append_to(@playlist, file.path)
          @playlist_view.refresh
          notify(count == 1 ? 'Added 1 playlist track' : "Added #{count} playlist tracks")
        rescue StandardError => e
          notify("Could not open playlist: #{e.message}")
        end
      end

      def save_playlist_dialog
        return notify('The playlist is empty') if @playlist.empty?

        dialog = Gtk::FileDialog.new
        dialog.title = 'Save Playlist'
        dialog.initial_name = 'playlist.m3u8'
        dialog.filters = playlist_filters
        dialog.save(self) do |source, result|
          file = source.save_finish(result)
          next unless file&.path

          count = PlaylistFile.save(file.path, @playlist)
          notify(count == 1 ? 'Saved 1 track' : "Saved #{count} tracks")
        rescue StandardError => e
          notify("Could not save playlist: #{e.message}")
        end
      end

      def playlist_filters
        filter = Gtk::FileFilter.new
        filter.name = 'M3U Playlists'
        filter.add_pattern('*.m3u')
        filter.add_pattern('*.m3u8')

        Gio::ListStore.new(Gtk::FileFilter).tap { |filters| filters.append(filter) }
      end
    end
  end
end
