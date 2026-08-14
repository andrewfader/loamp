#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify LOAMP dependencies

puts 'LOAMP Dependency Check'
puts '====================='

def check_ruby_version
  print 'Ruby version: '
  if RUBY_VERSION >= '3.0.0'
    puts "✓ #{RUBY_VERSION}"
    true
  else
    puts "✗ #{RUBY_VERSION} (requires 3.0.0+)"
    false
  end
end

def check_gem(gem_name)
  print "Checking #{gem_name}: "
  begin
    require gem_name.tr('-', '/')
    puts '✓ Available'
    true
  rescue LoadError
    puts '✗ Not found'
    false
  end
end

def check_command(command)
  print "Checking #{command}: "
  if system("which #{command} > /dev/null 2>&1")
    puts '✓ Available'
    true
  else
    puts '✗ Not found'
    false
  end
end

# Check Ruby version
ruby_ok = check_ruby_version

# Check required gems
puts "\nChecking Ruby gems:"
gtk4_ok = check_gem('gtk4')
gst_gem_ok = check_gem('gst')
taglib_ok = check_gem('taglib')

# libadwaita has no gem; it is loaded from its introspection typelib.
def check_adwaita
  print 'Checking libadwaita: '
  require 'gtk4'
  loader = GObjectIntrospection::Loader.new(Module.new)
  loader.load('Adw')
  puts '✓ Available'
  true
rescue StandardError, LoadError
  puts '✗ Not found (install libadwaita and its GIR data)'
  false
end

adwaita_ok = check_adwaita

puts "\nSummary:"
if ruby_ok && gtk4_ok && gst_gem_ok && taglib_ok && adwaita_ok
  puts '✓ All dependencies satisfied! LOAMP should work correctly.'
  exit 0
else
  puts '✗ Some dependencies are missing. Please run the installation script.'
  exit 1
end
