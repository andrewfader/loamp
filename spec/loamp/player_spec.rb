# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Player do
  # Real playback through a real pipeline, silenced at the sink. Nothing here
  # is stubbed, so a passing spec means audio genuinely played.
  let(:engine) { Loamp::AudioEngine.new(audio_sink: 'fakesink sync=true') }
  let(:player) { described_class.new(playlist, engine: engine) }

  let(:playlist) do
    Loamp::Playlist.new.tap do |list|
      list.add_track(AudioFixtures.tone(seconds: 2, frequency: 440, name: 'one.wav'))
      list.add_track(AudioFixtures.tone(seconds: 2, frequency: 550, name: 'two.wav'))
      list.add_track(AudioFixtures.tone(seconds: 2, frequency: 660, name: 'three.wav'))
    end
  end

  after { engine.shutdown }

  def play_and_settle
    player.play
    engine.wait_for_state(:playing, timeout: 5)
  end

  describe '#initialize' do
    it 'starts stopped on the first track' do
      expect(player.state).to eq(:stopped)
      expect(player.current_track).to eq(playlist[0])
    end

    it 'defaults to no repeat and no shuffle' do
      expect(player.repeat_mode).to eq(:off)
      expect(player).not_to be_shuffle
    end
  end

  describe '#play' do
    it 'actually plays the current track' do
      play_and_settle
      expect(player).to be_playing
    end

    it 'advances the real playback position' do
      play_and_settle
      sleep 0.6
      expect(player.position).to be > 0
    end

    it 'does nothing when the playlist is empty' do
      empty = described_class.new(Loamp::Playlist.new, engine: engine)
      empty.play
      expect(empty.state).to eq(:stopped)
    end

    it 'is a no-op when already playing' do
      play_and_settle
      sleep 0.5
      position_before = player.position

      player.play
      expect(player.position).to be >= position_before
      expect(player).to be_playing
    end
  end

  describe '#pause and #play_pause' do
    it 'pauses without losing position' do
      play_and_settle
      sleep 0.4
      player.pause

      expect(player).to be_paused
      expect(player.position).to be > 0
    end

    it 'toggles between playing and paused' do
      play_and_settle
      player.play_pause
      expect(player).to be_paused

      player.play_pause
      engine.wait_for_state(:playing, timeout: 5)
      expect(player).to be_playing
    end
  end

  describe '#stop' do
    it 'returns to a stopped state at position zero' do
      play_and_settle
      sleep 0.3
      player.stop

      expect(player).to be_stopped
      expect(player.position).to eq(0)
    end
  end

  describe '#seek' do
    it 'moves within a longer track' do
      list = Loamp::Playlist.new
      list.add_track(AudioFixtures.sample_mp3)
      long_player = described_class.new(list, engine: engine)

      long_player.play
      engine.wait_for_state(:playing, timeout: 5)
      long_player.seek(45)

      expect(long_player.position).to be_within(1.0).of(45)
    end
  end

  describe '#duration' do
    it 'reports the duration of the playing stream' do
      list = Loamp::Playlist.new
      list.add_track(AudioFixtures.sample_mp3)
      long_player = described_class.new(list, engine: engine)

      long_player.play
      engine.wait_for_state(:playing, timeout: 5)

      expect(long_player.duration).to be_within(0.5).of(110.4)
    end
  end

  describe '#next_track' do
    it 'moves to the following track and keeps playing' do
      play_and_settle
      player.next_track
      engine.wait_for_state(:playing, timeout: 5)

      expect(player.current_track).to eq(playlist[1])
      expect(player).to be_playing
    end

    it 'notifies listeners of the track change' do
      changed = []
      player.on_track_changed { |track| changed << track }

      play_and_settle
      player.next_track

      expect(changed.last).to eq(playlist[1])
    end

    it 'stops at the end of the playlist when repeat is off' do
      playlist.set_current_track(2)
      play_and_settle
      player.next_track

      expect(player).to be_stopped
    end

    it 'wraps to the first track when repeating all' do
      player.repeat_mode = :all
      playlist.set_current_track(2)
      play_and_settle
      player.next_track

      expect(player.current_track).to eq(playlist[0])
    end
  end

  describe '#previous_track' do
    it 'restarts the current track when past the rewind threshold' do
      list = Loamp::Playlist.new
      list.add_track(AudioFixtures.sample_mp3)
      list.add_track(AudioFixtures.sample_mp3)
      long_player = described_class.new(list, engine: engine)
      long_player.play
      engine.wait_for_state(:playing, timeout: 5)
      long_player.seek(30)

      long_player.previous_track

      expect(long_player.current_track).to eq(list[0])
      expect(long_player.position).to be < 3
    end

    it 'moves to the previous track when near the start' do
      playlist.set_current_track(1)
      play_and_settle
      player.previous_track

      expect(player.current_track).to eq(playlist[0])
    end

    it 'restarts the first track rather than stopping' do
      play_and_settle
      player.previous_track

      expect(player.current_track).to eq(playlist[0])
      expect(player).not_to be_stopped
    end
  end

  describe '#volume' do
    it 'round trips through the engine' do
      player.set_volume(35)
      expect(player.volume).to eq(35)
      expect(engine.volume).to eq(35)
    end

    it 'clamps out of range values' do
      player.set_volume(300)
      expect(player.volume).to eq(100)

      player.set_volume(-5)
      expect(player.volume).to eq(0)
    end

    it 'mutes and restores' do
      player.set_volume(70)
      player.muted = true
      expect(player).to be_muted

      player.muted = false
      expect(player).not_to be_muted
      expect(player.volume).to eq(70)
    end
  end

  describe 'repeat modes' do
    it 'accepts only known modes' do
      player.repeat_mode = :all
      expect(player.repeat_mode).to eq(:all)

      player.repeat_mode = :nonsense
      expect(player.repeat_mode).to eq(:all)
    end
  end

  describe 'shuffle' do
    it 'still visits every track exactly once' do
      player.shuffle = true
      visited = [playlist.current_index]

      2.times do
        playlist.set_current_track(playlist.next_index(wrap: true))
        visited << playlist.current_index
      end

      expect(visited.sort).to eq([0, 1, 2])
    end

    it 'can be turned back off' do
      player.shuffle = true
      player.shuffle = false
      expect(player).not_to be_shuffle
    end
  end

  describe 'automatic advance' do
    it 'moves to the next track without stopping when one ends' do
      short = Loamp::Playlist.new
      short.add_track(AudioFixtures.tone(seconds: 1, frequency: 440, name: 'short-one.wav'))
      short.add_track(AudioFixtures.tone(seconds: 2, frequency: 660, name: 'short-two.wav'))
      auto = described_class.new(short, engine: engine)

      auto.play
      engine.wait_for_state(:playing, timeout: 5)
      engine.wait_until_stream_starts(count: 2, timeout: 8)

      expect(auto.current_track).to eq(short[1])
      expect(auto).to be_playing
    end

    it 'stops once the last track finishes with repeat off' do
      single = Loamp::Playlist.new
      single.add_track(AudioFixtures.tone(seconds: 1, frequency: 440, name: 'solo.wav'))
      auto = described_class.new(single, engine: engine)

      auto.play
      engine.wait_for_end_of_stream(timeout: 8)

      expect(auto).to be_stopped
    end

    it 'repeats the same track when repeat one is set' do
      single = Loamp::Playlist.new
      single.add_track(AudioFixtures.tone(seconds: 1, frequency: 440, name: 'solo.wav'))
      auto = described_class.new(single, engine: engine)
      auto.repeat_mode = :one

      auto.play
      engine.wait_for_state(:playing, timeout: 5)
      engine.wait_until_stream_starts(count: 2, timeout: 8)

      expect(auto.current_track).to eq(single[0])
      expect(auto).to be_playing
    end
  end

  describe '#tick' do
    it 'reports position updates to listeners' do
      updates = []
      player.on_position_changed { |position, duration| updates << [position, duration] }

      play_and_settle
      sleep 0.4
      player.tick

      expect(updates).not_to be_empty
      expect(updates.last.first).to be > 0
    end
  end

  # The window, the transport controls, the playlist and MPRIS all watch the
  # same player at once, so a later listener must not displace an earlier one.
  describe 'notifying several listeners' do
    it 'tells every track-change listener, not only the last one registered' do
      seen = []
      player.on_track_changed { seen << :first }
      player.on_track_changed { seen << :second }

      player.notify_track_changed(nil)

      expect(seen).to eq(%i[first second])
    end

    it 'tells every state-change listener' do
      seen = []
      player.on_state_changed { seen << :first }
      player.on_state_changed { seen << :second }

      player.notify_state_changed(:playing)

      expect(seen).to eq(%i[first second])
    end

    it 'keeps notifying the rest when one listener raises' do
      seen = []
      player.on_track_changed { raise 'listener exploded' }
      player.on_track_changed { seen << :survivor }

      expect { player.notify_track_changed(nil) }.not_to raise_error
      expect(seen).to eq([:survivor])
    end
  end

  describe 'seek and volume notifications' do
    it 'reports a deliberate jump separately from the steady advance' do
      positions = []
      player.on_seeked { |position| positions << position }

      play_and_settle
      player.seek(1)

      expect(positions.last).to be_within(0.3).of(1.0)
    end

    it 'reports a volume change' do
      levels = []
      player.on_volume_changed { |level| levels << level }

      player.volume = 40

      expect(levels).to eq([40])
    end

    it 'reports a mute as a volume change too' do
      levels = []
      player.on_volume_changed { |level| levels << level }

      player.muted = true

      expect(levels.size).to eq(1)
    end
  end

  describe 'playback errors' do
    it 'surfaces a missing file without crashing' do
      broken = Loamp::Playlist.new
      broken.add_track('/nonexistent/missing-track.mp3')
      failing = described_class.new(broken, engine: engine)

      reported = nil
      failing.on_error { |message| reported = message }

      failing.play
      engine.wait_for_error(timeout: 5)

      expect(reported).to be_a(String)
      expect(failing).to be_stopped
    end
  end
end
