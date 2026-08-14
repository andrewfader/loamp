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
- Virtualised playlist that stays responsive at any size
- Playlist management with shuffle and repeat modes
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

### Install Ruby gems
```bash
bundle install
```

## Usage

Run the music player:
```bash
ruby loamp.rb
```

The Radio page opens with popular stations from the public Radio Browser
directory. Search by station, place, or genre; double-click a result to add it
to the queue and start its live stream.

The Similar Artists item in the main menu opens Discover, LOAMP's live artist
graph and Pandora-style local-library radio. Enter an artist to expand related
artists, click a node to explore it, or double-click one to start a station.
ListenBrainz supplies the default graph. Set `LOAMP_LASTFM_API_KEY` to enable
Last.fm as a fallback for artists that cannot be resolved to a MusicBrainz ID.

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

## Project Structure

```
loamp/
├── loamp.rb              # Main application entry point
├── lib/
│   ├── loamp/
│   │   ├── adw.rb          # libadwaita bindings via GObject Introspection
│   │   ├── application.rb  # Main application class
│   │   ├── audio_engine.rb # GStreamer playbin3 pipeline
│   │   ├── player.rb       # Play order, repeat/shuffle, gapless hand-off
│   │   ├── playlist.rb     # Playlist management
│   │   ├── track.rb        # Track model
│   │   ├── metadata.rb     # Tag values
│   │   ├── metadata/
│   │   │   └── reader.rb   # TagLib reading
│   │   ├── artwork.rb      # Cover art resolution
│   │   ├── art_cache.rb    # Cover art as a file:// URL, cached on disk
│   │   ├── file_uri.rb     # Path <-> file:// URI conversion
│   │   ├── mpris.rb        # MPRIS2 interface definitions
│   │   ├── mpris/
│   │   │   ├── adapter.rb  # MPRIS semantics over the player
│   │   │   ├── service.rb  # D-Bus export via GIO
│   │   │   └── variant.rb  # Ruby values as GVariants
│   │   └── ui/
│   │       ├── style.rb           # Colour scheme and CSS
│   │       ├── main_window.rb     # Main window
│   │       ├── player_controls.rb # Player controls widget
│   │       ├── playlist_view.rb   # Virtualised playlist (Gtk::ColumnView)
│   │       └── track_info.rb      # Now playing pane with album art
│   └── loamp.rb          # Main module
├── assets/               # Icons and images
├── Gemfile              # Ruby dependencies
└── README.md            # This file
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

The MPRIS specs talk to a real session bus and skip themselves when there is
none; `dbus-run-session -- bundle exec rspec` runs them on a headless machine.

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
├── spec_helper.rb           # Test configuration
├── support/                 # Test helpers and utilities
│   └── test_helpers.rb     # Shared test helpers
├── factories/              # Test data factories
│   ├── track_factory.rb    # Track test data
│   └── playlist_factory.rb # Playlist test data
├── loamp/                  # Unit tests
│   ├── application_spec.rb # Application tests
│   ├── player_spec.rb      # Player logic tests
│   ├── playlist_spec.rb    # Playlist management tests
│   ├── track_spec.rb       # Track metadata tests
│   └── ui/                 # UI component tests
│       ├── track_info_spec.rb      # Track info display tests
│       └── player_controls_spec.rb # Player controls tests
├── integration_test.rb     # Integration tests
└── loamp_spec.rb          # Module tests
```

### Test Coverage

The test suite covers:
- **Core Logic**: Track metadata, playlist management, player state
- **UI Components**: All GTK widgets and user interactions  
- **Integration**: End-to-end functionality testing
- **Error Handling**: Graceful failure scenarios
- **Edge Cases**: Boundary conditions and invalid inputs

### Continuous Integration

Tests run automatically on:
- Ruby 3.2, 3.3, 3.4, and 4.0
- Ubuntu latest
- All commits and pull requests

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
