# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Radio::GraphLayout do
  subject(:layout) { described_class.new(random: Random.new(1)) }

  it 'creates nodes once and keeps the first label' do
    layout.add_node('a', label: 'Artist A', local: true)
    layout.add_node('a', label: 'ignored')

    expect(layout.nodes['a'].label).to eq('Artist A')
    expect(layout.nodes['a'].local).to be(true)
  end

  it 'does not duplicate an edge' do
    layout.add_edge('a', 'b', weight: 0.5)
    layout.add_edge('a', 'b', weight: 0.9)

    expect(layout.edges.length).to eq(1)
    expect(layout.edges.first.weight).to eq(0.5)
  end

  it 'moves unpinned nodes during a step' do
    layout.add_node('a', label: 'A')
    layout.add_node('b', label: 'B')
    layout.nodes['a'].x = 0
    layout.nodes['a'].y = 0
    layout.nodes['b'].x = 10
    layout.nodes['b'].y = 0
    layout.add_edge('a', 'b', weight: 1)

    before = [layout.nodes['a'].x, layout.nodes['b'].x]
    layout.step
    after = [layout.nodes['a'].x, layout.nodes['b'].x]

    expect(after).not_to eq(before)
  end

  it 'leaves a pinned node where it is' do
    layout.add_node('a')
    layout.add_node('b')
    layout.nodes['a'].pinned = true
    origin = layout.nodes['a'].x
    layout.step(1)

    expect(layout.nodes['a'].x).to eq(origin)
  end
end
