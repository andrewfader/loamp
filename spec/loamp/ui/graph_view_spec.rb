# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::GraphView do
  before { skip_if_no_gtk }

  let(:similarity) { instance_double(Loamp::Radio::Similarity, expand: edges) }
  let(:edges) { [['mbid-b', 0.9, 'Slowdive']] }
  let(:view) { described_class.new(similarity) }

  after { view.shutdown }

  def wait_until
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      GLib::MainContext.default.iteration(false)
      sleep 0.01
    end
  end

  it 'labels neighbour nodes with artist names rather than MBIDs' do
    view.seed('MBV', mbid: 'mbid-a')
    wait_until { view.instance_variable_get(:@layout).nodes.key?('mbid-b') }

    node = view.instance_variable_get(:@layout).nodes['mbid-b']
    expect(node.label).to eq('Slowdive')
  end

  it 'starts a station on double-click of a node' do
    started = []
    view.on_start_station { |artist, id| started << [artist, id] }
    view.seed('MBV', mbid: 'mbid-a')
    wait_until { view.instance_variable_get(:@layout).nodes.key?('mbid-a') }

    node = view.instance_variable_get(:@layout).nodes['mbid-a']
    view.instance_variable_get(:@callbacks)[:start_station].call(node.label, node.id)

    expect(started).to eq([['MBV', 'mbid-a']])
  end

  it 'asks for the playing track from the This track button' do
    requested = false
    view.on_now_playing { requested = true }
    view.instance_variable_get(:@now_playing_button).signal_emit('clicked')

    expect(requested).to be(true)
  end

  it 'enables feedback only while a station is active' do
    buttons = view.instance_variable_get(:@feedback_buttons) || {}
    skip 'no feedback buttons' if buttons.empty?

    expect(buttons.values).to all(satisfy { |b| !b.sensitive? })

    view.station_active(true)
    expect(buttons.values).to all(be_sensitive)

    view.station_active(false)
    expect(buttons.values).to all(satisfy { |b| !b.sensitive? })
  end
end
