# frozen_string_literal: true

require 'gtk4'

RSpec.configure do |config|
  config.before(:suite) do
    # Check if we have a display available
    # Initialize GTK4 application for testing
    begin
      # Create a test application to ensure GTK initializes properly
      @test_app = Gtk::Application.new('org.loamp.test', :flags_none)
      
      # Don't run the app, just ensure it can be created
      puts "GTK4 initialized successfully for testing with display: #{ENV['WAYLAND_DISPLAY'] || ENV['DISPLAY']}"
      puts "Using GDK backend: #{ENV['GDK_BACKEND'] || 'auto'}"
      
      # Test basic widget creation
      Gtk::Label.new('GTK Test')
      puts "GTK widget creation successful"
      
    rescue StandardError => e
      puts "Error initializing GTK4: #{e.message}"
      puts "Make sure you have a working display and GTK4 is properly installed"
      warn "GTK test setup unavailable: #{e.message}"
    end
  end

  config.after do
    Gtk::Window.list_toplevels.each(&:destroy)
    context = GLib::MainContext.default
    context.iteration(false) while context.pending?
  rescue StandardError
    nil
  end

  config.after(:suite) do
    @test_app = nil
  end
end

# Helper method to check if GTK is available for tests
def gtk_available?
  return @gtk_available if defined?(@gtk_available)

  @gtk_available = begin
    # Quick check for display
    return false unless ENV['WAYLAND_DISPLAY'] || ENV['DISPLAY']
    
    # Try to create a simple widget
    Gtk::Label.new('test')
    true
  rescue StandardError
    false
  end
end

# Skip GTK tests if GTK is not available
def skip_if_no_gtk
  skip 'GTK not available - requires real display (Wayland or X11)' unless gtk_available?
end
