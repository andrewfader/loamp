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

        @button = Gtk::Button.new(label: 'Start Visualizer')
        @button.halign = :center
        @button.margin_bottom = 12
        @button.signal_connect('clicked') { toggle }
        append(@button)

        name = @player.engine.visualizer_name
        @button.tooltip_text = name ? "Using #{name}" : 'No supported visualizer is installed'
        @button.sensitive = !name.nil?
      end

      def shutdown
        @player.engine.disable_visualizer if @enabled
        @enabled = false
      end

      private

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
      end
    end
  end
end
