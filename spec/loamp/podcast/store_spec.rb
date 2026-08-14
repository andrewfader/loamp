# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Podcast::Store do
  subject(:store) { described_class.new(path: ':memory:') }

  let(:episode) do
    Loamp::Podcast::Episode.new(guid: 'one', title: 'Episode', media_url: 'https://cdn.test/1.mp3',
                                duration: 120, feed_title: 'Show')
  end
  let(:feed) { Loamp::Podcast::Feed.new(url: 'https://show.test/feed', title: 'Show', episodes: [episode]) }

  after { store.close }

  it 'stores subscriptions and episodes idempotently' do
    2.times { store.subscribe(feed) }
    expect(store.feeds.map(&:title)).to eq(['Show'])
    expect(store.episodes(feed.url).map(&:guid)).to eq(['one'])
  end

  it 'remembers playback position' do
    store.subscribe(feed)
    store.remember_position('one', 42.5)
    expect(store.position('one')).to eq(42.5)
  end

  it 'removes episodes with their subscription' do
    store.subscribe(feed)
    expect(store.unsubscribe(feed.url)).to be(true)
    expect(store.episodes(feed.url)).to be_empty
  end
end
