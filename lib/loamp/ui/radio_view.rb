# frozen_string_literal: true

module Loamp
  module UI
    # Search and playback UI for internet radio. Directory requests happen on
    # a worker so a slow or offline server never stalls GTK or audio playback.
    class RadioView < Gtk::Box
      def initialize(browser, playlist, player, store: Radio::Store.new)
        super(:vertical, 0)
        @browser = browser
        @playlist = playlist
        @player = player
        @store = store
        @stations = []
        @handlers = []
        @callbacks = {}
        @generation = 0

        build_toolbar
        build_results
        load_popular
      end

      def on_playlist_changed(&block)
        @callbacks[:playlist_changed] = block
      end

      def on_notify(&block)
        @callbacks[:notify] = block
      end

      def search_for(query)
        text = query.to_s.strip
        return false if text.empty? || @shutdown

        @search_entry.text = text
        generation = (@generation += 1)
        set_loading(true)
        Thread.new do
          stations = @browser.search(text)
          GLib::Idle.add { finish_search(generation, stations) }
        rescue StandardError
          GLib::Idle.add { finish_search(generation, []) }
        end
        true
      end

      def visible_stations = @stations.dup

      def play_station(index)
        station = @stations[index]
        return false unless station

        track = @playlist.add_station(station)
        @playlist.set_current_track(@playlist.size - 1)
        @player.stop
        @player.play
        @callbacks[:playlist_changed]&.call
        @callbacks[:notify]&.call("Playing #{station.name}")
        @store.played(station)
        track
      end

      def show_favorites
        finish_search(@generation, @store.favorites)
      end

      def load_popular
        return false if @shutdown

        generation = (@generation += 1)
        set_loading(true, message: 'Loading popular stations…')
        Thread.new do
          stations = @browser.popular
          GLib::Idle.add { finish_search(generation, stations, empty: 'No popular stations available') }
        rescue StandardError
          GLib::Idle.add { finish_search(generation, [], empty: 'Could not load popular stations') }
        end
        true
      end

      def shutdown
        return if @shutdown

        @shutdown = true
        @generation += 1
        @handlers.each { |object, id| object.signal_handler_disconnect(id) }
        @handlers.clear
        clear_results
      end

      private

      def connect(object, signal, &)
        @handlers << [object, object.signal_connect(signal, &)]
      end

      def build_toolbar
        @search_entry = Gtk::SearchEntry.new
        @search_entry.placeholder_text = 'Search stations, cities, or genres'
        @search_entry.hexpand = true
        connect(@search_entry, 'activate') { search_for(@search_entry.text) }

        button = Gtk::Button.new(label: 'Search')
        connect(button, 'clicked') { search_for(@search_entry.text) }

        @spinner = Gtk::Spinner.new
        favorites = Gtk::Button.new(label: 'Favorites')
        connect(favorites, 'clicked') { show_favorites }
        @status = Gtk::Label.new('Search the worldwide Radio Browser directory')
        @status.xalign = 0
        @status.add_css_class('dim-label')

        toolbar = Gtk::Box.new(:horizontal, 6)
        toolbar.margin_top = 12
        toolbar.margin_bottom = 6
        toolbar.margin_start = 12
        toolbar.margin_end = 12
        toolbar.append(@search_entry)
        toolbar.append(button)
        toolbar.append(favorites)
        toolbar.append(@spinner)
        append(toolbar)
        append(@status)
        @status.margin_start = 12
        @status.margin_end = 12
        @status.margin_bottom = 6
      end

      def build_results
        @results = Gtk::ListBox.new
        @results.selection_mode = :single
        @results.add_css_class('boxed-list')
        connect(@results, 'row-activated') { |_list, row| play_station(row.index) }

        scroller = Gtk::ScrolledWindow.new
        scroller.hscrollbar_policy = :never
        scroller.vexpand = true
        scroller.margin_start = 12
        scroller.margin_end = 12
        scroller.margin_bottom = 12
        scroller.child = @results
        append(scroller)
      end

      def finish_search(generation, stations, empty: 'No stations found')
        return false if @shutdown || generation != @generation

        @stations = stations
        clear_rows
        stations.each { |station| @results.append(station_row(station)) }
        @status.text = result_message(stations.size, empty: empty)
        set_loading(false)
        false
      end

      def station_row(station)
        primary = Gtk::Label.new(station.name)
        primary.xalign = 0
        primary.hexpand = true
        primary.ellipsize = :end

        details = [station.country, station.language, station.codec,
                   ("#{station.bitrate} kbps" if station.bitrate.to_i.positive?)].compact
        secondary = Gtk::Label.new(details.reject { |value| value.to_s.empty? }.join(' · '))
        secondary.xalign = 0
        secondary.add_css_class('dim-label')
        secondary.ellipsize = :end

        details_box = Gtk::Box.new(:vertical, 2)
        details_box.hexpand = true
        details_box.margin_top = 8
        details_box.margin_bottom = 8
        details_box.margin_start = 10
        details_box.margin_end = 10
        details_box.append(primary)
        details_box.append(secondary)
        favorite = Gtk::Button.new(label: @store.favorite?(station) ? '★' : '☆')
        connect(favorite, 'clicked') do
          @store.favorite?(station) ? @store.unfavorite(station) : @store.favorite(station)
          favorite.label = @store.favorite?(station) ? '★' : '☆'
        end
        row = Gtk::Box.new(:horizontal, 6)
        row.append(details_box)
        row.append(favorite)
        row
      end

      def clear_results
        @stations = []
        clear_rows
      end

      def clear_rows
        @results.remove(@results.first_child) while @results.first_child
      end

      def set_loading(loading, message: 'Searching…')
        loading ? @spinner.start : @spinner.stop
        @search_entry.sensitive = !loading
        @status.text = message if loading
      end

      def result_message(count, empty: 'No stations found')
        return empty if count.zero?

        count == 1 ? '1 station · double-click to play' : "#{count} stations · double-click to play"
      end
    end
  end
end
