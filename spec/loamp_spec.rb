# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp do
  describe 'module constants' do
    it 'has a version number' do
      expect(Loamp::VERSION).to eq('1.0.0')
    end
  end

  describe 'module loading' do
    it 'loads all required components' do
      expect(defined?(Loamp::Application)).to be_truthy
      expect(defined?(Loamp::Player)).to be_truthy
      expect(defined?(Loamp::Playlist)).to be_truthy
      expect(defined?(Loamp::Track)).to be_truthy
    end

    it 'loads all UI components' do
      expect(defined?(Loamp::UI::MainWindow)).to be_truthy
      expect(defined?(Loamp::UI::PlayerControls)).to be_truthy
      expect(defined?(Loamp::UI::PlaylistView)).to be_truthy
      expect(defined?(Loamp::UI::TrackInfo)).to be_truthy
    end
  end
end
