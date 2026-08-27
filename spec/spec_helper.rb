# frozen_string_literal: true

# Coverage is opt-in. Always-on reporting was colliding with GTK teardown on
# Ruby 4 (process exit 139 after a green suite). CI sets COVERAGE=true.
if ENV['COVERAGE']
  require 'simplecov'
  require 'simplecov_json_formatter'

  SimpleCov.command_name 'RSpec'
  SimpleCov.external_at_exit = true
  SimpleCov.start do
    add_filter '/spec/'
    add_group 'Core', 'lib/loamp'
    add_group 'UI', 'lib/loamp/ui'
    minimum_coverage 80
    formatter SimpleCov::Formatter::MultiFormatter.new(
      [
        SimpleCov::Formatter::SimpleFormatter,
        SimpleCov::Formatter::JSONFormatter,
      ]
    )
  end
end

require 'rspec'
require 'gtk4'

require 'base64'
require 'securerandom'
require 'ostruct'
require 'factory_bot'
require 'faker'

# Metadata is read through taglib against real files, so there is nothing to
# mock here any more.

# Require the main library
require_relative '../lib/loamp'

# Require test support files
Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

# Configure RSpec
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  config.before(:suite) do
    FactoryBot.find_definitions
  end

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.define_derived_metadata(file_path: %r{/spec/features/}) do |metadata|
    metadata[:type] = :feature
  end
end
