# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::CrossfadeEngine do
  def available?
    Gst::ElementFactory.find('interaudiosink') && Gst::ElementFactory.find('interaudiosrc')
  end

  let(:settings_path) { File.join(AudioFixtures.fixture_dir, "xfade-#{SecureRandom.hex(4)}.json") }
  let(:settings) { Loamp::PlaybackSettings.new(path: settings_path) }
  let(:engine) do
    described_class.new(crossfade_seconds: 1, audio_sink: 'fakesink sync=false',
                        settings: settings)
  end

  before { skip 'interaudio elements are unavailable' unless available? }

  after do
    engine.shutdown
    FileUtils.rm_f(settings_path)
  end

  it 'starts stopped with a cubic volume curve' do
    expect(engine.state).to eq(:stopped)
    engine.volume = 50
    expect(engine.raw_volume).to be_within(0.001).of(0.125)
  end

  it 'mutes without changing the stored volume' do
    engine.volume = 80
    engine.muted = true
    expect(engine).to be_muted
    expect(engine.volume).to eq(80)
    expect(engine.raw_volume).to eq(0.0)
  end

  it 'loads a URI and reports remaining time as infinite until duration is known' do
    engine.load(AudioFixtures.tone(seconds: 1, name: 'crossfade.wav'))
    expect(engine.uri).to include('file://')
    expect(engine.send(:remaining)).to eq(Float::INFINITY)
  end

  it 'clamps the crossfade window' do
    engine.crossfade_seconds = 99
    expect(engine.crossfade_seconds).to eq(12)
    engine.crossfade_seconds = 0
    expect(engine.crossfade_seconds).to eq(0.1)
  end

  describe 'visualizer presets' do
    it 'has nothing to cycle when the visualizer plugin has no presets' do
      skip 'no visualization plugin installed' unless engine.visualizer_name

      expect(engine.visualizer_presets.paths).to be_empty
      expect(engine.next_visualizer_preset).to be_nil
    end

    # A preset change restarts the plugin element mid-stream, so the important
    # part is that audio keeps flowing, the valve reopens and the bus stays
    # quiet once the bounce has finished.
    it 'restarts the running visualizer branch without disturbing playback' do
      skip 'no visualization plugin installed' unless engine.visualizer_name

      errors = []
      engine.on_error { |message| errors << message }
      engine.load(AudioFixtures.tone(seconds: 5, name: 'crossfade-presets.wav'))
      engine.play
      engine.enable_visualizer
      settle(1)
      before = engine.position

      expect(engine.send(:restart_visualizer)).to be(true)
      settle(2)

      expect(engine.instance_variable_get(:@visualizer_restart)).not_to be_alive
      expect(engine.instance_variable_get(:@visualizer_valve).get_property('drop')).to be(false)
      expect(engine.position).to be > before
      expect(errors).to be_empty
    end

    it 'leaves a hidden visualizer alone' do
      skip 'no visualization plugin installed' unless engine.visualizer_name

      expect(engine.send(:restart_visualizer)).to be(false)
    end
  end

  # Frames have to be taken off the paintable sink by the main loop, otherwise
  # the visualizer branch stalls with a buffer in hand.
  def settle(seconds)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    context = GLib::MainContext.default
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      engine.pump
      context.iteration(false) while context.pending?
      sleep 0.01
    end
  end
end
