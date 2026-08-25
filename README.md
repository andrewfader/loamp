# LOAMP - Linux Open Audio Music Player

A music player built with Ruby, GTK4 and libadwaita for Linux.

## Features

- Native libadwaita interface: adaptive split view, header bar, toasts, and
  automatic light/dark following the desktop preference
- GStreamer playback with accurate seeking, real position reporting and
  gapless track transitions, ReplayGain, a ten-band preset EQ, and optional
  two-pipeline crossfade
- A projectM-style visualization page: uses the `projectm` GStreamer element
  when installed and automatically falls back to Goom
- MPRIS2 desktop integration: media keys, the GNOME Shell media widget and
  `playerctl` all drive the player, with cover art in the notification
- Album art from embedded tags, from cover art beside the file, or fetched
  from the Cover Art Archive when the file has neither
- Broad format support (MP3, FLAC, Ogg Vorbis, Opus, M4A, WAV and more) with
  full tag reading via TagLib
- An indexed local library: folders are scanned on a background thread into a
  SQLite database with full-text search, so browsing and searching stay instant
- Virtualised playlist that stays responsive at any size
- Playlist management with shuffle and repeat modes
- Standard M3U/M3U8 playlist import and export
- Volume with a perceptual (cubic) curve, and mute
- Internet-radio discovery through Radio Browser, with live ICY song-title
  updates, favorites, history, and directory-server failover
- Synced embedded/sidecar/LRCLIB lyrics, podcasts with resume and downloads,
  Subsonic/Navidrome/Jellyfin servers, and durable ListenBrainz/Last.fm scrobbling
- Similar-artist discovery graph and an endless, steerable local-library radio

## Requirements

- Ruby 3.2+
- GTK4 and libadwaita development libraries
- GStreamer 1.0 with the good/bad/ugly plugin sets
- TagLib
- SQLite with FTS5, for the library index and the podcast and graph stores.
  The packaged `sqlite3` gem ships one, so nothing extra is needed.

The visualizer needs `gtk4paintablesink` and at least one visualization plugin.
LOAMP prefers projectM, then `goom`, then `goom2k1`; the standard GStreamer
good/bad packages provide the fallback on most distributions.

## Installation

### Install system dependencies (Ubuntu/Debian)
```bash
sudo apt-get update
sudo apt-get install ruby ruby-dev libgtk-4-dev libadwaita-1-dev libtag1-dev \
  libgstreamer1.0-dev gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
  gstreamer1.0-plugins-ugly build-essential pkg-config
```

`make install` runs `install.sh`, which does the same thing and adds the
PipeWire GStreamer plugin.

### Install Ruby gems
```bash
bundle install
```

`make deps` checks that everything the player needs is actually present.

### Desktop entry (optional)
```bash
make desktop
```

Installs `loamp.desktop` into `~/.local/share/applications/`, pointed at the
current checkout, so LOAMP appears in the application launcher.

## Usage

Run the music player:
```bash
ruby loamp.rb
```

### The pages

A view switcher along the bottom of the window moves between pages. Now
Playing, Lyrics and Visualizer are always there; the rest appear when the
thing behind them is available.

| Page | What it is | Appears when |
|------|------------|--------------|
| Now Playing | Album art, track details and the queue | always |
| Lyrics | Synced lyrics from tags, a sidecar `.lrc`, or LRCLIB | always |
| Visualizer | projectM or Goom, rendered into the window | always |
| Library | The indexed local collection, with search | the library database opened |
| Radio | Radio Browser stations, favorites and history | a directory server answered |
| Podcasts | Subscriptions, episodes, resume points and downloads | the podcast store opened |
| Streaming | Search across connected Subsonic/Jellyfin servers | a provider is configured |
| Discover | The similar-artist graph and steerable radio | a similarity service is reachable |

### Building the library

The Library page starts empty. **Add Folder** indexes a music folder in the
background — the UI stays live while it runs, and the page fills in as tracks
land. Folders are remembered, so **Rescan Library** in the main menu picks up
anything added or changed since. Overlapping folders are deduplicated rather
than indexed twice.

### Keyboard shortcuts

| Key | Action |
|-----|--------|
| <kbd>Space</kbd> | Play / pause |
| <kbd>←</kbd> / <kbd>→</kbd> | Seek back / forward 10 seconds |
| <kbd>Ctrl</kbd>+<kbd>←</kbd> / <kbd>Ctrl</kbd>+<kbd>→</kbd> | Previous / next track |
| <kbd>↑</kbd> / <kbd>↓</kbd> | Volume up / down |
| <kbd>M</kbd> | Toggle mute |
| <kbd>Delete</kbd> (in queue) | Remove selected track |
| <kbd>Alt</kbd>+<kbd>↑</kbd> / <kbd>Alt</kbd>+<kbd>↓</kbd> (in queue) | Reorder selected track |

Right-click a queue entry to play it next, move it, or remove it.

Media keys work too, through MPRIS — see below.

### Radio, Discover, Podcasts and the Visualizer

The Radio page opens with popular stations from the public Radio Browser
directory. Search by station, place, or genre; double-click a result to add it
to the queue and start its live stream.

The Similar Artists item in the main menu opens Discover, LOAMP's live artist
graph and Pandora-style local-library radio. Enter an artist to expand related
artists, click a node to explore it, or double-click one to start a station.
ListenBrainz supplies the default graph. Set `LOAMP_LASTFM_API_KEY` to enable
Last.fm as a fallback for artists that cannot be resolved to a MusicBrainz ID.

The Podcasts page takes an RSS or Atom feed URL and subscribes to it. Episodes
remember where you stopped, and can be downloaded for offline listening.

The Visualizer page is always present. Start it while audio is playing; its
button tooltip shows the selected backend. Playback continues normally when
no supported visualization plugin is installed.

### Optional services

LOAMP discovers optional accounts from environment variables:

```bash
LOAMP_SUBSONIC_URL=https://music.example \
LOAMP_SUBSONIC_USER=me LOAMP_SUBSONIC_PASSWORD=secret ruby loamp.rb

LOAMP_JELLYFIN_URL=https://media.example \
LOAMP_JELLYFIN_USER_ID=user-id LOAMP_JELLYFIN_TOKEN=token ruby loamp.rb

LOAMP_LISTENBRAINZ_TOKEN=token ruby loamp.rb
LOAMP_LASTFM_API_KEY=key LOAMP_LASTFM_SECRET=secret \
LOAMP_LASTFM_SESSION_KEY=session ruby loamp.rb
```

Credentials stay in the process environment and are not written into the
library database. Playback processing choices are available from the main
menu and persist between launches; changing crossfade takes effect on the next
launch because it selects a different GStreamer engine.

### Controlling it from the desktop

LOAMP registers itself on the session bus as `org.mpris.MediaPlayer2.loamp`,
so the standard media keys and any MPRIS client work with it:

```bash
playerctl -p loamp play-pause
playerctl -p loamp metadata
```

Without a session bus the player runs exactly as before, just without desktop
integration.

### Cover art from the network

A track with no embedded artwork and no cover image beside it is looked up on
MusicBrainz and the Cover Art Archive, on a background thread — playback never
waits on it. Files tagged by Picard skip the search, since they already say
which release they belong to.

Both services are free and need no account. MusicBrainz allows about one
request a second and asks that callers identify themselves, so LOAMP sends a
User-Agent naming the application and a contact address. Point it at your own
if you are packaging or forking it:

```bash
LOAMP_CONTACT='https://example.org/my-fork' ruby loamp.rb
```

Covers are cached under `$XDG_CACHE_HOME/loamp/art/`, keyed by album, and a
lookup that comes back empty is remembered for a month so the same album is not
searched for on every play. Delete the cache directory to start over.

### Where LOAMP keeps its files

Everything follows the XDG base directory spec, so `XDG_DATA_HOME`,
`XDG_CONFIG_HOME` and `XDG_CACHE_HOME` all move it. Anything under the cache
root is safe to delete; it is rebuilt on demand.

| Path | Contents |
|------|----------|
| `$XDG_DATA_HOME/loamp/library.db` | The indexed local collection |
| `$XDG_DATA_HOME/loamp/podcasts.db` | Subscriptions, episodes, resume points |
| `$XDG_DATA_HOME/loamp/radio.json` | Station favorites and history |
| `$XDG_CONFIG_HOME/loamp/playback.json` | ReplayGain, EQ and crossfade choices |
| `$XDG_CACHE_HOME/loamp/art/` | Downloaded cover art, keyed by album |
| `$XDG_CACHE_HOME/loamp/lyrics/` | Lyrics fetched from LRCLIB |
| `$XDG_CACHE_HOME/loamp/radio-graph.db` | The similar-artist graph |
| `$XDG_CACHE_HOME/loamp/scrobbles.json` | Scrobbles waiting to be submitted |

Scrobbles are queued on disk so a listen survives a network outage or a
crash, and are replayed on the next successful submission.

## Project Structure

```
loamp/
├── loamp.rb                  # Main application entry point
├── lib/
│   ├── loamp.rb              # Main module
│   └── loamp/
│       ├── adw.rb              # libadwaita bindings via GObject Introspection
│       ├── application.rb      # Main application class
│       ├── audio_engine.rb     # GStreamer playbin3 pipeline
│       ├── crossfade_engine.rb # Two-pipeline engine for overlapping tracks
│       ├── playback_settings.rb# ReplayGain/EQ/crossfade choices, persisted
│       ├── player.rb           # Play order, repeat/shuffle, gapless hand-off
│       ├── playlist.rb         # Playlist management
│       ├── track.rb            # Track model
│       ├── metadata.rb         # Tag values
│       ├── metadata/reader.rb  # TagLib reading
│       ├── artwork.rb          # Cover art resolution
│       ├── art_cache.rb        # Cover art as a file:// URL, cached on disk
│       ├── file_uri.rb         # Path <-> file:// URI conversion
│       ├── visualizer.rb       # Visualization backend selection
│       ├── musicbrainz_artist.rb # Artist name -> MusicBrainz ID
│       ├── listenbrainz.rb     # ListenBrainz similarity and scrobbling
│       ├── lastfm.rb           # Last.fm similarity and scrobbling
│       ├── scrobbler.rb        # Durable scrobble queue over both services
│       ├── cover_art/          # MusicBrainz + Cover Art Archive lookup
│       │   ├── fetcher.rb      #   Background resolution, miss-aware
│       │   ├── musicbrainz.rb  #   Release lookup
│       │   ├── archive.rb      #   Image download
│       │   └── miss_log.rb     #   Remembered empty results
│       ├── http/               # Shared HTTP client and rate limiting
│       ├── library.rb          # SQLite-backed local index
│       ├── library/
│       │   ├── scanner.rb      #   Background folder walk and indexing
│       │   ├── schema.rb       #   Tables, FTS5 index, migrations
│       │   └── search.rb       #   Query parsing and ranking
│       ├── lyrics/             # Embedded, sidecar and LRCLIB lyrics
│       │   ├── resolver.rb     #   Source preference and fallback
│       │   ├── lrclib.rb       #   LRCLIB client
│       │   ├── lrc_parser.rb   #   .lrc timing parser
│       │   ├── document.rb     #   Parsed lyrics with timings
│       │   └── cache.rb        #   On-disk cache
│       ├── podcast/            # Feeds, episodes, downloads
│       │   ├── client.rb       #   Feed fetching
│       │   ├── parser.rb       #   RSS/Atom parsing
│       │   ├── feed.rb         #   Feed and episode models
│       │   ├── opml.rb         #   OPML subscription lists
│       │   ├── store.rb        #   Subscriptions and resume points
│       │   └── downloader.rb   #   Offline episode downloads
│       ├── provider.rb         # Streaming provider interface
│       ├── provider/
│       │   ├── subsonic.rb     #   Subsonic/Navidrome
│       │   └── jellyfin.rb     #   Jellyfin
│       ├── radio/              # Internet radio and the similarity graph
│       │   ├── browser.rb      #   Radio Browser directory, with failover
│       │   ├── station.rb      #   Station model
│       │   ├── store.rb        #   Favorites and history
│       │   ├── station_queue.rb#   Live stream queueing and ICY titles
│       │   ├── similarity.rb   #   Similar artists from ListenBrainz/Last.fm
│       │   ├── graph_store.rb  #   Cached graph
│       │   └── graph_layout.rb #   Force-directed layout
│       ├── mpris.rb            # MPRIS2 interface definitions
│       ├── mpris/
│       │   ├── adapter.rb      #   MPRIS semantics over the player
│       │   ├── service.rb      #   D-Bus export via GIO
│       │   └── variant.rb      #   Ruby values as GVariants
│       └── ui/
│           ├── style.rb              # Colour scheme and CSS
│           ├── main_window.rb        # Main window and view stack
│           ├── secondary_views.rb    # Optional pages, built when available
│           ├── player_controls.rb    # Player controls widget
│           ├── playback_menu.rb      # ReplayGain, EQ and crossfade menu
│           ├── playback_observers.rb # Player state -> widget updates
│           ├── keyboard_shortcuts.rb # Key bindings
│           ├── playlist_view.rb      # Virtualised playlist (Gtk::ColumnView)
│           ├── track_info.rb         # Now playing pane with album art
│           ├── library_view.rb       # Library browsing and search
│           ├── library_name_factory.rb # Library list item rendering
│           ├── lyrics_view.rb        # Synced lyrics page
│           ├── visualizer_view.rb    # Visualization page
│           ├── radio_view.rb         # Radio search, favorites, history
│           ├── podcast_view.rb       # Subscriptions and episodes
│           ├── provider_view.rb      # Streaming server search
│           └── graph_view.rb         # Similar-artist graph and radio
├── assets/                   # Icons, images and stylesheet
├── Gemfile                   # Ruby dependencies
├── PLAN.md                   # Running record of in-flight work
└── README.md                 # This file
```

## Testing

LOAMP includes a comprehensive test suite with unit tests, integration tests, and code quality checks.

### Running Tests

#### Quick Test Run
```bash
# Run all tests
make test

# Or using the test runner script
./test_runner.sh
```

#### Individual Test Suites
```bash
# Unit tests only
bundle exec rspec

# Integration tests only  
ruby spec/integration_test.rb

# Code quality check
bundle exec rubocop

# Tests with coverage
make coverage
```

#### Test Structure
```
spec/
├── spec_helper.rb              # Test configuration
├── support/                    # Test helpers and utilities
│   ├── test_helpers.rb         #   Shared test helpers
│   ├── gtk_helper.rb           #   GTK init, skipping when there is no display
│   ├── stub_http_server.rb     #   Local HTTP server for network-facing specs
│   ├── audio_fixtures.rb       #   Generated audio files
│   └── screenshot_helper.rb    #   Window captures for UI specs
├── factories/                  # Test data factories
│   ├── track_factory.rb        #   Track test data
│   └── playlist_factory.rb     #   Playlist test data
├── loamp/                      # Unit tests, mirroring lib/loamp/
│   ├── player_spec.rb, playlist_spec.rb, track_spec.rb, …
│   ├── cover_art/, http/, library/, lyrics/, mpris/
│   ├── podcast/, provider/, radio/
│   └── ui/                     #   UI component tests
├── integration_test.rb         # Integration tests
├── real_audio_integration_spec.rb # Playback against generated audio files
└── loamp_spec.rb               # Module tests
```

Specs that reach the network talk to a local stub server, so the suite runs
offline. UI specs need a display and skip themselves without one; the MPRIS
specs do the same for the session bus. `xvfb-run -a dbus-run-session --
bundle exec rspec` runs everything on a headless machine. End-to-end UI specs
save window captures under a temporary directory; `LOAMP_SCREENSHOT_DIR`
puts them somewhere you can keep.

### Test Coverage

The test suite covers:
- **Core Logic**: Track metadata, playlist management, player state
- **Playback**: Engine state transitions, and real decoding of generated files
- **Library**: Scanning, schema migrations, and search ranking
- **Services**: Radio, podcasts, lyrics, streaming providers and scrobbling,
  each against a local stub HTTP server
- **Desktop Integration**: MPRIS adapter, D-Bus export and GVariant conversion
- **UI Components**: GTK widgets and user interactions
- **Integration**: End-to-end functionality testing
- **Error Handling**: Graceful failure scenarios
- **Edge Cases**: Boundary conditions and invalid inputs

### Continuous Integration

GitHub Actions runs RuboCop, the unit suite, the integration suite and a
coverage report on every push to `main` or `develop` and on every pull
request, against Ruby 3.2, 3.3, 3.4 and 4.0 on Ubuntu latest. Everything runs
under `xvfb-run` and `dbus-run-session`, so the display- and bus-dependent
specs execute rather than skip.

### Test Commands Reference

| Command | Description |
|---------|-------------|
| `make test` | Run all tests |
| `make coverage` | Run tests with coverage report |
| `make quality` | Run quality checks (rubocop + tests) |
| `make ci` | Run full CI suite |
| `bundle exec rspec` | Unit tests only |
| `ruby spec/integration_test.rb` | Integration tests only |
| `bundle exec rubocop` | Code style check |
| `./test_runner.sh` | Full test suite with colored output |

## License

MIT License
