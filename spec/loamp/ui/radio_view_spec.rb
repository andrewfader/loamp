# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::RadioView do
  before { skip_if_no_gtk }

  let(:station) do
    Loamp::Radio::Station.new(name: 'KEXP', stream_uri: 'https://radio.test/live',
                              country: 'United States', language: 'English', tags: ['indie'],
                              codec: 'AAC', bitrate: 128)
  end
  let(:browser) { instance_double(Loamp::Radio::Browser, search: [station], popular: []) }
  let(:playlist) { Loamp::Playlist.new }
  let(:player) { Loamp::Player.new(playlist, engine: AudioFixtures.silent_engine) }
  let(:view) { described_class.new(browser, playlist, player) }

  after do
    view.shutdown
    player.engine.shutdown
  end

  def wait_for_result
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      GLib::MainContext.default.iteration(false)
      sleep 0.01
    end
  end

  it 'searches away from the GTK thread and displays the results' do
    view.search_for('indie')
    wait_for_result { view.visible_stations.any? }

    expect(browser).to have_received(:search).with('indie')
    expect(view.visible_stations).to eq([station])
  end

  it 'renders real search results and captures their Wayland render tree' do
    window = Gtk::Window.new
    window.default_width = 760
    window.default_height = 420
    window.child = view
    window.present

    view.search_for('indie')
    wait_for_result { view.visible_stations.any? }
    settle_gtk

    results = view.instance_variable_get(:@results)
    row = results.first_child
    labels = row.first_child.first_child
    expect(labels.first_child.text).to eq('KEXP')
    expect(labels.first_child.next_sibling.text).to include('128 kbps')
    expect(capture_widget(window, 'radio-search-results')).to end_with('.png')
  ensure
    window&.destroy
  end

  it 'populates popular stations when opened' do
    allow(browser).to receive(:popular).and_return([station])
    populated = described_class.new(browser, playlist, player)

    wait_for_result { populated.visible_stations.any? }

    expect(populated.visible_stations).to eq([station])
    populated.shutdown
  end

  it 'queues and starts the chosen station' do
    view.search_for('kexp')
    wait_for_result { view.visible_stations.any? }
    allow(player).to receive(:play)

    track = view.play_station(0)

    expect(track.file_path).to eq('https://radio.test/live')
    expect(playlist.current_track).to equal(track)
    expect(player).to have_received(:play)
  end

  it 'announces playlist and playback changes' do
    changed = false
    notice = nil
    view.on_playlist_changed { changed = true }
    view.on_notify { |message| notice = message }
    view.search_for('kexp')
    wait_for_result { view.visible_stations.any? }
    allow(player).to receive(:play)

    view.play_station(0)

    expect(changed).to be(true)
    expect(notice).to eq('Playing KEXP')
  end

  it 'ignores a result delivered after shutdown' do
    view.shutdown
    expect(view.send(:finish_search, 0, [station])).to be(false)
    expect(view.visible_stations).to be_empty
  end
end
