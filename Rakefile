# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'rubocop/rake_task'

# Define RSpec task
RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
  spec.rspec_opts = ['--color', '--format documentation']
end

# Define RuboCop task
RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ['--display-cop-names']
end

# Integration tests
desc 'Run integration tests'
task :integration do
  sh 'ruby spec/integration_test.rb'
end

# Test coverage
desc 'Run tests with coverage'
task :coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task[:spec].invoke
end

# All tests
desc 'Run all tests (unit + integration)'
task :test do
  puts 'Running unit tests...'
  Rake::Task[:spec].invoke

  puts "\nRunning integration tests..."
  Rake::Task[:integration].invoke
end

# Quality checks
desc 'Run quality checks (rubocop + tests)'
task :quality do
  puts 'Running RuboCop...'
  Rake::Task[:rubocop].invoke

  puts "\nRunning tests..."
  Rake::Task[:test].invoke
end

# CI task
desc 'Run full CI suite'
task :ci do
  puts 'Running full CI suite...'
  Rake::Task[:quality].invoke
end

# Default task
task default: :test

# Custom tasks for LOAMP
namespace :loamp do
  desc 'Check system dependencies'
  task :deps do
    sh 'ruby test_deps.rb'
  end

  desc 'Install system dependencies'
  task :install do
    sh './install.sh'
  end

  desc 'Run the application'
  task :run do
    sh 'ruby loamp.rb'
  end

  desc 'Generate test report'
  task :test_report do
    sh 'rspec --format html --out spec/reports/test_report.html'
  end
end
