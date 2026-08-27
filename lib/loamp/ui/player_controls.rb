# frozen_string_literal: true

module Loamp
  module UI
    # Player controls widget with play/pause/stop buttons, volume, and progress
    class PlayerControls < Gtk::Box
      def initialize(player)
        super(:vertical, 10)
        @player = player

        create_widgets
        layout_widgets
        connect_signals
        setup_player_callbacks

        # Trigger initial update
        update_controls
        update_track_progress
      end

      private

      def setup_player_callbacks
        @player.on_state_changed do |state|
          update_play_pause_button(state)
          update_controls
        end

        @player.on_position_changed do |position, duration|
          update_progress(position, duration)
        end

        @player.on_track_changed do |track|
          update_track_progress(track)
          update_controls
        end

        @player.on_volume_changed do |_volume|
          refresh_volume_display
        end
      end

      def update_track_progress(track = nil)
        track ||= @player.playlist.current_track
        duration = track ? track.duration : 0
        update_progress(0, duration)
      end

      def create_widgets
        add_css_class('loamp-console')
        create_console_header_widgets
        create_transport_widgets
        create_progress_widgets
        create_volume_widgets
      end

      def create_console_header_widgets
        @console_label = Gtk::Label.new('Playback')
        @console_label.add_css_class('loamp-kicker')
        @console_label.xalign = 0

        @state_label = Gtk::Label.new
        @state_label.add_css_class('loamp-status')
        @state_label.xalign = 1
      end

      def create_transport_widgets
        @transport_box = Gtk::Box.new(:horizontal, 5)
        @transport_box.halign = :center

        @previous_button = Gtk::Button.new
        @previous_button.child = Gtk::Image.new(icon_name: 'media-skip-backward-symbolic')
        @previous_button.tooltip_text = 'Previous Track'

        @play_pause_button = Gtk::Button.new
        update_play_pause_button(@player.state)

        @stop_button = Gtk::Button.new
        @stop_button.child = Gtk::Image.new(icon_name: 'media-playback-stop-symbolic')

        @next_button = Gtk::Button.new
        @next_button.child = Gtk::Image.new(icon_name: 'media-skip-forward-symbolic')
        @next_button.tooltip_text = 'Next Track'

        # Shuffle and repeat controls
        @shuffle_button = Gtk::ToggleButton.new
        @shuffle_button.child = Gtk::Image.new(icon_name: 'media-playlist-shuffle-symbolic')
        @shuffle_button.tooltip_text = 'Shuffle'

        @repeat_button = Gtk::Button.new
        update_repeat_button_icon
      end

      def create_progress_widgets
        @progress_box = Gtk::Box.new(:horizontal, 10)

        @position_label = Gtk::Label.new('0:00')
        @position_label.width_chars = 5

        @progress_scale = Gtk::Scale.new(:horizontal)
        @progress_scale.set_range(0, 100)
        @progress_scale.value = 0
        @progress_scale.draw_value = false
        @progress_scale.add_css_class('loamp-progress')

        @duration_label = Gtk::Label.new('0:00')
        @duration_label.width_chars = 5
      end

      def create_volume_widgets
        @volume_box = Gtk::Box.new(:horizontal, 10)
        @volume_box.halign = :center

        @volume_label = Gtk::Label.new('Volume:')

        @volume_scale = Gtk::Scale.new(:horizontal)
        @volume_scale.set_range(0, 100)
        @volume_scale.value = @player.volume
        @volume_scale.width_request = 150
        # Showing the raw value renders as "100.0", which looks like a bug.
        @volume_scale.draw_value = false
        @volume_scale.tooltip_text = 'Volume'
        @volume_value_label = Gtk::Label.new("#{@player.volume.to_i}%")
        @volume_value_label.add_css_class('loamp-volume-value')
        @volume_value_label.add_css_class('numeric')
      end

      # Rows read top to bottom: progress, transport, volume. Using append
      # keeps the source order and the visual order the same.
      def layout_widgets
        set_orientation(:vertical)
        set_spacing(6)

        append(build_console_header)
        append(build_progress_row)
        append(build_transport_row)
        append(build_volume_row)
      end

      def build_console_header
        row = Gtk::Box.new(:horizontal, 8)
        row.append(@console_label)
        @state_label.hexpand = true
        row.append(@state_label)
        row
      end

      def build_progress_row
        row = Gtk::Box.new(:horizontal, 8)
        row.hexpand = true

        @progress_scale.hexpand = true
        row.append(@position_label)
        row.append(@progress_scale)
        row.append(@duration_label)
        row
      end

      def build_transport_row
        row = Gtk::Box.new(:horizontal, 6)
        row.halign = :center

        [@shuffle_button, @previous_button, @play_pause_button,
         @stop_button, @next_button, @repeat_button].each do |button|
          button.add_css_class('circular')
          row.append(button)
        end

        # The primary action reads as primary.
        @play_pause_button.add_css_class('suggested-action')
        @play_pause_button.add_css_class('loamp-play')
        row
      end

      def build_volume_row
        row = Gtk::Box.new(:horizontal, 6)
        row.halign = :center

        @mute_button = Gtk::ToggleButton.new
        @mute_button.add_css_class('flat')
        @mute_button.tooltip_text = 'Mute'
        refresh_mute_button

        row.append(@mute_button)
        row.append(@volume_scale)
        row.append(@volume_value_label)
        row
      end

      def connect_signals
        @play_pause_button.signal_connect('clicked') do
          @player.play_pause
        end

        @stop_button.signal_connect('clicked') do
          @player.stop
        end

        @previous_button.signal_connect('clicked') do
          @player.previous_track
        end

        @next_button.signal_connect('clicked') do
          @player.next_track
        end

        @shuffle_button.signal_connect('toggled') do
          @player.shuffle = @shuffle_button.active?
        end

        @repeat_button.signal_connect('clicked') do
          cycle_repeat_mode
        end

        @mute_button.signal_connect('toggled') do
          next if @updating_mute

          @player.muted = @mute_button.active?
          refresh_mute_button
          refresh_volume_label
        end

        seek_gesture = Gtk::GestureClick.new
        seek_gesture.signal_connect('pressed') do
          @seeking = true
        end
        seek_gesture.signal_connect('released') do
          @seeking = false
          @player.seek(@progress_scale.value) if @progress_scale.sensitive?
        end
        @progress_scale.add_controller(seek_gesture)

        @volume_scale.signal_connect('value-changed') do
          next if @updating_volume

          @player.muted = false if @player.muted?
          @player.set_volume(@volume_scale.value.to_i)
          refresh_volume_label
          refresh_mute_button
        end
      end

      def update_play_pause_button(state)
        @state_label.text = state == :playing ? 'Playing' : 'Stopped' if @state_label
        remove_css_class('is-playing')
        add_css_class('is-playing') if state == :playing

        case state
        when :playing
          @play_pause_button.child = Gtk::Image.new(icon_name: 'media-playback-pause-symbolic')
          @play_pause_button.tooltip_text = 'Pause'
        else
          @play_pause_button.child = Gtk::Image.new(icon_name: 'media-playback-start-symbolic')
          @play_pause_button.tooltip_text = 'Play'
        end
      end

      def update_repeat_button_icon
        @repeat_button.remove_css_class('suggested-action')
        case @player.repeat_mode
        when :off
          @repeat_button.child = Gtk::Image.new(icon_name: 'media-playlist-repeat-symbolic')
          @repeat_button.tooltip_text = 'Repeat: Off'
        when :one
          @repeat_button.child = Gtk::Image.new(icon_name: 'media-playlist-repeat-one-symbolic')
          @repeat_button.tooltip_text = 'Repeat: One'
          @repeat_button.add_css_class('suggested-action')
        when :all
          @repeat_button.child = Gtk::Image.new(icon_name: 'media-playlist-repeat-symbolic')
          @repeat_button.tooltip_text = 'Repeat: All'
          @repeat_button.add_css_class('suggested-action')
        end
      end

      def cycle_repeat_mode
        case @player.repeat_mode
        when :off
          @player.repeat_mode = :all
        when :all
          @player.repeat_mode = :one
        when :one
          @player.repeat_mode = :off
        end
        update_repeat_button_icon
        update_controls
      end

      def update_controls
        has_tracks = !@player.playlist.empty?
        playlist = @player.playlist
        is_stopped = @player.stopped?
        live = live_stream?

        @play_pause_button.sensitive = has_tracks
        @stop_button.sensitive = !is_stopped
        @next_button.sensitive = has_tracks && (playlist.has_next? || @player.repeat_mode != :off)
        @previous_button.sensitive = has_tracks
        @progress_scale.sensitive = has_tracks && !is_stopped && !live
        @volume_scale.sensitive = true
      end

      def update_progress(position, duration)
        live = live_stream? || duration.to_f <= 0 && @player.playing?
        @position_label.text = format_time(position)
        @duration_label.text = live ? 'Live' : format_time(duration)

        # While the user is dragging the slider, position updates from the
        # engine would yank it back out from under them.
        return if @seeking

        if duration.to_f.positive? && !live_stream?
          @progress_scale.set_range(0, duration)
          @progress_scale.value = position
        else
          @progress_scale.set_range(0, 100)
          @progress_scale.value = 0
        end
      end

      def live_stream?
        track = @player.playlist.current_track
        return false unless track

        uri = track.file_path.to_s
        duration = track.duration.to_f
        duration <= 0 && uri.match?(%r{\Ahttps?://}i)
      end

      def format_time(seconds)
        return '0:00' if seconds.nil? || seconds.negative?

        total = seconds.to_i
        hours, remainder = total.divmod(3600)
        minutes, secs = remainder.divmod(60)
        if hours.positive?
          format('%d:%02d:%02d', hours, minutes, secs)
        else
          format('%d:%02d', minutes, secs)
        end
      end

      def refresh_volume_display
        unless @updating_volume
          @updating_volume = true
          @volume_scale.value = @player.volume
          @updating_volume = false
        end
        refresh_volume_label
        refresh_mute_button
      end

      def refresh_volume_label
        @volume_value_label.text = @player.muted? ? 'Muted' : "#{@player.volume.to_i}%"
      end

      def refresh_mute_button
        return unless @mute_button

        @updating_mute = true
        @mute_button.active = @player.muted?
        @mute_button.icon_name = if @player.muted?
                                   'audio-volume-muted-symbolic'
                                 else
                                   'audio-volume-high-symbolic'
                                 end
        @mute_button.tooltip_text = @player.muted? ? 'Unmute' : 'Mute'
        @updating_mute = false
      end
    end
  end
end
