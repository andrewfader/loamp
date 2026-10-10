# frozen_string_literal: true

module Loamp
  module UI
    # Menu model and actions for persistent ReplayGain/EQ/crossfade choices.
    #
    # Each group is one stateful action with a string target, which is what
    # makes GTK draw the entries as radio items with the current choice
    # marked. A menu that offers eight EQ presets without saying which one
    # is on is a menu that gets clicked twice.
    module PlaybackMenu
      CROSSFADE_CHOICES = [0, 3, 6, 9, 12].freeze

      module_function

      def append_to(menu)
        menu.append_submenu('ReplayGain', replaygain)
        menu.append_submenu('Equalizer', equalizer)
        menu.append_submenu('Crossfade (next launch)', crossfade)
      end

      def install_actions(group, player)
        add_radio(group, 'replaygain', player.replaygain_mode) do |mode|
          player.replaygain_mode = mode.to_sym
        end
        add_radio(group, 'eq', player.eq_preset) do |preset|
          player.eq_preset = preset.to_sym
        end
        add_radio(group, 'crossfade', player.crossfade_seconds.to_f.round) do |seconds|
          player.crossfade_seconds = seconds.to_i
        end
      end

      def replaygain
        Gio::Menu.new.tap do |menu|
          menu.append('Off', 'win.replaygain::off')
          menu.append('Track gain', 'win.replaygain::track')
          menu.append('Album gain', 'win.replaygain::album')
        end
      end

      def equalizer
        Gio::Menu.new.tap do |menu|
          AudioEngine::EQ_PRESETS.each_key do |preset|
            menu.append(preset.to_s.tr('_', ' ').capitalize, "win.eq::#{preset}")
          end
        end
      end

      def crossfade
        Gio::Menu.new.tap do |menu|
          CROSSFADE_CHOICES.each do |seconds|
            label = seconds.zero? ? 'Off' : "#{seconds} seconds"
            menu.append(label, "win.crossfade::#{seconds}")
          end
        end
      end

      def add_radio(group, name, initial)
        action = Gio::SimpleAction.new(name, GLib::VariantType.new('s'),
                                       GLib::Variant.new(initial.to_s))
        action.signal_connect('activate') do |source, parameter|
          value = parameter.respond_to?(:value) ? parameter.value : parameter
          source.state = GLib::Variant.new(value.to_s)
          yield value.to_s
        end
        group.add_action(action)
      end
    end
  end
end
