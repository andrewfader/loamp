# frozen_string_literal: true

module Loamp
  module UI
    class VisualizerView < Gtk::Box
      def initialize(player)
        super(:vertical, 8)
        @player = player

        @picture = Gtk::Picture.new
        @picture.content_fit = :contain
        @picture.vexpand = true
        @picture.hexpand = true
        append(@picture)

        append(build_preset_row)

        @button = Gtk::Button.new(label: 'Start Visualizer')
        @button.halign = :center
        @button.margin_bottom = 12
        @button.signal_connect('clicked') { toggle }
        append(@button)

        name = @player.engine.visualizer_name
        @button.tooltip_text = name ? "Using #{name}" : 'No supported visualizer is installed'
        @button.sensitive = !name.nil?
        refresh_presets
      end

      def shutdown
        @player.engine.disable_visualizer if @enabled
        @enabled = false
      end

      private

      # projectM ships thousands of presets; goom has none. The row only shows
      # up when the engine reports presets it can actually switch between.
      def build_preset_row
        @preset_row = Gtk::Box.new(:horizontal, 6)
        @preset_row.halign = :center
        @preset_previous = preset_button('go-previous-symbolic', 'Previous preset') do
          cycle { @player.engine.previous_visualizer_preset }
        end
        @preset_random = preset_button('media-playlist-shuffle-symbolic', 'Random preset') do
          cycle { @player.engine.random_visualizer_preset }
        end
        @preset_next = preset_button('go-next-symbolic', 'Next preset') do
          cycle { @player.engine.next_visualizer_preset }
        end
        @preset_label = build_preset_label
        [@preset_previous, @preset_label, @preset_random, @preset_next]
          .each { |child| @preset_row.append(child) }
        @preset_row
      end

      def build_preset_label
        label = Gtk::Label.new(nil)
        label.ellipsize = :end
        label.width_chars = 24
        label.max_width_chars = 24
        label.add_css_class('dim-label')
        label
      end

      def preset_button(icon_name, tooltip, &)
        button = Gtk::Button.new(icon_name: icon_name)
        button.tooltip_text = tooltip
        button.signal_connect('clicked', &)
        button
      end

      def cycle
        yield
        refresh_presets
      end

      def refresh_presets
        engine = @player.engine
        available = engine.respond_to?(:visualizer_presets?) && engine.visualizer_presets?
        @preset_row.visible = available
        return unless available

        name = engine.current_visualizer_preset
        @preset_label.text = name.to_s
        @preset_label.tooltip_text = "#{name} (#{engine.visualizer_preset_count} presets)"
      end

      def toggle
        if @enabled
          @player.engine.disable_visualizer
          @picture.paintable = nil
          @button.label = 'Start Visualizer'
          @enabled = false
        else
          paintable = @player.engine.enable_visualizer
          return unless paintable

          @picture.paintable = paintable
          @button.label = 'Stop Visualizer'
          @enabled = true
        end
        refresh_presets
      end
    end
  end
end
