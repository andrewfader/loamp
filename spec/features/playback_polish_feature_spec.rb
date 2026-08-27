# frozen_string_literal: true

require 'spec_helper'

# Feature: First-track autoplay and empty-queue affordances.
RSpec.describe 'Playback queue polish', :feature do
  before { skip_if_no_gtk }

  let(:playlist) { Loamp::Playlist.new }
  let(:engine) { AudioFixtures.silent_engine }
  let(:player) { Loamp::Player.new(playlist, engine: engine) }
  let(:windows) { [] }

  after do
    windows.each do |window|
      window.shutdown
      window.destroy
    end
    engine.shutdown
  end

  def build_window
    Loamp::UI::MainWindow.new(player, playlist).tap { |w| windows << w }
  end

  scenario 'adding the first file to an empty idle queue starts playback' do
    window = build_window
    files = Gio::ListStore.new(Gio::File.gtype)
    files.append(Gio::File.new_for_path(AudioFixtures.sample_mp3))
    allow(player).to receive(:play).and_call_original

    window.send(:add_files, files)

    expect(playlist.size).to eq(1)
    expect(player).to have_received(:play)
  end

  scenario 'adding files while already playing does not force a restart' do
    playlist.add_track(AudioFixtures.sample_mp3)
    playlist.set_current_track(0)
    player.play
    engine.wait_for_state(:playing, timeout: 5)
    window = build_window
    files = Gio::ListStore.new(Gio::File.gtype)
    files.append(Gio::File.new_for_path(AudioFixtures.sample_mp3))
    play_calls = 0
    allow(player).to receive(:play) { play_calls += 1 }

    window.send(:add_files, files)

    expect(playlist.size).to eq(2)
    expect(play_calls).to eq(0)
  end

  scenario 'empty queue shows a status page instead of a blank list' do
    window = build_window
    empty = window.instance_variable_get(:@queue_empty)
    list = window.instance_variable_get(:@playlist_view)

    expect(empty).to be_a(Adw::StatusPage)
    # GtkWidget#visible? is is_visible (ancestors must be mapped). The property
    # is what update_queue_empty_state actually toggles.
    expect(empty.get_property('visible')).to be(true)
    expect(list.get_property('visible')).to be(false)

    playlist.add_track(AudioFixtures.sample_mp3)
    window.send(:update_queue_empty_state)

    expect(empty.get_property('visible')).to be(false)
    expect(list.get_property('visible')).to be(true)
  end

  scenario 'mute toggle mirrors player mute state' do
    controls = Loamp::UI::PlayerControls.new(player)
    mute = controls.instance_variable_get(:@mute_button)

    mute.active = true
    expect(player.muted?).to be(true)
    expect(controls.instance_variable_get(:@volume_value_label).text).to eq('Muted')

    mute.active = false
    expect(player.muted?).to be(false)
  end

  scenario 'live streams show Live and disable seeking' do
    stream = Loamp::Track.new(
      'https://radio.test/live.mp3',
      metadata: Loamp::Metadata.new(title: 'Live', duration: 0)
    )
    playlist.append(stream)
    playlist.set_current_track(0)
    controls = Loamp::UI::PlayerControls.new(player)
    allow(player).to receive(:playing?).and_return(true)
    player.instance_variable_set(:@state, :playing)

    controls.send(:update_controls)
    controls.send(:update_progress, 0, 0)

    expect(controls.instance_variable_get(:@duration_label).text).to eq('Live')
    expect(controls.instance_variable_get(:@progress_scale).sensitive?).to be(false)
  end
end
