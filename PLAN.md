# LOAMP Plan

This plan is now an implementation record. The feature work below has been
completed; the detailed notes are retained to explain design choices and the
constraints that shaped them.

## Where things stand

Done:

- **GStreamer engine** (`lib/loamp/audio_engine.rb`) — `playbin3` driven from
  the GLib main loop. Real position and duration queries, flushing seeks,
  cubic volume, gapless hand-off via `about-to-finish`, bus drained by `#pump`.
- **TagLib metadata** (`lib/loamp/metadata.rb`, `metadata/reader.rb`) —
  MP3/FLAC/Ogg/Opus/M4A, embedded artwork, ReplayGain tags, album artist and
  disc numbering. Never raises; degrades to the filename.
- **libadwaita UI** — `Adw::Window` + `ToolbarView` + `OverlaySplitView` with a
  collapse breakpoint, toasts instead of a status bar, and `Gtk::ColumnView`
  (virtualised) instead of the deprecated `Gtk::TreeView`.
- **Local artwork** (`lib/loamp/artwork.rb`) — embedded picture first, then
  `cover`/`folder`/`front`/`album`/`albumart` images beside the track.
- **MPRIS2** (`lib/loamp/mpris/`) — both interfaces on the session bus via
  GIO, so media keys, the GNOME Shell widget and `playerctl` all work.
- **Art cache** (`lib/loamp/art_cache.rb`) — cover art as a `file://` URL,
  keyed per album under `$XDG_CACHE_HOME/loamp/art/`. Built for MPRIS, and the
  disk half of item 3 below.
- **CI system dependencies** — libadwaita, TagLib, the GStreamer plugin sets
  and a `dbus-run-session` wrapper are all in `.github/workflows/ci.yml`.
- **Library index** (`lib/loamp/library.rb`, `library/`) — SQLite with FTS5
  search, incremental rescan keyed on `(path, mtime, size)`, and a threaded
  scanner that reports through `GLib::Idle`. 10k tracks index in 1.4s once
  tags are read, rescan of an unchanged folder takes 0.37s, and search
  answers in about 5ms.
- **Library browser** (`lib/loamp/ui/library_view.rb`) — artists, albums and
  tracks as three linked panes with a search box, on a `Adw::ViewStack` page
  beside Now Playing.
- **Network cover art** (`lib/loamp/http/`, `lib/loamp/cover_art/`) — see item
  1 below, which is now a record of what was built rather than a plan.
- **MusicBrainz identifiers** — `Metadata` reads `MUSICBRAINZ_ALBUMID` and
  `MUSICBRAINZ_ALBUMARTISTID` from Vorbis comments, ID3v2 TXXX frames and MP4
  freeform atoms, and the library index stores them. Item 6 needs exactly
  these to key its similarity graph.

Suite: 689 examples, 0 failures, 80%+ enforced line coverage, rubocop clean,
plus a real Wayland/GStreamer visualizer render test.

---

## 1. Album art pipeline

Done. Local resolution, the disk cache and the network half are all in place:

- `Loamp::Http::Client` and `Http::RateLimiter` — one polite HTTP client for
  every service in this file. Descriptive User-Agent, timeouts, redirects
  followed, failures reported rather than raised, and a rate limit that holds
  across threads.
- `Loamp::CoverArt::MusicBrainz` resolves artist + album to a release MBID at
  one request a second, refusing matches scoring under 80; files carrying
  `MUSICBRAINZ_ALBUMID` skip the search entirely.
- `Loamp::CoverArt::Archive` fetches `coverartarchive.org/release/<mbid>/front`
  at a chosen size, following the redirect the archive answers with.
- `Loamp::CoverArt::MissLog` remembers confirmed misses on disk for 30 days.
  A miss the network caused is deliberately not remembered.
- `ArtCache#fetch_remote` runs the lookup on a worker thread, hands the result
  back through `GLib::Idle`, writes the image into the same album-keyed cache
  the local half uses, and starts one lookup per album however many of its
  tracks ask at once. `Application` calls it on every track change and tells
  both the now-playing pane and MPRIS when art arrives late.

Completed follow-ups:

- List rows request size-keyed cached thumbnails and decode them away from the
  full-sized Now Playing/MPRIS artwork.
- `Client::CONTACT` defaults to the project home. Packagers and forks can set
  `LOAMP_CONTACT` to their own maintained support URL.

Note `TrackInfo#decode_texture` scales during decode via
`GdkPixbuf::PixbufLoader`'s `size-prepared` signal — reuse that.

---

## 2. Gapless, crossfade, ReplayGain, EQ and visualization

Done. The standard engine has a ReplayGain bypass selector, limiter and
ten-band preset EQ. Processing choices persist. Crossfade uses two playbin3
decoders feeding an audiomixer and safely falls back to the standard engine if
the required interaudio elements are unavailable. The Visualizer page prefers
projectM and falls back to Goom, rendering through `gtk4paintablesink`.

Gapless is done. The rest needs a filter chain in place of playbin's default
audio sink, set via the `audio-sink` property (the engine already supports an
injected sink — that is how specs pass `fakesink`):

```
audioconvert ! rgvolume ! rglimiter ! equalizer-10bands ! audioconvert ! autoaudiosink
```

- **ReplayGain**: `rgvolume` reads the tags GStreamer parses; `Metadata` also
  exposes `replaygain_track_gain`/`album_gain` for display and as a fallback.
  Offer album vs track mode.
- **EQ**: `equalizer-10bands` exposes `band0`..`band9`. Ship the classic
  Winamp presets and persist the user's choice.
- **Crossfade** is the hard one: playbin3 cannot overlap its own streams. It
  needs two pipelines feeding an `audiomixer`, with volume ramps driven by
  `GstController`. Treat as a separate, larger piece of work.

---

## 3. Lyrics with LRCLIB

Done: embedded and sidecar lyrics resolve before LRCLIB, fetched documents and
definitive misses are cached, and the Lyrics page follows playback position.

- Resolve in order: embedded `USLT`/`SYLT` frames, then a sidecar `.lrc` beside
  the track, then LRCLIB (`https://lrclib.net/api/get`, free, no auth,
  returns both plain and synced lyrics) through `Loamp::Http::Client`.
- The shape to copy is `CoverArt::Fetcher` plus `ArtCache#fetch_remote`:
  resolve locally first, fetch on a worker thread, hand back on `GLib::Idle`,
  and remember confirmed misses on disk with `CoverArt::MissLog`.
- Write an LRC parser for `[mm:ss.xx]` timestamps into `[seconds, text]` pairs.
- Karaoke pane driven by `AudioEngine#position`; the app already ticks at
  250ms via `Application::TICK_INTERVAL_MS`, which is fine for line-level
  highlighting.
- Cache fetched lyrics next to the cache used in item 1.
- `Metadata::Reader` does not read `USLT`/`SYLT` yet — add it there rather than
  in the lyrics layer.

---

## 4. Podcasts and internet radio

Done: RSS/Atom, OPML, resumable downloads and episode positions are backed by
SQLite. Radio Browser has mirrors/failover, favorites, history and live tags.

Both ride the GStreamer HTTP source, so playback needs no engine changes —
`AudioEngine#load` already passes non-`file://` URIs straight through.

- **Podcasts**: RSS/Atom parsing, OPML import/export, episode download with
  resume, and remembering playback position per episode. Needs the library DB,
  which is now in place.
Both go through `Loamp::Http::Client`, which already carries the User-Agent,
the timeouts and the rate limiter these APIs want.

- **Radio (search and playback done)**: `Radio::Browser` searches radio-browser.info and
  normalizes healthy results into `Radio::Station`; stations become tracks
  without sending a network URL through TagLib. GStreamer `TAG` messages now
  flow through `AudioEngine` and `Player`, updating the now-playing title
  without pretending the stream itself changed. `UI::RadioView` searches on a
  worker thread, presents results as a Radio page, and queues a station on
  activation. What remains is favorites/history and directory-server failover.
- Live streams have no duration; the seek bar must handle that (currently
  `duration` returns 0, which the progress row already tolerates).

---

## 5. Streaming provider plugin layer

Done for the open/playable tier: the registry supports playable and link-only
items, with Subsonic/Navidrome and Jellyfin implementations. Closed services
remain link-only by design rather than attempting prohibited local decoding.

Define `Loamp::Provider` with `search`, `browse`, and
`resolve_stream_uri(track)`, then implement per service. **The tiers are not
equal and this should shape what gets built:**

- **Fully open, build these**: Subsonic / Navidrome / Jellyfin. Documented
  APIs, real playback, self-hosted. The best "streaming" story on Linux and
  the right first implementation. ListenBrainz and Last.fm scrobbling belong
  here too — see item 6, which needs them for its feedback loop.
- **Gray, optional plugin only**: YouTube Music via `yt-dlp`. It works, but it
  violates YouTube's terms, so it cannot be enabled by default or shipped in a
  distro/Flatpak package. Structure it as a plugin the user installs
  deliberately.
- **Effectively closed, metadata only**: Spotify needs `librespot`
  (reverse-engineered, Premium-only, risks account action); Apple Music is
  Widevine DRM with no Linux SDK; Deezer's SDK is dead. Realistic scope is
  OAuth search, deep links, and Spotify **Connect remote control** — which is
  legitimate and genuinely useful — but not local audio decode.

Design the interface so a provider may legally return "cannot play, here is a
link" rather than assuming every provider yields a stream URI.

---

## 6. Themed radio and the similar-artist graph

Done: MusicBrainz identity resolution, ListenBrainz/Last.fm similarity,
durable scrobbling, feedback-aware stations, variety limits, queue refill and
the interactive graph are integrated. Graph nodes expand off-thread and
support click, double-click, drag/pin, zoom and familiar/adventurous steering.

The Pandora-style half of the app: seed a station, let it play forever, and
let the listener steer it. Depends on the library index, which is
built, for the pool of playable music, and on item 5 for anything beyond the
local disk.

### Where the similarity data comes from

No service will licence us their taste graph, but two open ones are enough:

- **ListenBrainz** (`api.listenbrainz.org`) — the default. Free, no key for
  reads, and the Labs endpoints expose the derived datasets we actually want:
  `similar-artists` and `similar-recordings`, both keyed by MusicBrainz MBID.
  Data is CC0, so it can be cached on disk without a licensing problem.
- **Last.fm** (`ws.audioscrobbler.com/2.0/`) — richer tag data.
  `artist.getSimilar`, `tag.getTopArtists` and `artist.getTopTags` are what a
  themed station is built from. Needs a free API key, and the terms require
  attribution and forbid redistributing bulk data — so cache per user, never
  ship a prebuilt graph.
- **MusicBrainz** for identity. Similarity is keyed by MBID, and the library
  holds free-text tags, so resolving `artist name -> MBID` once per artist and
  storing it in the index is a prerequisite, not an afterthought. Reading the
  tags is done — `Metadata#musicbrainz_artist_id`, stored in the index — so
  artists whose files do not carry one are resolved through the same
  `Http::Client` the cover art layer uses.

Both services rate-limit (Last.fm to roughly 5 requests/second, MusicBrainz to
one). Everything goes through one polite queue with a descriptive User-Agent,
and every response is cached in the library DB with a fetched-at timestamp.
Similarity does not change hourly; a month-old cache entry is fine.

### Scrobbling, which is the other half of the loop

`ListenBrainz` (`submit-listens`) and Last.fm (`track.scrobble`) both want a
"now playing" ping at track start and a submission once half the track or four
minutes has played, whichever comes first. Item 6 lists this under providers;
it belongs here too, because a station that knows what the listener actually
finished is a better station. Queue submissions and retry — a scrobble lost to
a flaky connection is the one thing users notice.

### Stations

`Loamp::Radio::Station` takes a seed and yields tracks forever:

- Seeds: an artist, a track, a tag/genre ("shoegaze", "90s"), a decade, or the
  listener's own library ("shuffle everything I have, weighted").
- Expansion: seed -> related artists (weighted) -> tracks by those artists that
  the library actually holds, or that a configured provider can stream. A
  station over local files only ever plays what exists, so the graph is a
  ranking device, not a source of tracks.
- Steering: thumbs up/down per track, "never play this artist again", and a
  familiar/adventurous slider that biases how far from the seed the walk goes.
  Feedback is local, stored in the library DB, and reweights future picks.
- Variety rules matter more than they look: no same-artist repeat inside a
  window, no track twice per session, and a cap on how much any one album
  contributes. Without these a station sounds broken however good the graph is.
- The queue is filled a few tracks ahead so the gapless hand-off in
  `Player#queue_following_track` always has something to hand over.

### The live graph browser

An `Adw::NavigationPage` holding a `Gtk::DrawingArea`, artists as nodes and
similarity as edge weight:

- Force-directed layout — springs along edges, repulsion between nodes,
  damped. A few hundred nodes is the ceiling for the naive O(n^2) step; past
  that it needs Barnes-Hut, which is a reason to cap what is shown rather than
  to write a quadtree.
- Animate from the widget's frame clock via `Gtk::Widget#add_tick_callback`,
  not a `GLib::Timeout` — it gives the frame time and stops when unmapped.
  Draw with `Gtk::Snapshot` (`Gsk::Path` for edges) rather than Cairo, so it
  stays on the GPU path.
- Interaction through `Gtk::GestureClick` and `Gtk::GestureDrag`: click a node
  to expand its neighbours (fetched lazily, then re-laid-out), double-click to
  start a station there, drag to pin a node, scroll to zoom.
- Colour nodes by whether the library holds them: the point of the view is
  discovering both what is in the collection and what is missing from it.
- Expansion must never block the UI. Fetch on a worker thread, hand results
  back with `GLib::Idle.add`, and show a node as pending until its edges land.
- Fall back gracefully offline: with no network, build the graph from the
  library's own tag and genre co-occurrence. It is a poorer graph, but a
  present one.

Acceptance: seeding a station from an artist plays for an hour without
repeating itself or drifting into nothing; thumbs-down visibly changes what
follows; the graph stays interactive at 60fps while a station plays, and
expanding a node never stutters the audio.

---

## Gotchas worth remembering

Hard-won during the work already done:

- ruby-gnome **cannot build or read a GVariant dictionary**. `GLib::Variant.new`
  raises `NotImplementedError` on `a{sv}`, and a reply or signal payload
  containing one raises during conversion — inside a GIO callback, which aborts
  the process. `Loamp::Mpris::Variant` goes around it by serialising to
  GVariant text and calling `GLib::Variant.parse`; specs that need to read such
  a reply shell out to `gdbus`.
- GVariant text needs a trailing comma in a one-element tuple (`(int64 5,)`)
  and an explicit type on an empty container (`@as []`, `@a{sv} {}`).
- `Gio::DBusNodeInfo#interfaces` and `DBusInterfaceInfo#methods` return
  garbage from this binding. `#lookup_interface` works.
- D-Bus lives at `Gio.bus_get_sync` / `Gio.bus_own_name_on_connection`, not
  under a `Gio::Bus` class.
- A synchronous D-Bus call to an object exported on the same main context
  deadlocks. Call asynchronously and iterate the context.
- GStreamer's `about-to-finish` fires on the streaming thread. An engine that
  is dropped without `#shutdown` while its pipeline still runs segfaults, which
  is why `#shutdown` disconnects the handler.
- A `Gtk::Popover` parented with `set_parent` **must be unparented** before it
  is finalised. GTK warns "still has children left" and the dangling parent
  turns into a segfault in an unrelated spec later. `PlaylistView#shutdown`
  does it, and `MainWindow#shutdown` calls that — closing a window reaches the
  window but not its children.
- **`GtkWidget::destroy` is useless as a teardown hook in GTK4.** It is emitted
  from `dispose`, so it does not fire while anything still holds a reference —
  and in ruby-gnome the Ruby wrapper always does. `window.destroy` returns
  having emitted nothing. `MainWindow` hangs teardown off `close-request`
  (returning false so the window still closes), and `Application` calls
  `#shutdown` directly from the app's own `shutdown` signal because quitting
  via `app.quit` closes no window at all.
- `Gtk::Popover#parent` **raises** (`(null) isn't supported`) — another struct
  field exposed through introspection, like the `parent=` that segfaults.
- `Gtk::SearchEntry` debounces `search-changed` internally. The pending timer
  keeps the entry alive past the view that owns it, so the handler must be
  disconnected on teardown or it fires into a half-collected object.
- Mutating a `Gio::ListStore` from inside a `selection-changed` handler
  re-enters GTK while the model is still changing. `LibraryView` sets a
  loading flag around every refill for exactly this reason.
- Prefer `Gio::ListStore#splice` to a loop of `#append`: each append emits
  items-changed and the list view answers every one.
- SQLite resolves a bare name in `GROUP BY` to a **real column before an
  output alias**, so `SELECT album AS title ... GROUP BY title` silently
  groups by the song title. Repeat the expression instead.
- An in-memory SQLite database belongs to the connection that created it, so
  the scanner cannot open a second handle onto one — it shares the instance.
- `Gst.init` **exists but is not callable** from ruby-gnome. Requiring `gst`
  initializes GStreamer; calling `Gst.init` raises `NoMethodError`.
- `popover.parent = widget` **segfaults** — `Gtk::Popover` exposes a struct
  field of that name through introspection. Use `set_parent`.
- Popping up a popover whose widget is not yet inside a toplevel window also
  segfaults. `PlaylistView#show_context_menu` guards on `root`.
- `Gdk::Texture.new_from_bytes` does not exist in this binding. Decode via
  `GdkPixbuf::PixbufLoader` then `Gdk::Texture.new(pixbuf)`.
- `Gtk::PopoverMenu.new(model)` takes the model positionally; the keyword form
  raises.
- Do not name a private method the same as an inherited GObject method — a
  helper called `add_breakpoint` silently shadowed `Adw::Window#add_breakpoint`.
- Endless method definitions cannot define setters (`def x=(v) = ...` is a
  syntax error).
- libadwaita ignores `GtkSettings:gtk-application-prefer-dark-theme` and warns.
  Colour scheme goes through `UI::Style`, which wraps `Adw::StyleManager`.
- `assets/style.css` must only add what Adwaita has no opinion about. It
  previously hardcoded backgrounds and broke light mode entirely.

## Housekeeping (completed)

- The obsolete dialog/volume scripts and duplicate `Gemfile.test` were removed.
- GTK setup no longer terminates the whole process on initialization failure;
  integration runs use a Wayland compositor and Cairo renderer in CI/headless
  environments.
- Several UI specs still assert against `instance_variable_get` internals.
  They pass, but they test structure rather than behaviour and will churn on
  the next UI change.
- `Player` callbacks are now multicast. Before that, `MainWindow`,
  `PlayerControls` and `PlaylistView` each registered `on_track_changed` and
  only the last one ever ran — worth checking whether anything else in the UI
  was quietly relying on the broken behaviour.
