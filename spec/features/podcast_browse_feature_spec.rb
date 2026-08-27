# frozen_string_literal: true

require 'spec_helper'
require 'json'

# Feature: Browse and subscribe to podcasts without knowing a feed URL.
RSpec.describe 'Podcast browsing', :feature do
  before { skip_if_no_gtk }

  let(:store) { Loamp::Podcast::Store.new(path: ':memory:') }
  let(:client) { instance_double(Loamp::Podcast::Client) }
  let(:directory) { instance_double(Loamp::Podcast::Directory) }
  let(:playlist) { Loamp::Playlist.new }
  let(:player) { Loamp::Player.new(playlist, engine: AudioFixtures.silent_engine) }
  let(:listing) do
    Loamp::Podcast::Directory::Listing.new(
      title: 'The Daily',
      artist: 'The New York Times',
      feed_url: 'https://feeds.test/daily',
      genre: 'News',
      collection_id: 42
    )
  end
  let(:episode) do
    Loamp::Podcast::Episode.new(
      guid: 'ep-1', title: 'Monday', media_url: 'https://cdn.test/monday.mp3',
      published_at: Time.utc(2024, 3, 1).to_i, feed_title: 'The Daily', duration: 1200
    )
  end
  let(:feed) do
    Loamp::Podcast::Feed.new(url: listing.feed_url, title: listing.title, episodes: [episode])
  end

  after do
    @view&.shutdown
    player.engine.shutdown
    store.close
  end

  def open_podcasts(popular: [listing])
    allow(directory).to receive(:popular).and_return(popular)
    allow(directory).to receive(:search).and_return([])
    @view = Loamp::UI::PodcastView.new(store, client, playlist, player, directory: directory)
  end

  scenario 'opening Podcasts shows top charts instead of an empty void' do
    open_podcasts
    wait_until { @view.instance_variable_get(:@listings).any? }

    expect(@view.instance_variable_get(:@mode)).to eq(:discover)
    expect(@view.instance_variable_get(:@listings).map(&:title)).to eq(['The Daily'])
    expect(@view.instance_variable_get(:@status).text).to include('double-click to subscribe')
  end

  scenario 'searching by name lists matching shows' do
    open_podcasts(popular: [])
    allow(directory).to receive(:search).with('daily').and_return([listing])

    expect(@view.search_for('daily')).to be(true)
    wait_until { @view.instance_variable_get(:@listings).any? }

    expect(directory).to have_received(:search).with('daily')
    expect(@view.instance_variable_get(:@listings).first.feed_url).to eq(listing.feed_url)
  end

  scenario 'subscribing from the directory loads episodes under My Shows' do
    open_podcasts
    wait_until { @view.instance_variable_get(:@listings).any? }
    allow(client).to receive(:fetch).with(listing.feed_url).and_return(feed)

    @view.subscribe(listing.feed_url)
    wait_until { store.feeds.any? }

    expect(store.feeds.map(&:title)).to eq(['The Daily'])
    @view.show_subscriptions
    expect(@view.instance_variable_get(:@mode)).to eq(:subscriptions)
    expect(@view.instance_variable_get(:@episodes).map(&:guid)).to eq(['ep-1'])
  end

  scenario 'playing an episode queues it and seeks remembered progress' do
    store.subscribe(feed)
    store.remember_position(episode.guid, 45)
    open_podcasts(popular: [])
    @view.show_subscriptions
    allow(player).to receive(:play)
    allow(player).to receive(:playing?).and_return(true)
    allow(player).to receive(:seek)

    track = @view.play_episode(0)

    expect(track.file_path).to eq(episode.media_url)
    expect(playlist.current_track).to equal(track)
    expect(player).to have_received(:play)
  end

  scenario 'unsubscribing removes the show from My Shows' do
    store.subscribe(feed)
    open_podcasts(popular: [])
    @view.show_subscriptions

    @view.send(:unsubscribe, feed.url)

    expect(store.feeds).to be_empty
  end
end
