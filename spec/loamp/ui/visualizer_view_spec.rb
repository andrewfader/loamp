# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::VisualizerView do
  before { skip_if_no_gtk }

  # A stand-in engine: enough of the visualizer surface for the view, with a
  # preset cursor that moves like the real one.
  def fake_engine(names, visualizer_name: 'projectm')
    Class.new do
      def initialize(names, visualizer_name)
        @names = names
        @position = 0
        @visualizer_name = visualizer_name
      end

      attr_reader :visualizer_name

      def visualizer_presets? = !@names.empty?
      def visualizer_preset_count = @names.size
      def current_visualizer_preset = @names[@position]
      def next_visualizer_preset = step(1)
      def previous_visualizer_preset = step(-1)
      def random_visualizer_preset = step(2)
      def enable_visualizer = nil
      def disable_visualizer = true

      def step(delta)
        @position = (@position + delta) % @names.size
        current_visualizer_preset
      end
    end.new(names, visualizer_name)
  end

  def view_for(engine) = described_class.new(instance_double(Loamp::Player, engine: engine))

  let(:view) { view_for(fake_engine(%w[alpha bravo charlie])) }

  def label = view.instance_variable_get(:@preset_label)
  def click(name) = view.instance_variable_get(name).signal_emit('clicked')

  it 'shows the current preset when the engine has presets to cycle' do
    expect(view.instance_variable_get(:@preset_row)).to be_visible
    expect(label.text).to eq('alpha')
    expect(label.tooltip_text).to eq('alpha (3 presets)')
  end

  it 'steps forward through the presets' do
    click(:@preset_next)
    expect(label.text).to eq('bravo')
  end

  it 'steps backwards through the presets, wrapping past the start' do
    click(:@preset_previous)
    expect(label.text).to eq('charlie')
  end

  it 'jumps to another preset at random' do
    click(:@preset_random)
    expect(label.text).to eq('charlie')
  end

  it 'hides the preset row for a visualizer without presets' do
    empty = view_for(fake_engine([]))
    expect(empty.instance_variable_get(:@preset_row)).not_to be_visible
  end

  it 'hides the preset row for an engine that knows nothing about presets' do
    legacy = Class.new do
      def visualizer_name = 'goom'
      def disable_visualizer = true
    end.new
    expect(view_for(legacy).instance_variable_get(:@preset_row)).not_to be_visible
  end
end
