# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Podcast::Opml do
  let(:feed) { Loamp::Podcast::Feed.new(title: 'Show', url: 'https://show.test/feed', episodes: []) }

  it 'imports unique feed URLs from nested outlines' do
    xml = <<~XML
      <opml version="2.0"><body>
        <outline text="Group">
          <outline type="rss" xmlUrl="https://one.test/feed"/>
          <outline type="rss" xmlUrl="https://one.test/feed"/>
          <outline type="rss" xmlurl="https://two.test/feed"/>
        </outline>
      </body></opml>
    XML

    expect(described_class.import(xml)).to eq(%w[https://one.test/feed https://two.test/feed])
  end

  it 'returns an empty list for broken XML' do
    expect(described_class.import('<opml')).to eq([])
  end

  it 'round-trips subscriptions' do
    xml = described_class.export([feed])

    expect(xml).to include("xmlUrl='https://show.test/feed'")
    expect(described_class.import(xml)).to eq(['https://show.test/feed'])
  end
end
