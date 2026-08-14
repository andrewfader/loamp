# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Mpris::Variant do
  describe '.build' do
    it 'builds a string' do
      expect(described_class.build('s', 'Song').to_s).to eq("'Song'")
    end

    it 'builds an int64 from a float, as microsecond positions arrive' do
      expect(described_class.build('x', 1.9e6).to_s).to eq('1900000')
    end

    it 'builds a double from an integer volume' do
      expect(described_class.build('d', 1).to_s).to eq('1.0')
    end

    it 'builds an object path' do
      variant = described_class.build('o', '/org/mpris/MediaPlayer2')

      expect(variant.type.to_s).to eq('o')
    end

    it 'builds a string array' do
      expect(described_class.build('as', %w[Haim]).to_s).to eq("['Haim']")
    end

    it 'builds a dictionary' do
      variant = described_class.build('a{sv}', { 'xesam:title' => ['s', 'Song'] })

      expect(variant.type.to_s).to eq('a{sv}')
    end
  end

  describe '.dictionary' do
    it 'types each value by its signature' do
      variant = described_class.dictionary(
        'mpris:trackid' => ['o', '/track/1'],
        'mpris:length' => ['x', 1_000],
        'xesam:artist' => ['as', ['Haim']]
      )

      expect(variant.to_s).to eq(
        "{'mpris:trackid': <objectpath '/track/1'>, 'mpris:length': <int64 1000>, " \
        "'xesam:artist': <['Haim']>}"
      )
    end

    it 'drops keys whose value is missing rather than sending a null' do
      variant = described_class.dictionary('xesam:title' => ['s', 'Song'],
                                           'xesam:album' => ['s', nil])

      expect(variant.to_s).to eq("{'xesam:title': <'Song'>}")
    end

    it 'still produces a typed dictionary when everything is missing' do
      variant = described_class.dictionary('xesam:title' => ['s', nil])

      expect(variant.type.to_s).to eq('a{sv}')
    end
  end

  describe 'escaping' do
    it 'survives a title containing quotes and backslashes' do
      expect(round_trip(%(a "b" c\\d))).to eq(%(a "b" c\\d))
    end

    it 'survives a title containing a newline' do
      expect(round_trip("a\nb")).to eq("a\nb")
    end

    it 'survives control characters' do
      expect(round_trip("a\u0001b")).to eq("a\u0001b")
    end

    it 'keeps non-ASCII text intact' do
      expect(round_trip('Sigur Rós')).to eq('Sigur Rós')
    end

    it 'drops bytes that are not valid UTF-8 rather than handing them to GLib' do
      tag = (+"Bj\xF6rk").force_encoding(Encoding::ASCII_8BIT)

      expect(round_trip(tag)).to eq('Bjrk')
    end

    it 'escapes a key as carefully as a value' do
      text = described_class.dictionary_text(%(we"ird) => ['s', 'x'])

      expect(text).to eq(%({"we\\"ird": <"x">}))
      expect { GLib::Variant.parse(text, 'a{sv}') }.not_to raise_error
    end
  end

  describe '.literal' do
    it 'spells out the element type of an empty array' do
      expect(described_class.literal('as', [])).to eq('@as []')
    end

    it 'wraps a bare string in a list' do
      expect(described_class.literal('as', 'Haim')).to eq('["Haim"]')
    end

    it 'refuses a signature it cannot serialise' do
      expect { described_class.literal('q', 1) }.to raise_error(ArgumentError, /unsupported/)
    end
  end

  # Handing the escaped text back to GLib's own parser is the only honest
  # check that a value survives the trip, rather than merely looking right.
  def round_trip(value)
    GLib::Variant.parse(described_class.literal('s', value), 's').value
  end
end
