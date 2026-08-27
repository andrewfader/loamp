# frozen_string_literal: true

require 'spec_helper'

# Feature: Discover station start refuses to wipe the queue when nothing matches.
RSpec.describe 'Discover station start', :feature do
  before { skip_if_no_gtk }

  let(:playlist) { Loamp::Playlist.new }
  let(:engine) { AudioFixtures.silent_engine }
  let(:player) { Loamp::Player.new(playlist, engine: engine) }
  let(:library) { Loamp::Library.new(path: Loamp::Library::IN_MEMORY) }
  let(:graph) { Loamp::Radio::GraphStore.new(path: ':memory:') }
  # Plain object — no rspec-mocks lifecycle. GraphView may expand on a worker
  # thread after the example ends.
  let(:similarity) do
    Class.new do
      def expand(**) = []
      def local?(*) = false
    end.new
  end
  let(:windows) { [] }

  after do
    windows.each do |window|
      window.shutdown
      window.destroy
    end
    context = GLib::MainContext.default
    20.times do
      context.iteration(false) while context.pending?
      sleep 0.01
    end
    engine.shutdown
    library.close
  end

  def build_window
    Loamp::UI::MainWindow.new(
      player, playlist,
      library: library,
      radio_services: [similarity, graph]
    ).tap { |w| windows << w }
  end

  scenario 'starting a station with no matching library tracks keeps the queue' do
    playlist.add_track(AudioFixtures.sample_mp3)
    window = build_window
    notices = []
    allow(window).to receive(:notify) { |msg| notices << msg }

    window.send(:start_themed_station, 'Nobody', nil)

    expect(playlist.size).to eq(1)
    expect(notices.last).to include('No local tracks match')
  end

  scenario 'feedback without an active station asks the listener to start one' do
    window = build_window
    notices = []
    allow(window).to receive(:notify) { |msg| notices << msg }

    window.send(:steer_station, :up)

    expect(notices.last).to include('Start a station')
  end
end
