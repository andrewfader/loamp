# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

# Feature: Radio browse includes recently played stations.
RSpec.describe 'Radio recent stations', :feature do
  before { skip_if_no_gtk }

  let(:station) do
    Loamp::Radio::Station.new(
      id: 'kexp', name: 'KEXP', stream_uri: 'https://radio.test/live',
      country: 'United States', language: 'English', tags: ['indie'],
      codec: 'AAC', bitrate: 128
    )
  end
  let(:browser) { instance_double(Loamp::Radio::Browser, search: [], popular: []) }
  let(:playlist) { Loamp::Playlist.new }
  let(:player) { Loamp::Player.new(playlist, engine: AudioFixtures.silent_engine) }
  let(:store_path) { File.join(AudioFixtures.fixture_dir, "radio-feat-#{SecureRandom.hex(4)}.json") }
  let(:store) { Loamp::Radio::Store.new(path: store_path) }
  let(:view) { Loamp::UI::RadioView.new(browser, playlist, player, store: store) }

  after do
    view.shutdown
    player.engine.shutdown
    FileUtils.rm_f(store_path)
  end

  scenario 'playing a station records it for Recent' do
    allow(browser).to receive(:search).and_return([station])
    view.search_for('kexp')
    wait_until { view.visible_stations.any? }
    allow(player).to receive(:play)

    view.play_station(0)
    view.show_history

    expect(view.visible_stations.map(&:name)).to include('KEXP')
  end
end
