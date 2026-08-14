# frozen_string_literal: true

module Loamp
  module UI
    # Menu model and actions for persistent ReplayGain/EQ choices.
    module PlaybackMenu
      module_function

      def append_to(menu)
        menu.append_submenu('ReplayGain', replaygain)
        menu.append_submenu('Equalizer', equalizer)
        menu.append_submenu('Crossfade (next launch)', crossfade)
      end

      def install_actions(group, player)
        PlaybackSettings::REPLAYGAIN_MODES.each do |mode|
          add_action(group, "replaygain-#{mode}") { player.replaygain_mode = mode }
        end
        AudioEngine::EQ_PRESETS.each_key do |preset|
          add_action(group, "eq-#{action_name(preset)}") { player.eq_preset = preset }
        end
        [0, 3, 6, 9, 12].each do |seconds|
          add_action(group, "crossfade-#{seconds}") { player.crossfade_seconds = seconds }
        end
      end

      def replaygain
        Gio::Menu.new.tap do |menu|
          menu.append('Off', 'win.replaygain-off')
          menu.append('Track gain', 'win.replaygain-track')
          menu.append('Album gain', 'win.replaygain-album')
        end
      end

      def equalizer
        Gio::Menu.new.tap do |menu|
          AudioEngine::EQ_PRESETS.each_key do |preset|
            menu.append(preset.to_s.tr('_', ' ').capitalize, "win.eq-#{action_name(preset)}")
          end
        end
      end

      def crossfade
        Gio::Menu.new.tap do |menu|
          [0, 3, 6, 9, 12].each do |seconds|
            label = seconds.zero? ? 'Off' : "#{seconds} seconds"
            menu.append(label, "win.crossfade-#{seconds}")
          end
        end
      end

      def add_action(group, name, &)
        action = Gio::SimpleAction.new(name)
        action.signal_connect('activate', &)
        group.add_action(action)
      end

      def action_name(preset) = preset.to_s.tr('_', '-')
    end
  end
end
