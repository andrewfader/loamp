# frozen_string_literal: true

module Loamp
  module UI
    module KeyboardShortcuts
      SEEK_STEP_SECONDS = 10
      VOLUME_STEP = 5

      private

      def setup_keyboard_shortcuts
        key_controller = Gtk::EventControllerKey.new
        add_controller(key_controller)
        key_controller.signal_connect('key-pressed') do |_controller, keyval, _keycode, state|
          handle_key_press(keyval, state)
        end
      end

      def handle_key_press(keyval, state)
        ctrl_pressed = state.to_i.anybits?(Gdk::ModifierType::CONTROL_MASK.to_i)
        case keyval
        when Gdk::Keyval::KEY_space then handle_play_pause
        when Gdk::Keyval::KEY_Right then handle_forward(ctrl_pressed)
        when Gdk::Keyval::KEY_Left then handle_backward(ctrl_pressed)
        when Gdk::Keyval::KEY_Up then adjust_volume(VOLUME_STEP)
        when Gdk::Keyval::KEY_Down then adjust_volume(-VOLUME_STEP)
        when Gdk::Keyval::KEY_m then toggle_mute
        else false
        end
      end

      def handle_play_pause
        @player.play_pause
        true
      end

      def handle_forward(ctrl_pressed)
        ctrl_pressed ? @player.next_track : @player.seek(@player.position + SEEK_STEP_SECONDS)
        true
      end

      def handle_backward(ctrl_pressed)
        if ctrl_pressed
          @player.previous_track
        else
          @player.seek([@player.position - SEEK_STEP_SECONDS,
                        0].max)
        end
        true
      end

      def adjust_volume(delta)
        @player.set_volume((@player.volume + delta).clamp(0, 100))
        true
      end

      def toggle_mute
        @player.muted = !@player.muted?
        true
      end
    end
  end
end
