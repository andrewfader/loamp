# frozen_string_literal: true

module Loamp
  module UI
    class PodcastView < Gtk::Box
      POSITION_WRITE_INTERVAL = 5

      def initialize(store, client, playlist, player)
        super(:vertical, 6)
        @store = store
        @client = client
        @playlist = playlist
        @player = player
        @handlers = []
        @callbacks = {}
        @episodes = []
        @generation = 0

        build_toolbar
        build_browser
        refresh
        watch_playback
      end

      def on_playlist_changed(&block) = (@callbacks[:playlist_changed] = block)
      def on_notify(&block) = (@callbacks[:notify] = block)

      def subscribe(url)
        address = url.to_s.strip
        return false if address.empty? || @shutdown

        generation = (@generation += 1)
        set_loading(true)
        Thread.new do
          feed = @client.fetch(address)
          GLib::Idle.add { finish_subscription(generation, feed) }
        rescue StandardError
          GLib::Idle.add { finish_subscription(generation, nil) }
        end
        true
      end

      def play_episode(index)
        episode = @episodes[index]
        return false unless episode&.playable?

        track = @playlist.append(episode.to_track)
        @playlist.set_current_track(@playlist.size - 1)
        @current_episode = episode
        @last_position_write = 0
        @callbacks[:playlist_changed]&.call
        @player.stop
        @player.play
        resume_when_ready(@store.position(episode.guid))
        track
      end

      def refresh
        @feeds = @store.feeds
        clear_list(@feed_list)
        @feeds.each { |feed| @feed_list.append(label_row(feed.title)) }
        show_feed(0) if @feeds.any?
      end

      def shutdown
        return if @shutdown

        @shutdown = true
        @generation += 1
        @handlers.each { |object, id| object.signal_handler_disconnect(id) }
        @handlers.clear
        clear_list(@feed_list)
        clear_list(@episode_list)
      end

      private

      def connect(object, signal, &)
        @handlers << [object, object.signal_connect(signal, &)]
      end

      def build_toolbar
        @url_entry = Gtk::Entry.new
        @url_entry.placeholder_text = 'Podcast RSS or Atom URL'
        @url_entry.hexpand = true
        connect(@url_entry, 'activate') { subscribe(@url_entry.text) }

        button = Gtk::Button.new(label: 'Subscribe')
        connect(button, 'clicked') { subscribe(@url_entry.text) }
        @spinner = Gtk::Spinner.new

        toolbar = Gtk::Box.new(:horizontal, 6)
        toolbar.margin_top = 12
        toolbar.margin_start = 12
        toolbar.margin_end = 12
        toolbar.append(@url_entry)
        toolbar.append(button)
        toolbar.append(@spinner)
        append(toolbar)
      end

      def build_browser
        @feed_list = Gtk::ListBox.new
        @feed_list.selection_mode = :single
        connect(@feed_list, 'row-selected') { |_list, row| show_feed(row&.index) }

        @episode_list = Gtk::ListBox.new
        @episode_list.selection_mode = :single
        connect(@episode_list, 'row-activated') { |_list, row| play_episode(row.index) }

        split = Gtk::Paned.new(:horizontal)
        split.position = 240
        split.start_child = scroller_for(@feed_list)
        split.end_child = scroller_for(@episode_list)
        split.vexpand = true
        split.margin_start = 12
        split.margin_end = 12
        split.margin_bottom = 12
        append(split)
      end

      def scroller_for(child)
        Gtk::ScrolledWindow.new.tap do |scroller|
          scroller.hscrollbar_policy = :never
          scroller.child = child
        end
      end

      def finish_subscription(generation, feed)
        return false if @shutdown || generation != @generation

        set_loading(false)
        if feed
          @store.subscribe(feed)
          @callbacks[:notify]&.call("Subscribed to #{feed.title}")
          refresh
        else
          @callbacks[:notify]&.call('Could not read that podcast feed')
        end
        false
      end

      def show_feed(index)
        feed = index && @feeds[index]
        @episodes = feed ? @store.episodes(feed.url) : []
        clear_list(@episode_list)
        @episodes.each do |episode|
          published = episode.published_at && Time.at(episode.published_at).strftime('%Y-%m-%d')
          @episode_list.append(label_row(episode.title, published))
        end
      end

      def label_row(primary, secondary = nil)
        box = Gtk::Box.new(:vertical, 2)
        box.margin_top = 7
        box.margin_bottom = 7
        box.margin_start = 9
        box.margin_end = 9
        box.append(Gtk::Label.new(primary.to_s).tap { |label| label.xalign = 0 })
        if secondary
          box.append(Gtk::Label.new(secondary).tap do |label|
            label.xalign = 0
            label.add_css_class('dim-label')
          end)
        end
        box
      end

      def watch_playback
        @player.on_position_changed do |position, _duration|
          next unless @current_episode && position - @last_position_write >= POSITION_WRITE_INTERVAL

          @store.remember_position(@current_episode.guid, position)
          @last_position_write = position
        end
      end

      def resume_when_ready(position)
        return unless position.positive?

        attempts = 0
        GLib::Timeout.add(100) do
          attempts += 1
          ready = @player.playing?
          @player.seek(position) if ready
          !ready && attempts < 50 && !@shutdown
        end
      end

      def set_loading(value)
        value ? @spinner.start : @spinner.stop
        @url_entry.sensitive = !value
      end

      def clear_list(list)
        list.remove(list.first_child) while list.first_child
      end
    end
  end
end
