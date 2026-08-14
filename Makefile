# LOAMP Makefile

.PHONY: install deps check clean run help test coverage quality ci

# Default target
help:
	@echo "LOAMP - Linux Open Audio Music Player"
	@echo "======================================"
	@echo ""
	@echo "Available targets:"
	@echo "  install  - Install system dependencies and gems"
	@echo "  deps     - Check dependencies"
	@echo "  run      - Run the music player"
	@echo "  check    - Run dependency check"
	@echo "  test     - Run all tests"
	@echo "  coverage - Run tests with coverage report"
	@echo "  quality  - Run quality checks (rubocop + tests)"
	@echo "  ci       - Run full CI suite"
	@echo "  clean    - Clean bundle cache"
	@echo "  desktop  - Install desktop entry"
	@echo "  help     - Show this help"

# Install dependencies
install:
	@echo "Installing LOAMP dependencies..."
	./install.sh

# Check dependencies
deps check:
	@echo "Checking dependencies..."
	./test_deps.rb

# Run the application
run:
	@echo "Starting LOAMP..."
	./loamp.rb

# Test targets
test:
	@echo "Running all tests..."
	bundle exec rake test

coverage:
	@echo "Running tests with coverage..."
	bundle exec rake coverage

quality:
	@echo "Running quality checks..."
	bundle exec rake quality

ci:
	@echo "Running full CI suite..."
	bundle exec rake ci

# Clean bundle cache
clean:
	@echo "Cleaning bundle cache..."
	bundle clean --force

# Install desktop entry
desktop:
	@echo "Installing desktop entry..."
	@mkdir -p ~/.local/share/applications
	@cp loamp.desktop ~/.local/share/applications/
	@sed -i "s|/home/andrew/workspace/loamp|$(PWD)|g" ~/.local/share/applications/loamp.desktop
	@update-desktop-database ~/.local/share/applications/
	@echo "Desktop entry installed to ~/.local/share/applications/"
