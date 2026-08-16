# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::VisualizerPresetControls do
  let(:engine) { Class.new { include Loamp::VisualizerPresetControls }.new }
  let(:presets) do
    instance_double(Loamp::VisualizerPresets, available?: true, count: 7,
                                              current_name: 'alpha', next_preset: 'bravo',
                                              previous_preset: 'charlie', random_preset: 'delta')
  end

  context 'when the engine has no preset list' do
    before { allow(engine).to receive(:visualizer_presets).and_return(nil) }

    it 'reports no presets' do
      expect(engine.visualizer_presets?).to be(false)
      expect(engine.visualizer_preset_count).to eq(0)
    end

    it 'has nothing to cycle' do
      expect(engine.current_visualizer_preset).to be_nil
      expect(engine.next_visualizer_preset).to be_nil
      expect(engine.previous_visualizer_preset).to be_nil
      expect(engine.random_visualizer_preset).to be_nil
    end
  end

  context 'when the engine has a preset list' do
    before { allow(engine).to receive(:visualizer_presets).and_return(presets) }

    it 'reports what is available' do
      expect(engine.visualizer_presets?).to be(true)
      expect(engine.visualizer_preset_count).to eq(7)
      expect(engine.current_visualizer_preset).to eq('alpha')
    end

    it 'passes cycling through to the list' do
      expect(engine.next_visualizer_preset).to eq('bravo')
      expect(engine.previous_visualizer_preset).to eq('charlie')
      expect(engine.random_visualizer_preset).to eq('delta')
    end
  end
end
