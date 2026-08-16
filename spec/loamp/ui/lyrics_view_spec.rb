# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::LyricsView do
  before { skip_if_no_gtk }

  let(:view) { described_class.new }
  let(:track) { AudioFixtures.track_with(title: 'Song', artist: 'Artist') }
  let(:document) do
    Loamp::Lyrics::Document.new(plain: "One\nTwo", lines: [[0.0, 'One'], [5.0, 'Two']],
                                source: :lrc)
  end

  it 'highlights the first synced line, including at position zero' do
    view.show_document(track, document)
    view.update_position(0)

    rows = view.instance_variable_get(:@rows)
    expect(rows[0].css_classes).to include('accent')
    expect(rows[1].css_classes).not_to include('accent')
  end

  it 'moves the highlight as playback advances' do
    view.show_document(track, document)
    view.update_position(0)
    view.update_position(5.5)

    rows = view.instance_variable_get(:@rows)
    expect(rows[0].css_classes).not_to include('accent')
    expect(rows[1].css_classes).to include('accent')
  end

  it 'shows unsynced lyrics as selectable text' do
    plain = Loamp::Lyrics::Document.new(plain: 'Just words', lines: [], source: :embedded)
    view.show_document(track, plain)

    expect(view.instance_variable_get(:@plain).text).to eq('Just words')
    expect(view.instance_variable_get(:@stack).visible_child_name).to eq('plain')
  end

  it 'clears the pane' do
    view.show_document(track, document)
    view.clear

    expect(view.instance_variable_get(:@heading).text).to eq('No lyrics loaded')
    expect(view.instance_variable_get(:@rows)).to be_empty
  end
end
