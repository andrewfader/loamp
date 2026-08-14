# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Podcast::Parser do
  it 'parses RSS podcast metadata and playable episodes' do
    feed = described_class.new.parse(<<~XML, url: 'https://show.test/feed')
      <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
        <channel><title>Example Show</title><description>A show</description>
          <item><guid>ep-1</guid><title>Episode One</title>
            <enclosure url="https://cdn.test/one.mp3" type="audio/mpeg"/>
            <itunes:duration>1:02:03</itunes:duration>
          </item>
        </channel>
      </rss>
    XML

    expect(feed.title).to eq('Example Show')
    expect(feed.episodes.first.media_url).to eq('https://cdn.test/one.mp3')
    expect(feed.episodes.first.duration).to eq(3723)
    expect(feed.episodes.first.to_track.artist).to eq('Example Show')
  end

  it 'parses Atom enclosures' do
    feed = described_class.new.parse(<<~XML)
      <feed xmlns="http://www.w3.org/2005/Atom"><title>Atom Show</title>
        <entry><id>x</id><title>Entry</title>
          <link rel="enclosure" href="https://cdn.test/x.ogg"/>
        </entry>
      </feed>
    XML
    expect(feed.episodes.first.media_url).to eq('https://cdn.test/x.ogg')
  end

  it 'returns nil for malformed or unrelated XML' do
    expect(described_class.new.parse('<broken')).to be_nil
    expect(described_class.new.parse('<html/>')).to be_nil
  end
end
