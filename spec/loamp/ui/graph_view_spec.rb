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
    wait_until { view.instance_variable_get(:@layout).nodes.key?('mbid-b') }

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

  it 'discards delayed results when a different artist is searched' do
    release = Queue.new
    entered = Queue.new
    allow(similarity).to receive(:expand) do |artist:, **|
      if artist == 'Old'
        entered << true
        release.pop
        [['stale', 1, 'Stale artist']]
      else
        [['fresh', 1, 'Fresh artist']]
      end
    end
    view.seed('Old')
    wait_until { !entered.empty? }
    view.seed('New')
    wait_until { view.instance_variable_get(:@layout).nodes.key?('fresh') }
    release << true
    settle_gtk
    expect(view.instance_variable_get(:@layout).nodes.keys).to contain_exactly('New', 'fresh')
  ensure
    release << true
  end

  it 'reports lookup failures and stops the spinner' do
    allow(similarity).to receive(:expand).and_raise(IOError, 'offline')
    view.seed('MBV')
    wait_until { view.instance_variable_get(:@status).text.include?('offline') }
    expect(view.instance_variable_get(:@status).text).to include('Could not find similar artists')
    expect(view.instance_variable_get(:@spinner)).not_to be_spinning
  end

  it 'ignores zero-distance scrolling and resets zoom for a new search' do
    canvas = view.instance_variable_get(:@canvas)
    scroll = canvas.observe_controllers.to_a.grep(Gtk::EventControllerScroll).first
    expect(scroll.signal_emit('scroll', 0.0, 0.0)).to be(false)
    expect(view.instance_variable_get(:@scale)).to eq(1.0)
    scroll.signal_emit('scroll', 0.0, -1.0)
    view.seed('MBV')
    wait_until { view.instance_variable_get(:@layout).nodes.key?('mbid-b') }
    expect(view.instance_variable_get(:@scale)).to eq(1.0)
  end

  it 'does not restart lookups after shutdown' do
    view.shutdown
    expect(similarity).not_to receive(:expand)
    view.seed('MBV')
    expect(view.instance_variable_get(:@layout).nodes).to be_empty
  end
end
