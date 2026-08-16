# frozen_string_literal: true

module Loamp
  module UI
    # Construction and callback wiring for optional content sources.
    module SecondaryViews
      private

      def create_library_view
        return unless @library

        @library_view = LibraryView.new(@library, @playlist, @player, art_cache: @art_cache)
        wire_queue_view(@library_view)
      end

      def create_radio_view
        return unless @radio_browser

        @radio_view = RadioView.new(@radio_browser, @playlist, @player)
        wire_queue_view(@radio_view)
      end

      def create_podcast_view
        return unless @podcasts

        store, client = @podcasts
        @podcast_view = PodcastView.new(store, client, @playlist, @player)
        wire_queue_view(@podcast_view)
      end

      def create_provider_view
        return unless @providers&.any?

        @provider_view = ProviderView.new(@providers, @playlist, @player)
        wire_queue_view(@provider_view)
      end

      def create_graph_view
        return unless @radio_services

        similarity, graph = @radio_services
        @graph_store = graph
        @graph_view = GraphView.new(similarity)
        @graph_view.on_start_station { |artist, mbid| start_themed_station(artist, mbid) }
        @graph_view.on_feedback { |action| steer_station(action) }
        @graph_view.on_adventure_changed { |value| @station.adventure = value if @station }
        @graph_view.on_now_playing { discover_similar(@player.current_track) }
        @track_info.on_discover { |track| discover_similar(track) }
      end

      def discover_similar(track)
        artist = track&.artist.to_s.strip
        return notify('Nothing is playing') if artist.empty?
        return unless @graph_view

        @graph_view.seed(artist, mbid: track.musicbrainz_artist_id, local: true)
        show_view('discovery')
      end

      def show_discovery
        track = @player.current_track
        if track&.artist.to_s.strip.empty?
          show_view('discovery')
        else
          discover_similar(track)
        end
      end

      def start_themed_station(artist, mbid)
        seed = mbid || artist
        @station = Radio::StationQueue.new(library: @library, graph: @graph_store, seed: seed)
        @playlist.clear
        10.times.filter_map { @station.next_track }.each { |track| @playlist.append(track) }
        @playlist.set_current_track(0)
        @playlist_view.refresh
        @player.stop
        @player.play
        notify("Started a station from #{artist}")
      end

      def steer_station(action)
        track = @player.current_track
        return unless @station && track

        case action
        when :up then @station.thumbs_up(track)
        when :down then @station.thumbs_down(track)
        when :ban then @station.ban_artist(track.artist)
        end
        notify('Station preference saved')
      end

      def refill_station_queue
        return unless @station

        added = []
        while @playlist.size - @playlist.current_index < 6
          track = @station.next_track
          break unless track

          added << @playlist.append(track)
        end
        @playlist_view.refresh if added.any?
      end

      def wire_queue_view(view)
        view.on_playlist_changed { @playlist_view.refresh }
        view.on_notify { |message| notify(message) }
      end

      def switchable_views?
        @library_view || @radio_view || @podcast_view || @provider_view || @graph_view
      end
    end
  end
end
