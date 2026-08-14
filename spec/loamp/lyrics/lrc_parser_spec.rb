# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Lyrics::LrcParser do
  subject(:parser) { described_class.new }

  it 'parses, sorts, and scales timestamps of different precision' do
    document = parser.parse("[01:02.5]Later\n[00:03.25]Earlier\n")
    expect(document.lines).to eq([[3.25, 'Earlier'], [62.5, 'Later']])
    expect(document.plain).to eq("Earlier\nLater")
  end

  it 'supports several timestamps on one lyric line' do
    document = parser.parse("[00:01][00:02.00]Again\n")
    expect(document.lines).to eq([[1.0, 'Again'], [2.0, 'Again']])
  end

  it 'keeps unsynchronized lyrics while dropping LRC metadata' do
    document = parser.parse("[ar:Artist]\nA plain line\nAnother\n")
    expect(document.plain).to eq("A plain line\nAnother")
    expect(document).not_to be_synced
  end

  it 'finds the active line for a playback position' do
    document = parser.parse("[00:01]One\n[00:05]Two\n")
    expect(document.line_at(5.5)).to eq([5.0, 'Two'])
  end
end
