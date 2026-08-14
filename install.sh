#!/bin/bash

# LOAMP Installation Script for Ubuntu/Debian

echo "Installing LOAMP - Linux Open Audio Music Player"
echo "================================================"

# Update package lists
echo "Updating package lists..."
sudo apt-get update

# Install system dependencies
echo "Installing system dependencies..."
sudo apt-get install -y \
    ruby \
    ruby-dev \
    libgtk-4-dev \
    libadwaita-1-dev \
    gir1.2-adw-1 \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libtag1-dev \
    build-essential \
    pkg-config

# GStreamer decoders. Playback happens in-process through playbin3, so no
# external command line player is needed.
echo "Installing GStreamer codecs..."
sudo apt-get install -y \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-pipewire

# Install bundler if not present
echo "Installing bundler..."
gem install bundler --user-install

# Install Ruby gems
echo "Installing Ruby dependencies..."
bundle install

echo "Installation complete!"
echo ""
echo "To run LOAMP:"
echo "  ruby loamp.rb"
echo ""
echo "Or make it executable:"
echo "  chmod +x loamp.rb"
echo "  ./loamp.rb"
