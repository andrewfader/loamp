# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Visualizer Wayland integration' do
  before { skip_if_no_gtk }

  let(:playlist) { Loamp::Playlist.new }
  let(:engine) { AudioFixtures.silent_engine }
  let(:player) { Loamp::Player.new(playlist, engine: engine) }
  let(:view) { Loamp::UI::VisualizerView.new(player) }

  after do
    view.shutdown
    player.stop
    engine.shutdown
  end

  it 'renders a real GStreamer visualization into a GTK paintable' do
    skip 'No GStreamer visualization plugin is installed' unless engine.visualizer_name

    playlist.add_track(AudioFixtures.tone(seconds: 3, name: 'visualizer-e2e.wav'))
    window = Gtk::Window.new
    window.default_width = 760
    window.default_height = 480
    window.child = view
    window.present
    errors = []
    engine.on_error { |message| errors << message }
    view.send(:toggle)
    player.play
    engine.wait_for_state(:playing, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      engine.pump
      settle_gtk(iterations: 1)
      picture = view.instance_variable_get(:@picture)
      break if engine.position > 0.25 && picture.paintable&.current_image
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    end

    picture = view.instance_variable_get(:@picture)
    button = view.instance_variable_get(:@button)
    expect(picture.paintable).not_to be_nil
    expect(picture.paintable.current_image).not_to be_nil
    expect(button.label).to eq('Stop Visualizer')
    expect(engine.position).to be > 0.25
    expect(errors).to be_empty
  ensure
    window&.destroy
  end
end
