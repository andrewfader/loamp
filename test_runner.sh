#!/bin/bash

# LOAMP Test Runner Script

set -e

echo "LOAMP Test Runner"
echo "=================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if bundle is installed
if ! command -v bundle &> /dev/null; then
    print_status $RED "Error: bundler is not installed. Please install it first:"
    echo "  gem install bundler"
    exit 1
fi

# Install dependencies
print_status $YELLOW "Installing dependencies..."
bundle install --quiet

# Run dependency check
print_status $YELLOW "Checking system dependencies..."
if ./test_deps.rb; then
    print_status $GREEN "✓ Dependencies check passed"
else
    print_status $YELLOW "⚠ Some dependencies missing (this is OK for testing)"
fi

# Run RuboCop
print_status $YELLOW "Running RuboCop..."
if bundle exec rubocop; then
    print_status $GREEN "✓ RuboCop passed"
else
    print_status $RED "✗ RuboCop failed"
    exit 1
fi

# Run unit tests
print_status $YELLOW "Running unit tests..."
if bundle exec rspec; then
    print_status $GREEN "✓ Unit tests passed"
else
    print_status $RED "✗ Unit tests failed"
    exit 1
fi

# Run integration tests
print_status $YELLOW "Running integration tests..."
if bundle exec ruby spec/integration_test.rb; then
    print_status $GREEN "✓ Integration tests passed"
else
    print_status $RED "✗ Integration tests failed"
    exit 1
fi

print_status $GREEN "🎉 All tests passed!"
echo ""
echo "Test Coverage Report:"
echo "  Unit Tests: $(bundle exec rspec --dry-run | grep -c 'examples'|| echo '0') examples"
echo "  Integration Tests: 4 scenarios"
echo ""
echo "To run individual test suites:"
echo "  bundle exec rspec              # Unit tests only"
echo "  ruby spec/integration_test.rb  # Integration tests only"
echo "  bundle exec rubocop            # Code quality check"
