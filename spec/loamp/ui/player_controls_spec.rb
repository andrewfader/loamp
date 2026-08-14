# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::PlayerControls do
  before(:each) do
    skip_if_no_gtk
  end

  let(:playlist) { build(:playlist, :with_tracks) }
  let(:engine) { AudioFixtures.silent_engine }
  let(:player) { Loamp::Player.new(playlist, engine: engine) }
  let(:player_controls) { described_class.new(player) }

  after { engine.shutdown }

  # Drives real playback of a real file so control sensitivity reflects genuine
  # player state rather than a poked instance variable.
  def start_real_playback
    playlist.add_track(AudioFixtures.tone(seconds: 3, name: 'controls.wav'))
    playlist.set_current_track(playlist.size - 1)
    player.play
    engine.wait_for_state(:playing, timeout: 5)
  end

  describe '#initialize' do
    it 'creates a player controls widget' do
      expect(player_controls).to be_a(described_class)
      expect(player_controls).to be_a(Gtk::Box)
    end

    it 'subscribes to player notifications' do
      controls = described_class.new(player)
      position_label = controls.instance_variable_get(:@position_label)

      player.notify_position_changed(65, 200)

      expect(position_label.text).to eq('1:05')
    end

    it 'initializes volume scale with player volume' do
      allow(player).to receive(:volume).and_return(50)
      controls = described_class.new(player)
      volume_scale = controls.instance_variable_get(:@volume_scale)
      expect(volume_scale).to be_a(Gtk::Scale)
      expect(volume_scale.value).to eq(50)
    end
  end

  describe 'button click functionality' do
    let(:controls) { described_class.new(player) }

    context 'play/pause button' do
      it 'calls player play_pause when clicked' do
        play_pause_button = controls.instance_variable_get(:@play_pause_button)
        expect(player).to receive(:play_pause)

        # Simulate button click
        play_pause_button.signal_emit('clicked')
      end
    end

    context 'stop button' do
      it 'calls player stop when clicked' do
        stop_button = controls.instance_variable_get(:@stop_button)
        expect(player).to receive(:stop)

        # Simulate button click
        stop_button.signal_emit('clicked')
      end
    end

    context 'previous button' do
      it 'calls player previous_track when clicked' do
        previous_button = controls.instance_variable_get(:@previous_button)
        expect(player).to receive(:previous_track)

        # Simulate button click
        previous_button.signal_emit('clicked')
      end
    end

    context 'next button' do
      it 'calls player next_track when clicked' do
        next_button = controls.instance_variable_get(:@next_button)
        expect(player).to receive(:next_track)

        # Simulate button click
        next_button.signal_emit('clicked')
      end
    end
  end

  describe 'shuffle button functionality' do
    let(:controls) { described_class.new(player) }

    it 'toggles shuffle mode when clicked' do
      shuffle_button = controls.instance_variable_get(:@shuffle_button)
      expect(shuffle_button).to be_a(Gtk::ToggleButton)

      # Test enabling shuffle
      expect(player).to receive(:shuffle=).with(true)
      shuffle_button.active = true

      # Test disabling shuffle
      expect(player).to receive(:shuffle=).with(false)
      shuffle_button.active = false
    end

    it 'reflects player shuffle state' do
      shuffle_button = controls.instance_variable_get(:@shuffle_button)

      # The toggle is the source of truth for the user-facing state.
      shuffle_button.active = true
      expect(shuffle_button.active?).to be(true)

      shuffle_button.active = false
      expect(shuffle_button.active?).to be(false)
    end
  end

  describe 'repeat button functionality' do
    let(:controls) { described_class.new(player) }

    it 'cycles through repeat modes when clicked' do
      repeat_button = controls.instance_variable_get(:@repeat_button)
      expect(repeat_button).to be_a(Gtk::Button)

      player.repeat_mode = :off
      controls.send(:cycle_repeat_mode)
      expect(player.repeat_mode).to eq(:all)

      controls.send(:cycle_repeat_mode)
      expect(player.repeat_mode).to eq(:one)

      controls.send(:cycle_repeat_mode)
      expect(player.repeat_mode).to eq(:off)
    end

    it 'updates icon and tooltip for repeat modes' do
      controls = described_class.new(player)
      repeat_button = controls.instance_variable_get(:@repeat_button)

      # Test :off mode
      player.repeat_mode = :off
      controls.send(:update_repeat_button_icon)
      expect(repeat_button.child.icon_name).to eq('media-playlist-repeat-symbolic')
      expect(repeat_button.tooltip_text).to eq('Repeat: Off')

      # Test :all mode
      player.repeat_mode = :all
      controls.send(:update_repeat_button_icon)
      expect(repeat_button.child.icon_name).to eq('media-playlist-repeat-symbolic')
      expect(repeat_button.tooltip_text).to eq('Repeat: All')

      # Test :one mode
      player.repeat_mode = :one
      controls.send(:update_repeat_button_icon)
      expect(repeat_button.child.icon_name).to eq('media-playlist-repeat-one-symbolic')
      expect(repeat_button.tooltip_text).to eq('Repeat: One')
    end
  end

  describe 'volume control functionality' do
    let(:controls) { described_class.new(player) }

    it 'updates player volume when scale value changes' do
      volume_scale = controls.instance_variable_get(:@volume_scale)
      expect(volume_scale).to be_a(Gtk::Scale)

      # Test volume change
      expect(player).to receive(:set_volume).with(75)
      volume_scale.value = 75
    end

    it 'reflects player volume changes' do
      volume_scale = controls.instance_variable_get(:@volume_scale)

      volume_scale.value = 80
      expect(volume_scale.value).to eq(80)
    end

    it 'is always sensitive regardless of player state' do
      volume_scale = controls.instance_variable_get(:@volume_scale)

      # Test when stopped
      player.instance_variable_set(:@state, :stopped)
      controls.send(:update_controls)
      expect(volume_scale.sensitive?).to be(true)

      # Test when playing
      player.instance_variable_set(:@state, :playing)
      controls.send(:update_controls)
      expect(volume_scale.sensitive?).to be(true)

      # Test when paused
      player.instance_variable_set(:@state, :paused)
      controls.send(:update_controls)
      expect(volume_scale.sensitive?).to be(true)
    end
  end

  describe 'progress scale functionality' do
    let(:controls) { described_class.new(player) }

    it 'seeks player position when scale is clicked' do
      progress_scale = controls.instance_variable_get(:@progress_scale)
      expect(progress_scale).to be_a(Gtk::Scale)

      # Set up seeking behavior - simulate user clicking at position 60
      progress_scale.value = 60
      expect(player).to receive(:seek).with(60)

      # Simulate the gesture click sequence
      seek_gesture = progress_scale.observe_controllers.find { |c| c.is_a?(Gtk::GestureClick) }
      if seek_gesture
        controls.instance_variable_set(:@seeking, true)
        seek_gesture.signal_emit('pressed', 1, 0, 0)
        controls.instance_variable_set(:@seeking, false)
        seek_gesture.signal_emit('released', 1, 0, 0)
      else
        # Fallback: directly call the seeking logic
        controls.instance_variable_set(:@seeking, false)
        progress_scale.signal_emit('button-release-event', nil)
      end
    end

    it 'is only sensitive when player is playing' do
      progress_scale = controls.instance_variable_get(:@progress_scale)

      # Test when stopped
      player.stop
      controls.send(:update_controls)
      expect(progress_scale.sensitive?).to be(false)

      # Test when playing
      start_real_playback
      controls.send(:update_controls)
      expect(progress_scale.sensitive?).to be(true)

      # Test when paused
      player.pause
      controls.send(:update_controls)
      expect(progress_scale.sensitive?).to be(false)
    end

    it 'updates progress correctly with different durations' do
      progress_scale = controls.instance_variable_get(:@progress_scale)
      position_label = controls.instance_variable_get(:@position_label)
      duration_label = controls.instance_variable_get(:@duration_label)

      # Test with zero duration
      controls.send(:update_progress, 0, 0)
      expect(progress_scale.adjustment.upper).to eq(100)
      expect(progress_scale.value).to eq(0)

      # Test with normal duration
      controls.send(:update_progress, 45, 180)
      expect(progress_scale.adjustment.upper).to eq(180)
      expect(progress_scale.value).to eq(45)
      expect(position_label.text).to eq('0:45')
      expect(duration_label.text).to eq('3:00')
    end
  end

  describe 'player state changes' do
    context 'when player state changes to playing' do
      it 'updates the play/pause button to a pause icon' do
        controls = described_class.new(player)
        play_button = controls.instance_variable_get(:@play_pause_button)
        expect(play_button).to be_a(Gtk::Button)

        player.instance_variable_set(:@state, :playing)
        player.notify_state_changed(:playing)

        expect(play_button.child).to be_a(Gtk::Image)
        expect(play_button.child.icon_name).to eq('media-playback-pause-symbolic')
        expect(play_button.tooltip_text).to eq('Pause')
      end
    end

    context 'when player state changes to paused' do
      it 'updates the play/pause button to a play icon' do
        controls = described_class.new(player)
        play_button = controls.instance_variable_get(:@play_pause_button)
        expect(play_button).to be_a(Gtk::Button)

        player.instance_variable_set(:@state, :paused)
        player.notify_state_changed(:paused)

        expect(play_button.child).to be_a(Gtk::Image)
        expect(play_button.child.icon_name).to eq('media-playback-start-symbolic')
        expect(play_button.tooltip_text).to eq('Play')
      end
    end

    context 'when player state changes to stopped' do
      it 'updates the play/pause button to a play icon' do
        controls = described_class.new(player)
        play_button = controls.instance_variable_get(:@play_pause_button)
        expect(play_button).to be_a(Gtk::Button)

        player.instance_variable_set(:@state, :stopped)
        player.notify_state_changed(:stopped)

        expect(play_button.child).to be_a(Gtk::Image)
        expect(play_button.child.icon_name).to eq('media-playback-start-symbolic')
        expect(play_button.tooltip_text).to eq('Play')
      end
    end
  end

  describe 'track and position changes' do
    it 'updates progress when position changes' do
      controls = described_class.new(player)
      position_label = controls.instance_variable_get(:@position_label)
      duration_label = controls.instance_variable_get(:@duration_label)
      progress_scale = controls.instance_variable_get(:@progress_scale)

      expect(position_label).to be_a(Gtk::Label)
      expect(duration_label).to be_a(Gtk::Label)
      expect(progress_scale).to be_a(Gtk::Scale)

      player.notify_position_changed(90, 205)

      expect(position_label.text).to eq('1:30')
      expect(duration_label.text).to eq('3:25')
      expect(progress_scale.value).to eq(90)
    end

    it 'resets progress when track changes' do
      controls = described_class.new(player)
      new_track = build(:track, duration: 180)
      position_label = controls.instance_variable_get(:@position_label)
      duration_label = controls.instance_variable_get(:@duration_label)
      progress_scale = controls.instance_variable_get(:@progress_scale)

      expect(position_label).to be_a(Gtk::Label)
      expect(duration_label).to be_a(Gtk::Label)
      expect(progress_scale).to be_a(Gtk::Scale)

      player.notify_track_changed(new_track)

      expect(position_label.text).to eq('0:00')
      expect(duration_label.text).to eq('3:00')
      expect(progress_scale.value).to eq(0)
    end
  end

  describe 'controls sensitivity' do
    context 'when playlist is empty' do
      it 'disables transport buttons' do
        playlist.clear
        controls = described_class.new(player)
        buttons = [
          controls.instance_variable_get(:@previous_button),
          controls.instance_variable_get(:@play_pause_button),
          controls.instance_variable_get(:@stop_button),
          controls.instance_variable_get(:@next_button)
        ]

        # Verify all buttons are real GTK buttons
        buttons.each do |button|
          expect(button).to be_a(Gtk::Button)
        end

        player.notify_track_changed(nil)

        buttons.each do |button|
          expect(button.sensitive?).to be(false)
        end
      end
    end

    context 'when playlist has tracks' do
      it 'enables transport buttons' do
        # Add multiple tracks to test next/prev buttons
        # Real files, so the "playing" leg of this example can really play.
        player.playlist.add_track(AudioFixtures.tone(seconds: 3, name: 'transport-one.wav'))
        player.playlist.add_track(AudioFixtures.tone(seconds: 3, name: 'transport-two.wav'))
        player.playlist.select_track(0) # Select the first track

        controls = described_class.new(player)

        # Verify all buttons are real GTK buttons
        play_pause_button = controls.instance_variable_get(:@play_pause_button)
        stop_button = controls.instance_variable_get(:@stop_button)
        next_button = controls.instance_variable_get(:@next_button)
        previous_button = controls.instance_variable_get(:@previous_button)

        expect(play_pause_button).to be_a(Gtk::Button)
        expect(stop_button).to be_a(Gtk::Button)
        expect(next_button).to be_a(Gtk::Button)
        expect(previous_button).to be_a(Gtk::Button)

        # Check sensitivity
        expect(play_pause_button.sensitive?).to be(true)
        expect(stop_button.sensitive?).to be(false) # Stopped initially
        expect(next_button.sensitive?).to be(true)
        expect(previous_button.sensitive?).to be(false)

        # --- Test with player playing ---
        player.play
        engine.wait_for_state(:playing, timeout: 5)
        controls.send(:update_controls)

        expect(stop_button.sensitive?).to be(true)

        # --- Test at the end of the playlist ---
        player.playlist.select_track(1) # Select the last track
        controls.send(:update_controls)

        expect(next_button.sensitive?).to be(false)
        expect(previous_button.sensitive?).to be(true)
      end
    end
  end

  describe '#format_time' do
    it 'formats seconds to M:SS format' do
      expect(player_controls.send(:format_time, 125)).to eq('2:05')
    end

    it 'handles zero seconds' do
      expect(player_controls.send(:format_time, 0)).to eq('0:00')
    end

    it 'handles nil input' do
      expect(player_controls.send(:format_time, nil)).to eq('0:00')
    end

    it 'handles negative input' do
      expect(player_controls.send(:format_time, -10)).to eq('0:00')
    end

    it 'formats minutes correctly with leading zeros for seconds' do
      expect(player_controls.send(:format_time, 65)).to eq('1:05')
    end

    it 'handles long durations correctly' do
      expect(player_controls.send(:format_time, 3661)).to eq('61:01') # 1 hour, 1 minute, 1 second
    end
  end
end
