# frozen_string_literal: true

module Loamp
  # Main application class that initializes and runs the music player
  class Application
    APPLICATION_ID = 'org.loamp.player'

    # How often the player is pumped. Fast enough for a smooth progress bar,
    # slow enough to stay out of the way.
    TICK_INTERVAL_MS = 250

    attr_reader :player, :playlist, :mpris, :library, :art_cache, :radio_browser,
                :lyrics_cache, :podcast_store

    def initialize(library_path: Library.default_path)
      @playlist = Playlist.new
      @playback_settings = PlaybackSettings.new
      @player = Player.new(@playlist, engine: build_audio_engine)
      # One cache, shared: art fetched for the now-playing pane is the same art
      # the desktop widget shows, and neither should fetch it twice.
      @art_cache = ArtCache.new
      @mpris = Mpris::Service.new(Mpris::Adapter.new(@player, art_cache: @art_cache))
      @library = open_library(library_path)
      @radio_browser = Radio::Browser.new
      @lyrics_cache = Lyrics::Cache.new
      @podcast_store = open_podcast_store
      @podcast_client = Podcast::Client.new
      @providers = build_providers
      @scrobbler = build_scrobbler
      @graph_store = Radio::GraphStore.new
      @similarity = build_similarity
    end

    def run
      app = build_application

      app.signal_connect('activate') do
        @main_window = UI::MainWindow.new(@player, @playlist, library: @library,
                                                              radio_browser: @radio_browser,
                                                              podcasts: podcast_services,
                                                              providers: @providers,
                                                              radio_services: radio_services,
                                                              art_cache: @art_cache)
        @main_window.application = app
        @main_window.present
        @main_window.auto_scan_library
        start_mpris(app)
        start_artwork_lookups
        start_lyrics_lookups
        start_scrobbling
        start_playback_clock
      end

      app.signal_connect('shutdown') do
        @main_window&.shutdown
        @art_cache.shutdown
        @lyrics_cache.shutdown
        @mpris.stop
        @library&.close
        @podcast_store&.close
        @scrobbler.shutdown
        @graph_store.close
      end

      app.run([])
    end

    # Media keys, the GNOME Shell media widget and playerctl all arrive
    # through here. Failing to reach the bus is not fatal — the player simply
    # runs without desktop integration.
    def start_mpris(app)
      adapter = @mpris.adapter
      adapter.on_raise { @main_window&.present }
      adapter.on_quit { app.quit }

      return unless @mpris.start

      @player.on_track_changed { @mpris.track_changed }
      @player.on_state_changed { @mpris.state_changed }
      @player.on_volume_changed { @mpris.volume_changed }
      @player.on_seeked { |position| @mpris.seeked(position) }
    end

    # Cover art for a track that carries none and has none beside it is looked
    # for on the network, on a worker thread. It arrives late or not at all,
    # which is why both the pane and the desktop widget are told again rather
    # than asked to wait.
    def start_artwork_lookups
      @player.on_track_changed do |track|
        @art_cache.fetch_remote(track) do |url|
          next unless url

          @main_window&.artwork_arrived(track, url)
          @mpris.track_changed
        end
      end
    end

    def start_lyrics_lookups
      @player.on_track_changed do |track|
        local = @lyrics_cache.for(track)
        @main_window&.show_lyrics(track, local)
        next if local

        @lyrics_cache.fetch_remote(track) do |document|
          @main_window&.show_lyrics(track, document)
        end
      end
    end

    def start_scrobbling
      @player.on_track_changed { |track| @scrobbler.track_started(track) }
    end

    private

    def build_audio_engine
      seconds = @playback_settings.crossfade_seconds
      return AudioEngine.new(settings: @playback_settings) unless seconds.positive?

      CrossfadeEngine.new(crossfade_seconds: seconds, settings: @playback_settings)
    rescue StandardError => e
      warn "Crossfade unavailable (#{e.message}); using the standard audio engine"
      @playback_settings.crossfade_seconds = 0
      AudioEngine.new(settings: @playback_settings)
    end

    # A library that cannot be opened — a read-only home directory, a corrupt
    # file — costs the browse pane, not the player.
    def open_library(library_path)
      Library.new(path: library_path)
    rescue StandardError => e
      warn "Library unavailable: #{e.message}"
      nil
    end

    def open_podcast_store
      Podcast::Store.new
    rescue StandardError => e
      warn "Podcast store unavailable: #{e.message}"
      nil
    end

    def podcast_services
      [@podcast_store, @podcast_client] if @podcast_store
    end

    def radio_services = [@similarity, @graph_store]

    def build_providers
      Provider::Registry.new.tap do |registry|
        add_subsonic_provider(registry)
        add_jellyfin_provider(registry)
      end
    end

    def build_scrobbler
      services = []
      token = ENV.fetch('LOAMP_LISTENBRAINZ_TOKEN', nil)
      services << ListenBrainz.new(token: token) if token
      key = ENV.fetch('LOAMP_LASTFM_API_KEY', nil)
      if key
        services << Lastfm.new(api_key: key, secret: ENV.fetch('LOAMP_LASTFM_SECRET', nil),
                               session_key: ENV.fetch('LOAMP_LASTFM_SESSION_KEY', nil))
      end
      Scrobbler.new(services)
    end

    def build_similarity
      key = ENV.fetch('LOAMP_LASTFM_API_KEY', nil)
      lastfm = Lastfm.new(api_key: key) if key
      Radio::Similarity.new(graph: @graph_store, lastfm: lastfm, library: @library)
    end

    def add_subsonic_provider(registry)
      url = ENV.fetch('LOAMP_SUBSONIC_URL', nil)
      return unless url

      registry.register(:subsonic, Provider::Subsonic.new(
                                     url: url, username: ENV.fetch('LOAMP_SUBSONIC_USER', nil),
                                     password: ENV.fetch('LOAMP_SUBSONIC_PASSWORD', nil)
                                   ))
    end

    def add_jellyfin_provider(registry)
      url = ENV.fetch('LOAMP_JELLYFIN_URL', nil)
      return unless url

      registry.register(:jellyfin, Provider::Jellyfin.new(
                                     url: url, user_id: ENV.fetch('LOAMP_JELLYFIN_USER_ID', nil),
                                     token: ENV.fetch('LOAMP_JELLYFIN_TOKEN', nil)
                                   ))
    end

    # Adw::Application initializes libadwaita and applies the Adwaita
    # stylesheet, which a plain Gtk::Application would not.
    def build_application
      Adw::Application.new(APPLICATION_ID, :flags_none).tap do |app|
        register_quit_action(app)
      end
    end

    # The main menu refers to app.quit, so the action has to exist.
    def register_quit_action(app)
      action = Gio::SimpleAction.new('quit')
      action.signal_connect('activate') { app.quit }
      app.add_action(action)
      app.set_accels_for_action('app.quit', ['<Control>q'])
    end

    # The engine posts everything it knows on the GStreamer bus. This timer is
    # what carries those messages into the GTK main loop.
    def start_playback_clock
      GLib::Timeout.add(TICK_INTERVAL_MS, &playback_clock)
    end

    def playback_clock
      lambda do
        @player.tick
        @scrobbler.tick(@player.position, @player.duration) if @player.playing?
        true # keep the timer alive
      end
    end
  end
end
