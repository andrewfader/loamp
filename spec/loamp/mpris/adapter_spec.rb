# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Mpris::Adapter do
  let(:playlist) { Loamp::Playlist.new }
  let(:engine) { AudioFixtures.silent_engine }
  let(:player) { Loamp::Player.new(playlist, engine: engine) }
  let(:art_cache) { instance_double(Loamp::ArtCache, url_for: nil) }
  let(:adapter) { described_class.new(player, art_cache: art_cache) }

  # A pipeline left running past the end of an example goes on emitting into
  # an engine nothing references any more, which GStreamer answers with a
  # segfault rather than an exception.
  after { engine.shutdown }

  let(:player_interface) { Loamp::Mpris::PLAYER_INTERFACE }
  let(:root_interface) { Loamp::Mpris::ROOT_INTERFACE }

  def value_of(interface, name)
    adapter.property(interface, name).last
  end

  describe 'the root interface' do
    it 'identifies itself for the desktop' do
      expect(value_of(root_interface, 'Identity')).to eq('LOAMP')
      expect(value_of(root_interface, 'DesktopEntry')).to eq('loamp')
    end

    it 'can always be quit' do
      expect(value_of(root_interface, 'CanQuit')).to be true
    end

    it 'only claims it can be raised once something is listening' do
      expect(value_of(root_interface, 'CanRaise')).to be false

      adapter.on_raise { nil }

      expect(value_of(root_interface, 'CanRaise')).to be true
    end

    it 'has no track list interface' do
      expect(value_of(root_interface, 'HasTrackList')).to be false
    end

    it 'advertises the schemes the engine can actually open' do
      expect(value_of(root_interface, 'SupportedUriSchemes')).to include('file', 'http')
    end

    it 'runs the Raise handler' do
      raised = false
      adapter.on_raise { raised = true }

      adapter.invoke(root_interface, 'Raise')

      expect(raised).to be true
    end

    it 'runs the Quit handler' do
      quit = false
      adapter.on_quit { quit = true }

      adapter.invoke(root_interface, 'Quit')

      expect(quit).to be true
    end

    it 'refuses a method it does not implement' do
      expect { adapter.invoke(root_interface, 'Fullscreen') }
        .to raise_error(described_class::UnknownMember)
    end
  end

  describe 'playback status' do
    it 'reports Stopped before anything plays' do
      expect(value_of(player_interface, 'PlaybackStatus')).to eq('Stopped')
    end

    it 'reports Playing and Paused as the engine moves' do
      playlist.add_track(AudioFixtures.tone(seconds: 2))
      player.play
      engine.wait_for_state(:playing)

      expect(value_of(player_interface, 'PlaybackStatus')).to eq('Playing')

      player.pause
      engine.wait_for_state(:paused)

      expect(value_of(player_interface, 'PlaybackStatus')).to eq('Paused')
    end
  end

  describe 'loop status' do
    it 'maps the player repeat modes onto the spec names' do
      expect(value_of(player_interface, 'LoopStatus')).to eq('None')

      player.repeat_mode = :all
      expect(value_of(player_interface, 'LoopStatus')).to eq('Playlist')

      player.repeat_mode = :one
      expect(value_of(player_interface, 'LoopStatus')).to eq('Track')
    end

    it 'maps the spec names back when written' do
      adapter.set_property(player_interface, 'LoopStatus', 'Playlist')

      expect(player.repeat_mode).to eq(:all)
    end

    it 'ignores a value the spec does not define' do
      adapter.set_property(player_interface, 'LoopStatus', 'Sideways')

      expect(player.repeat_mode).to eq(:off)
    end
  end

  describe 'volume' do
    it 'reports the 0-100 player volume as a 0.0-1.0 double' do
      player.volume = 50

      expect(value_of(player_interface, 'Volume')).to eq(0.5)
    end

    it 'writes a double back as a percentage' do
      adapter.set_property(player_interface, 'Volume', 0.25)

      expect(player.volume).to eq(25)
    end

    it 'clamps an out-of-range request instead of refusing it' do
      adapter.set_property(player_interface, 'Volume', 4.0)
      expect(player.volume).to eq(100)

      adapter.set_property(player_interface, 'Volume', -1.0)
      expect(player.volume).to eq(0)
    end
  end

  describe 'shuffle' do
    it 'round-trips through the playlist' do
      adapter.set_property(player_interface, 'Shuffle', true)
      expect(value_of(player_interface, 'Shuffle')).to be true

      adapter.set_property(player_interface, 'Shuffle', false)
      expect(value_of(player_interface, 'Shuffle')).to be false
    end
  end

  describe 'rate' do
    it 'reports a single supported rate' do
      expect(value_of(player_interface, 'Rate')).to eq(1.0)
      expect(value_of(player_interface, 'MinimumRate')).to eq(1.0)
      expect(value_of(player_interface, 'MaximumRate')).to eq(1.0)
    end

    it 'accepts a write without changing anything, as the spec requires' do
      expect(adapter.set_property(player_interface, 'Rate', 2.0)).to be true
      expect(value_of(player_interface, 'Rate')).to eq(1.0)
    end
  end

  describe 'read-only properties' do
    it 'refuses to be written' do
      expect(adapter.set_property(player_interface, 'PlaybackStatus', 'Playing')).to be false
    end
  end

  describe 'capabilities' do
    it 'cannot play an empty playlist' do
      expect(value_of(player_interface, 'CanPlay')).to be false
      expect(value_of(player_interface, 'CanGoNext')).to be false
      expect(value_of(player_interface, 'CanGoPrevious')).to be false
    end

    it 'can go forwards but not back at the head of the playlist' do
      2.times { playlist.add_track(AudioFixtures.tone(seconds: 1)) }

      expect(value_of(player_interface, 'CanPlay')).to be true
      expect(value_of(player_interface, 'CanGoNext')).to be true
      expect(value_of(player_interface, 'CanGoPrevious')).to be false
    end

    it 'can go both ways at the end of the playlist once repeat is on' do
      2.times { playlist.add_track(AudioFixtures.tone(seconds: 1)) }
      playlist.set_current_track(1)
      player.repeat_mode = :all

      expect(value_of(player_interface, 'CanGoNext')).to be true
      expect(value_of(player_interface, 'CanGoPrevious')).to be true
    end

    it 'cannot seek while stopped' do
      expect(value_of(player_interface, 'CanSeek')).to be false
    end

    it 'can seek once a track is loaded and its duration is known' do
      playlist.add_track(AudioFixtures.tone(seconds: 2))
      player.play
      engine.wait_for_state(:playing)

      expect(value_of(player_interface, 'CanSeek')).to be true
    end

    it 'is always controllable and pausable' do
      expect(value_of(player_interface, 'CanControl')).to be true
      expect(value_of(player_interface, 'CanPause')).to be true
    end
  end

  describe 'metadata' do
    it 'reports the reserved no-track path when nothing is loaded' do
      expect(adapter.metadata['mpris:trackid']).to eq(['o', Loamp::Mpris::NO_TRACK])
    end

    it 'maps tags onto their xesam names' do
      track = AudioFixtures.track_with(title: 'Song', artist: 'Haim', album: 'Days Are Gone',
                                       album_artist: 'Haim', genre: 'Pop', track_number: 3,
                                       disc_number: 1, year: 2013, duration: 210)

      metadata = adapter.metadata(track)

      expect(metadata['xesam:title']).to eq(['s', 'Song'])
      expect(metadata['xesam:artist']).to eq(['as', ['Haim']])
      expect(metadata['xesam:album']).to eq(['s', 'Days Are Gone'])
      expect(metadata['xesam:trackNumber']).to eq(['i', 3])
      expect(metadata['xesam:contentCreated']).to eq(['s', '2013-01-01T00:00:00Z'])
    end

    it 'reports length in microseconds' do
      track = AudioFixtures.track_with(duration: 210)

      expect(adapter.metadata(track)).to include('mpris:length' => ['x', 210_000_000])
    end

    it 'omits the length of a track whose duration is unknown' do
      track = AudioFixtures.track_with(duration: 0)

      expect(adapter.metadata(track)).to include('mpris:length' => ['x', nil])
    end

    it 'falls back to the filename when a track carries no title' do
      track = Loamp::Track.new(AudioFixtures.sample_mp3)

      expect(adapter.metadata(track).fetch('xesam:title').last).to eq('turkey_in_the_straw')
    end

    it 'includes the art URL the cache resolved' do
      allow(art_cache).to receive(:url_for).and_return('file:///cache/art.jpg')

      metadata = adapter.metadata(AudioFixtures.track_with)

      expect(metadata).to include('mpris:artUrl' => ['s', 'file:///cache/art.jpg'])
    end

    it 'gives a track a distinct object path so clients notice the change' do
      first = AudioFixtures.track_with(title: 'One')
      second = AudioFixtures.track_with(title: 'Two')

      expect(adapter.track_id(first)).not_to eq(adapter.track_id(second))
      expect(adapter.track_id(first)).to eq(adapter.track_id(first))
    end

    it "prefers the current track's live duration over the tagged one" do
      playlist.add_track(AudioFixtures.tone(seconds: 2))
      player.play
      engine.wait_for_state(:playing)

      length = adapter.metadata.fetch('mpris:length').last

      expect(length).to be_within(200_000).of(2_000_000)
    end
  end

  describe 'position' do
    it 'is reported in microseconds' do
      allow(player).to receive(:position).and_return(1.5)

      expect(adapter.position_microseconds).to eq(1_500_000)
    end
  end

  describe 'transport methods' do
    before { playlist.add_track(AudioFixtures.tone(seconds: 2)) }

    it 'plays' do
      adapter.invoke(player_interface, 'Play')
      engine.wait_for_state(:playing)

      expect(player).to be_playing
    end

    it 'pauses and resumes through PlayPause' do
      adapter.invoke(player_interface, 'Play')
      engine.wait_for_state(:playing)

      adapter.invoke(player_interface, 'PlayPause')
      engine.wait_for_state(:paused)

      expect(player).to be_paused
    end

    it 'stops' do
      adapter.invoke(player_interface, 'Play')
      engine.wait_for_state(:playing)

      adapter.invoke(player_interface, 'Stop')

      expect(player).to be_stopped
    end

    it 'moves to the next track' do
      playlist.add_track(AudioFixtures.tone(seconds: 1, frequency: 880))
      adapter.invoke(player_interface, 'Play')
      engine.wait_for_state(:playing)

      adapter.invoke(player_interface, 'Next')

      expect(playlist.current_index).to eq(1)
    end

    it 'refuses a method it does not implement' do
      expect { adapter.invoke(player_interface, 'Rewind') }
        .to raise_error(described_class::UnknownMember)
    end
  end

  describe 'Seek' do
    before do
      playlist.add_track(AudioFixtures.tone(seconds: 4))
      player.play
      engine.wait_for_state(:playing)
    end

    it 'moves forward by a relative offset' do
      adapter.invoke(player_interface, 'Seek', [2_000_000])

      expect(player.position).to be_within(0.3).of(2.0)
    end

    it 'never lands before the start of the track' do
      adapter.invoke(player_interface, 'Seek', [-30_000_000])

      expect(player.position).to be_within(0.3).of(0.0)
    end

    it 'moves to the next track when the offset runs past the end' do
      playlist.add_track(AudioFixtures.tone(seconds: 1, frequency: 880))

      adapter.invoke(player_interface, 'Seek', [60_000_000])

      expect(playlist.current_index).to eq(1)
    end

    it 'does nothing when nothing is playing' do
      player.stop

      expect { adapter.invoke(player_interface, 'Seek', [1_000_000]) }.not_to raise_error
    end
  end

  describe 'SetPosition' do
    before do
      playlist.add_track(AudioFixtures.tone(seconds: 4))
      player.play
      engine.wait_for_state(:playing)
    end

    it 'seeks the named track to an absolute position' do
      adapter.invoke(player_interface, 'SetPosition',
                     [adapter.track_id(player.current_track), 2_000_000])

      expect(player.position).to be_within(0.3).of(2.0)
    end

    it 'ignores a request naming a track that is no longer current' do
      adapter.invoke(player_interface, 'SetPosition', ['/org/mpris/MediaPlayer2/loamp/track/99',
                                                       2_000_000])

      expect(player.position).to be < 1.0
    end

    it 'ignores a position beyond the end of the track' do
      adapter.invoke(player_interface, 'SetPosition',
                     [adapter.track_id(player.current_track), 60_000_000])

      expect(player.position).to be < 1.0
    end
  end

  describe 'OpenUri' do
    it 'adds a local file and starts playing it' do
      uri = Loamp::FileUri.for(AudioFixtures.tone(seconds: 1))

      adapter.invoke(player_interface, 'OpenUri', [uri])
      engine.wait_for_state(:playing)

      expect(playlist.size).to eq(1)
      expect(player).to be_playing
    end

    it 'ignores a URI that is not a file it can open' do
      adapter.invoke(player_interface, 'OpenUri', ['file:///no/such/track.mp3'])

      expect(playlist).to be_empty
    end
  end

  describe '#properties' do
    it 'returns every property of an interface with its signature' do
      properties = adapter.properties(root_interface)

      expect(properties.keys).to match_array(described_class::ROOT_PROPERTIES.keys)
      expect(properties['Identity']).to eq(['s', 'LOAMP'])
    end

    it 'returns only the named subset when asked' do
      expect(adapter.properties(player_interface, %w[Volume]).keys).to eq(%w[Volume])
    end
  end
end
