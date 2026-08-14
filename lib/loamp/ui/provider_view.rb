# frozen_string_literal: true

module Loamp
  module UI
    class ProviderView < Gtk::Box
      def initialize(registry, playlist, player)
        super(:vertical, 6)
        @registry = registry
        @playlist = playlist
        @player = player
        @items = []
        @callbacks = {}
        @generation = 0
        build
      end

      def on_playlist_changed(&block) = (@callbacks[:playlist_changed] = block)
      def on_notify(&block) = (@callbacks[:notify] = block)

      def search(query)
        text = query.to_s.strip
        return false if text.empty? || @shutdown

        generation = (@generation += 1)
        @spinner.start
        Thread.new do
          items = @registry.search(text)
          GLib::Idle.add { finish_search(generation, items) }
        end
        true
      end

      def play(index)
        item = @items[index]
        return false unless item

        track = @registry.track_for(item)
        unless track
          message = item.external_url ? 'Open this item in its provider' : 'Item is not playable'
          @callbacks[:notify]&.call(message)
          return false
        end

        @playlist.append(track)
        @playlist.set_current_track(@playlist.size - 1)
        @callbacks[:playlist_changed]&.call
        @player.stop
        @player.play
        track
      end

      def shutdown
        @shutdown = true
        @generation += 1
        clear
      end

      private

      def build
        @entry = Gtk::SearchEntry.new
        @entry.placeholder_text = 'Search connected music servers'
        @entry.hexpand = true
        @entry.signal_connect('activate') { search(@entry.text) }
        @spinner = Gtk::Spinner.new

        toolbar = Gtk::Box.new(:horizontal, 6)
        toolbar.margin_top = 12
        toolbar.margin_start = 12
        toolbar.margin_end = 12
        toolbar.append(@entry)
        toolbar.append(@spinner)
        append(toolbar)

        @list = Gtk::ListBox.new
        @list.signal_connect('row-activated') { |_list, row| play(row.index) }
        scroller = Gtk::ScrolledWindow.new
        scroller.vexpand = true
        scroller.margin_start = 12
        scroller.margin_end = 12
        scroller.margin_bottom = 12
        scroller.child = @list
        append(scroller)
      end

      def finish_search(generation, items)
        return false if @shutdown || generation != @generation

        @items = items
        clear
        items.each do |item|
          label = Gtk::Label.new([item.title, item.artist, item.album].compact.join(' — '))
          label.xalign = 0
          label.margin_top = 8
          label.margin_bottom = 8
          label.margin_start = 10
          label.margin_end = 10
          @list.append(label)
        end
        @spinner.stop
        false
      end

      def clear
        @list.remove(@list.first_child) while @list.first_child
      end
    end
  end
end
