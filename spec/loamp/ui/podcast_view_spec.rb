# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::PodcastView do
  before { skip_if_no_gtk }

  let(:store) { Loamp::Podcast::Store.new(path: ':memory:') }
  let(:client) { instance_double(Loamp::Podcast::Client) }
  let(:directory) { instance_double(Loamp::Podcast::Directory, popular: [], search: []) }
  let(:playlist) { Loamp::Playlist.new }
  let(:player) { Loamp::Player.new(playlist, engine: AudioFixtures.silent_engine) }
  let(:view) { described_class.new(store, client, playlist, player, directory: directory) }
  let(:episode) do
    Loamp::Podcast::Episode.new(guid: 'ep-1', title: 'Episode One',
                                media_url: 'https://cdn.test/one.mp3',
                                published_at: Time.utc(2024, 1, 2).to_i, feed_title: 'Show',
                                duration: 100)
  end
  let(:feed) do
    Loamp::Podcast::Feed.new(url: 'https://show.test/feed', title: 'Show', episodes: [episode])
  end
  let(:listing) do
    Loamp::Podcast::Directory::Listing.new(
      title: 'Show', artist: 'Host', feed_url: 'https://show.test/feed', genre: 'News'
    )
  end

  after do
    view.shutdown
    # Drain idle callbacks from a directory thread that finished after shutdown.
    context = GLib::MainContext.default
    20.times { context.iteration(false) while context.pending?; sleep 0.01 }
    player.engine.shutdown
    store.close
  end

  def wait_until
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      GLib::MainContext.default.iteration(false)
      sleep 0.01
    end
  end

  it 'loads top charts on open so the page is never empty' do
    allow(directory).to receive(:popular).and_return([listing])
    opened = described_class.new(store, client, playlist, player, directory: directory)
    wait_until { opened.instance_variable_get(:@listings).any? }

    expect(opened.instance_variable_get(:@listings).map(&:title)).to eq(['Show'])
    opened.shutdown
  end

  it 'subscribes to a feed off the GTK thread' do
    allow(client).to receive(:fetch).and_return(feed)

    expect(view.subscribe('https://show.test/feed')).to be(true)
    wait_until { store.feeds.any? }

    expect(store.feeds.map(&:title)).to eq(['Show'])
    expect(view.instance_variable_get(:@episodes).map(&:guid)).to eq(['ep-1'])
  end

  it 'searches the directory by name' do
    allow(directory).to receive(:search).with('daily').and_return([listing])

    expect(view.search_for('daily')).to be(true)
    wait_until { view.instance_variable_get(:@listings).any? }

    expect(view.instance_variable_get(:@listings).first.title).to eq('Show')
  end

  it 'queues a playable episode' do
    store.subscribe(feed)
    view.show_subscriptions
    allow(player).to receive(:play)

    track = view.play_episode(0)

    expect(track.file_path).to eq('https://cdn.test/one.mp3')
    expect(playlist.current_track).to equal(track)
    expect(player).to have_received(:play)
  end

  it 'ignores an empty subscribe URL' do
    expect(view.subscribe('  ')).to be(false)
  end
end
