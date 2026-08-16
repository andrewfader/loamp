# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::ProviderView do
  before { skip_if_no_gtk }

  let(:item) do
    Loamp::Provider::Item.new(id: '1', title: 'Song', artist: 'Artist', album: 'Album',
                              playable: true, provider: :music)
  end
  let(:registry) { instance_double(Loamp::Provider::Registry, search: [item], track_for: track) }
  let(:track) { AudioFixtures.track_with(title: 'Song', artist: 'Artist') }
  let(:playlist) { Loamp::Playlist.new }
  let(:player) { Loamp::Player.new(playlist, engine: AudioFixtures.silent_engine) }
  let(:view) { described_class.new(registry, playlist, player) }

  after do
    view.shutdown
    player.engine.shutdown
  end

  def wait_until
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      GLib::MainContext.default.iteration(false)
      sleep 0.01
    end
  end

  it 'searches away from the GTK thread and lists results' do
    expect(view.search('song')).to be(true)
    wait_until { view.instance_variable_get(:@items).any? }

    expect(registry).to have_received(:search).with('song')
    expect(view.instance_variable_get(:@list).first_child).not_to be_nil
  end

  it 'queues a playable result' do
    view.instance_variable_set(:@items, [item])
    allow(player).to receive(:play)

    expect(view.play(0)).to eq(track)
    expect(playlist.current_track).to eq(track)
    expect(player).to have_received(:play)
  end

  it 'notifies when an item cannot be played' do
    unplayable = Loamp::Provider::Item.new(id: '2', title: 'Link', playable: false,
                                           external_url: 'https://music.test/x')
    view.instance_variable_set(:@items, [unplayable])
    allow(registry).to receive(:track_for).and_return(nil)
    messages = []
    view.on_notify { |message| messages << message }

    expect(view.play(0)).to be(false)
    expect(messages.first).to include('Open this item')
  end

  it 'ignores an empty search' do
    expect(view.search(' ')).to be(false)
  end
end
