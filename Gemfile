# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.2'

gem 'gtk4', '~> 4.2'

# Audio playback pipeline
gem 'gstreamer', '~> 4.3'

# Metadata: taglib covers mp3/flac/ogg/opus/m4a plus embedded artwork
gem 'taglib-ruby', '~> 2.0'

# Library index. Needs an SQLite built with FTS5, which the packaged gem is.
gem 'sqlite3', '~> 2.0'

# Standards-compliant RSS/Atom and OPML parsing for podcast subscriptions.
gem 'rexml', '~> 3.4'

group :development, :test do
  gem 'rake', '~> 13.0'
  gem 'rspec', '~> 3.12'
  gem 'rubocop', '~> 1.0'
  gem 'rubocop-performance', '~> 1.0'
  gem 'rubocop-rspec', '~> 3.0'
end

group :test do
  gem 'factory_bot', '~> 6.2'
  gem 'faker', '~> 3.2'
  gem 'ostruct', '~> 0.6'
  gem 'rspec-mocks', '~> 3.12'
  gem 'simplecov', '>= 0.22'
end
