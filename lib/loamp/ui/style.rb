# frozen_string_literal: true

module Loamp
  module UI
    # Application theming.
    #
    # libadwaita owns light and dark: it recolours every widget and follows the
    # desktop preference on its own. Forcing a scheme is a user choice, not a
    # default, so :system is what ships.
    module Style
      SCHEMES = {
        system: Adw::ColorScheme::DEFAULT,
        light: Adw::ColorScheme::FORCE_LIGHT,
        dark: Adw::ColorScheme::FORCE_DARK,
      }.freeze

      module_function

      def manager
        Adw::StyleManager.default
      end

      def color_scheme=(scheme)
        adwaita_scheme = SCHEMES[scheme.to_s.to_sym]
        manager.color_scheme = adwaita_scheme if adwaita_scheme
      end

      def color_scheme
        SCHEMES.key(manager.color_scheme) || :system
      end

      def dark?
        manager.dark?
      end

      # Application CSS layers on top of the Adwaita stylesheet; it should only
      # ever add what Adwaita does not already provide.
      def load_css(path)
        return unless path && File.exist?(path)

        provider = Gtk::CssProvider.new
        provider.load_from_path(path)

        Gtk::StyleContext.add_provider_for_display(
          Gdk::Display.default,
          provider,
          Gtk::StyleProvider::PRIORITY_APPLICATION,
        )
      rescue StandardError => e
        warn "Could not load stylesheet #{path}: #{e.message}"
      end
    end
  end
end
