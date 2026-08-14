# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::PlaybackSettings do
  let(:path) { File.join(AudioFixtures.fixture_dir, "settings-#{SecureRandom.hex(4)}.json") }

  after { FileUtils.rm_f(path) }

  it 'starts with safe processing defaults' do
    settings = described_class.new(path: path)
    expect(settings.to_h).to eq(described_class::DEFAULTS)
  end

  it 'persists choices across instances' do
    settings = described_class.new(path: path)
    settings.replaygain_mode = :album
    settings.eq_preset = :rock
    settings.save

    expect(described_class.new(path: path).to_h)
      .to eq(replaygain_mode: :album, eq_preset: :rock, crossfade_seconds: 0.0)
  end

  it 'falls back safely from a corrupt file' do
    File.write(path, '{not json')
    expect(described_class.new(path: path).to_h).to eq(described_class::DEFAULTS)
  end
end
