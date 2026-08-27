# frozen_string_literal: true

module Loamp
  module UI
    # Podcast subscriptions plus a browseable directory.
    #
    # Opening the page loads top charts so the panes are never a blank
    # "paste a URL" void. Search hits Apple's podcast directory; activating a
    # result subscribes and shows episodes. The RSS field stays for power users.
    class PodcastView < Gtk::Box
      POSITION_WRITE_INTERVAL = 5

      def initialize(store, client, playlist, player, directory: Podcast::Directory.new)
        super(:vertical, 6)
        @store = store
        @client = client
        @directory = directory
        @playlist = playlist
        @player = player
        @handlers = []
        @callbacks = {}
        @episodes = []
        @listings = []
        @mode = :discover
        @generation = 0

        build_toolbar
        build_browser
        refresh
        load_popular
        watch_playback
      end

      def on_playlist_changed(&block) = (@callbacks[:playlist_changed] = block)
      def on_notify(&block) = (@callbacks[:notify] = block)

      def subscribe(url)
        address = url.to_s.strip
        return false if address.empty? || @shutdown

        generation = (@generation += 1)
        set_loading(true, message: 'Fetching feed…')
        Thread.new do
          feed = @client.fetch(address)
          GLib::Idle.add { finish_subscription(generation, feed) }
        rescue StandardError
          GLib::Idle.add { finish_subscription(generation, nil) }
        end
        true
      end

      def search_for(query)
        text = query.to_s.strip
        return false if text.empty? || @shutdown

        @search_entry.text = text
        generation = (@generation += 1)
        set_loading(true, message: 'Searching podcasts…')
        Thread.new do
          listings = @directory.search(text)
          GLib::Idle.add { finish_directory(generation, listings, empty: 'No podcasts matched') }
        rescue StandardError
          GLib::Idle.add { finish_directory(generation, [], empty: 'Could not search podcasts') }
        end
        true
      end

      def load_popular
        return false if @shutdown

        generation = (@generation += 1)
        set_loading(true, message: 'Loading top podcasts…')
        Thread.new do
          listings = @directory.popular
          GLib::Idle.add do
            finish_directory(generation, listings, empty: 'No top podcasts available')
          end
        rescue StandardError
          GLib::Idle.add do
            finish_directory(generation, [], empty: 'Could not load top podcasts')
          end
        end
        true
      end

      def show_subscriptions
        @mode = :subscriptions
        refresh
        @status.text = if @feeds.empty?
                         'No subscriptions yet — browse Top Charts or search by name'
                       else
                         "#{@feeds.size} subscription#{'s' unless @feeds.size == 1}"
                       end
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
        return unless @mode == :subscriptions

        clear_list(@feed_list)
        @feeds.each { |feed| @feed_list.append(subscription_row(feed)) }
        show_feed(0) if @feeds.any?
        clear_episodes if @feeds.empty?
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
        @search_entry = Gtk::SearchEntry.new
        @search_entry.placeholder_text = 'Search podcasts by name'
        @search_entry.hexpand = true
        connect(@search_entry, 'activate') { search_for(@search_entry.text) }

        search = Gtk::Button.new(label: 'Search')
        connect(search, 'clicked') { search_for(@search_entry.text) }

        top = Gtk::Button.new(label: 'Top Charts')
        connect(top, 'clicked') { load_popular }

        mine = Gtk::Button.new(label: 'My Shows')
        connect(mine, 'clicked') { show_subscriptions }

        @url_entry = Gtk::Entry.new
        @url_entry.placeholder_text = 'Or paste an RSS URL'
        @url_entry.width_chars = 18
        connect(@url_entry, 'activate') { subscribe(@url_entry.text) }

        subscribe = Gtk::Button.new(label: 'Subscribe')
        connect(subscribe, 'clicked') { subscribe(@url_entry.text) }

        @spinner = Gtk::Spinner.new
        @status = Gtk::Label.new('Browse top podcasts, or search by name')
        @status.xalign = 0
        @status.add_css_class('dim-label')

        toolbar = Gtk::Box.new(:horizontal, 6)
        toolbar.margin_top = 12
        toolbar.margin_start = 12
        toolbar.margin_end = 12
        toolbar.append(@search_entry)
        toolbar.append(search)
        toolbar.append(top)
        toolbar.append(mine)
        toolbar.append(@url_entry)
        toolbar.append(subscribe)
        toolbar.append(@spinner)
        append(toolbar)
        append(@status)
        @status.margin_start = 12
        @status.margin_end = 12
        @status.margin_bottom = 6
      end

      def build_browser
        @feed_list = Gtk::ListBox.new
        @feed_list.selection_mode = :single
        connect(@feed_list, 'row-selected') { |_list, row| select_left_row(row&.index) }
        connect(@feed_list, 'row-activated') { |_list, row| activate_left_row(row&.index) }

        @episode_list = Gtk::ListBox.new
        @episode_list.selection_mode = :single
        connect(@episode_list, 'row-activated') { |_list, row| play_episode(row.index) }

        split = Gtk::Paned.new(:horizontal)
        split.position = 280
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
          @mode = :subscriptions
          refresh
          select_feed_by_url(feed.url)
        else
          @callbacks[:notify]&.call('Could not read that podcast feed')
        end
        false
      end

      def finish_directory(generation, listings, empty:)
        return false if @shutdown || generation != @generation

        @mode = :discover
        @listings = listings
        @feeds = @store.feeds
        clear_list(@feed_list)
        clear_episodes
        listings.each { |listing| @feed_list.append(listing_row(listing)) }
        @status.text = directory_message(listings.size, empty: empty)
        set_loading(false)
        false
      end

      def directory_message(count, empty:)
        return empty if count.zero?

        verb = count == 1 ? 'show' : 'shows'
        "#{count} #{verb} · double-click to subscribe"
      end

      def select_left_row(index)
        return if index.nil?

        if @mode == :discover
          preview_listing(@listings[index])
        else
          show_feed(index)
        end
      end

      def activate_left_row(index)
        return if index.nil?

        if @mode == :discover
          listing = @listings[index]
          subscribe(listing.feed_url) if listing
        else
          play_episode(0) if @episodes.any?
        end
      end

      def preview_listing(listing)
        clear_episodes
        return unless listing

        @episode_list.append(label_row(listing.title, listing.artist))
        details = [listing.genre, 'Double-click the show to subscribe'].compact.reject(&:empty?)
        @episode_list.append(label_row(details.join(' · '))) if details.any?
      end

      def show_feed(index)
        feed = index && @feeds[index]
        @episodes = feed ? @store.episodes(feed.url) : []
        clear_list(@episode_list)
        @episodes.each do |episode|
          published = episode.published_at && Time.at(episode.published_at).strftime('%Y-%m-%d')
          progress = episode_progress(episode)
          secondary = [published, progress].compact.join(' · ')
          @episode_list.append(label_row(episode.title, secondary))
        end
      end

      def episode_progress(episode)
        position = @store.position(episode.guid)
        return nil unless position.positive? && episode.duration.to_f.positive?

        percent = ((position / episode.duration) * 100).round
        "#{percent}% played"
      end

      def select_feed_by_url(url)
        index = @feeds.index { |feed| feed.url == url }
        return unless index

        @feed_list.select_row(@feed_list.get_row_at_index(index))
        show_feed(index)
      end

      def listing_row(listing)
        label_row(listing.title, [listing.artist, listing.genre].reject(&:empty?).join(' · '))
      end

      def subscription_row(feed)
        box = label_row(feed.title, "#{feed.episodes.size} episodes")
        remove = Gtk::Button.new
        remove.icon_name = 'list-remove-symbolic'
        remove.tooltip_text = 'Unsubscribe'
        remove.valign = Gtk::Align::CENTER
        remove.add_css_class('flat')
        connect(remove, 'clicked') { unsubscribe(feed.url) }

        row = Gtk::Box.new(:horizontal, 6)
        box.hexpand = true
        row.append(box)
        row.append(remove)
        row
      end

      def unsubscribe(url)
        return unless @store.unsubscribe(url)

        @callbacks[:notify]&.call('Unsubscribed')
        refresh
      end

      def label_row(primary, secondary = nil)
        box = Gtk::Box.new(:vertical, 2)
        box.margin_top = 7
        box.margin_bottom = 7
        box.margin_start = 9
        box.margin_end = 9
        box.append(Gtk::Label.new(primary.to_s).tap do |label|
          label.xalign = 0
          label.ellipsize = :end
        end)
        if secondary
          box.append(Gtk::Label.new(secondary).tap do |label|
            label.xalign = 0
            label.add_css_class('dim-label')
            label.ellipsize = :end
          end)
        end
        box
      end

      def watch_playback
        @player.on_position_changed do |position, _duration|
          next if @shutdown
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

      def set_loading(value, message: nil)
        value ? @spinner.start : @spinner.stop
        @search_entry.sensitive = !value
        @url_entry.sensitive = !value
        @status.text = message if value && message
      end

      def clear_episodes
        @episodes = []
        clear_list(@episode_list)
      end

      def clear_list(list)
        list.remove(list.first_child) while list.first_child
      end
    end
  end
end
