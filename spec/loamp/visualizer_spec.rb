# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Visualizer do
  subject(:visualizer) { described_class.new }

  # Stands in for playbin: remembers every flag written to it.
  def fake_playbin(flags)
    Class.new do
      attr_reader :writes

      def initialize(flags)
        @flags = flags
        @writes = []
      end

      def get_property(_name) = @flags
      def set_property(_name, value) = @writes << (@flags = value)
    end.new(flags)
  end

  describe '#restart' do
    it 'drops and restores the vis flag so the chain is rebuilt' do
      playbin = fake_playbin(Loamp::Visualizer::PLAY_FLAG_VIS | 2)
      visualizer.instance_variable_set(:@playbin, playbin)
      expect(visualizer.restart).to be(true)
      expect(playbin.writes).to eq([2, Loamp::Visualizer::PLAY_FLAG_VIS | 2])
    end

    it 'leaves a stopped visualizer alone' do
      playbin = fake_playbin(2)
      visualizer.instance_variable_set(:@playbin, playbin)
      expect(visualizer.restart).to be(false)
      expect(playbin.writes).to be_empty
    end

    it 'does nothing before the visualizer has been attached' do
      expect(visualizer.restart).to be(false)
    end
  end

  describe '#presets' do
    it 'hands the preset list a way to restart the visualization' do
      presets = visualizer.presets
      expect(presets).to be_a(Loamp::VisualizerPresets)
      expect(presets.instance_variable_get(:@restart).owner).to eq(described_class)
    end
  end
end
