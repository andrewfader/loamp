# frozen_string_literal: true

require 'gtk4'

# libadwaita has no dedicated Ruby gem, but it ships a GObject Introspection
# typelib, which is everything ruby-gnome needs to build real bindings at load
# time. This gives us Adw::ApplicationWindow, Adw::ToolbarView, Adw::Toast and
# the rest as ordinary Ruby classes that can be subclassed.
module Adw
  loader = GObjectIntrospection::Loader.new(self)
  loader.load('Adw')

  # Adw::Application performs initialization during startup, but widgets built
  # before that point still need the library primed.
  init if respond_to?(:init)
end
