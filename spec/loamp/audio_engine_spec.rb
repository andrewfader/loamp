# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::AudioEngine do
  # A silent sink keeps the suite quiet while still running the real GStreamer
  # pipeline in real time, so positions and end-of-stream behave as in production.
  let(:engine) { described_class.new(audio_sink: 'fakesink sync=true') }
  let(:tone) { AudioFixtures.tone(seconds: 2) }

  after { engine.shutdown }

  describe '#initialize' do
    it 'starts stopped with no track loaded' do
      expect(engine.state).to eq(:stopped)
      expect(engine.uri).to be_nil
    end

    it 'starts at full volume and unmuted' do
      expect(engine.volume).to eq(100)
      expect(engine).not_to be_muted
    end
  end

  describe '#load' do
    it 'converts a local file path into a file URI' do
      engine.load(tone)
      expect(engine.uri).to eq("file://#{tone}")
    end

    it 'preserves a URI that is already absolute' do
      engine.load('https://example.com/stream.mp3')
      expect(engine.uri).to eq('https://example.com/stream.mp3')
    end

    it 'escapes characters that are not URI safe' do
      spaced = AudioFixtures.tone(seconds: 1, name: 'a track with spaces.wav')
      engine.load(spaced)
      expect(engine.uri).to include('%20')
    end

    it 'leaves the engine stopped until playback is requested' do
      engine.load(tone)
      expect(engine.state).to eq(:stopped)
    end
  end

  describe '#play' do
    it 'enters the playing state' do
      engine.load(tone)
      engine.play
      expect(engine.wait_for_state(:playing, timeout: 5)).to be(true)
      expect(engine.state).to eq(:playing)
    end

    it 'advances position while playing' do
      engine.load(tone)
      engine.play
      engine.wait_for_state(:playing, timeout: 5)

      first = engine.position
      sleep 0.6
      expect(engine.position).to be > first
    end

    it 'does nothing when no track is loaded' do
      engine.play
      expect(engine.state).to eq(:stopped)
    end
  end

  describe '#pause' do
    it 'holds the position steady' do
      engine.load(tone)
      engine.play
      engine.wait_for_state(:playing, timeout: 5)
      sleep 0.3
      engine.pause

      paused_at = engine.position
      sleep 0.4
      expect(engine.position).to be_within(0.05).of(paused_at)
      expect(engine.state).to eq(:paused)
    end

    it 'resumes from where it paused' do
      engine.load(tone)
      engine.play
      engine.wait_for_state(:playing, timeout: 5)
      sleep 0.3
      engine.pause
      paused_at = engine.position

      engine.play
      engine.wait_for_state(:playing, timeout: 5)
      sleep 0.3
      expect(engine.position).to be > paused_at
    end
  end

  describe '#stop' do
    it 'resets the position and returns to stopped' do
      engine.load(tone)
      engine.play
      engine.wait_for_state(:playing, timeout: 5)
      sleep 0.3
      engine.stop

      expect(engine.state).to eq(:stopped)
      expect(engine.position).to eq(0)
    end
  end

  describe '#seek' do
    it 'moves playback to the requested position' do
      engine.load(AudioFixtures.sample_mp3)
      engine.play
      engine.wait_for_state(:playing, timeout: 5)

      engine.seek(30)
      expect(engine.position).to be_within(1.0).of(30)
    end

    it 'clamps a negative position to the start' do
      engine.load(AudioFixtures.sample_mp3)
      engine.play
      engine.wait_for_state(:playing, timeout: 5)

      engine.seek(-10)
      expect(engine.position).to be >= 0
    end

    it 'is ignored when nothing is loaded' do
      expect { engine.seek(10) }.not_to raise_error
    end
  end

  describe '#duration' do
    it 'reports the real duration of the stream' do
      engine.load(AudioFixtures.sample_mp3)
      engine.play
      engine.wait_for_state(:playing, timeout: 5)

      expect(engine.duration).to be_within(0.5).of(110.4)
    end

    it 'is zero when nothing is loaded' do
      expect(engine.duration).to eq(0)
    end
  end

  describe '#volume' do
    it 'round trips a value' do
      engine.volume = 40
      expect(engine.volume).to eq(40)
    end

    it 'clamps values outside the supported range' do
      engine.volume = 150
      expect(engine.volume).to eq(100)

      engine.volume = -20
      expect(engine.volume).to eq(0)
    end

    it 'applies a perceptual curve to the underlying pipeline' do
      engine.volume = 50
      # Cubic scale: half the perceived loudness is far below half amplitude.
      expect(engine.raw_volume).to be_within(0.01).of(0.125)
    end

    it 'survives being set before a track is loaded' do
      engine.volume = 25
      engine.load(tone)
      engine.play
      engine.wait_for_state(:playing, timeout: 5)
      expect(engine.volume).to eq(25)
    end
  end

  describe '#muted' do
    it 'mutes without losing the volume setting' do
      engine.volume = 60
      engine.muted = true

      expect(engine).to be_muted
      expect(engine.volume).to eq(60)
    end

    it 'unmutes back to the previous volume' do
      engine.volume = 60
      engine.muted = true
      engine.muted = false

      expect(engine).not_to be_muted
      expect(engine.volume).to eq(60)
    end
  end

  describe 'end of stream' do
    it 'notifies listeners when the track finishes' do
      finished = false
      engine.on_end_of_stream { finished = true }

      engine.load(AudioFixtures.tone(seconds: 1))
      engine.play
      engine.wait_for_end_of_stream(timeout: 8)

      expect(finished).to be(true)
    end

    it 'returns to the stopped state after the stream ends' do
      engine.load(AudioFixtures.tone(seconds: 1))
      engine.play
      engine.wait_for_end_of_stream(timeout: 8)

      expect(engine.state).to eq(:stopped)
    end
  end

  describe 'error handling' do
    it 'reports a failure for a file that does not exist' do
      error = nil
      engine.on_error { |message| error = message }

      engine.load('/nonexistent/definitely-not-here.mp3')
      engine.play
      engine.wait_for_error(timeout: 5)

      expect(error).to be_a(String)
      expect(error).not_to be_empty
    end

    it 'stays stopped rather than crashing on a decode failure' do
      engine.load('/nonexistent/definitely-not-here.mp3')
      engine.play
      engine.wait_for_error(timeout: 5)

      expect(engine.state).to eq(:stopped)
    end
  end

  describe 'gapless playback' do
    it 'asks for the next track before the current one ends' do
      asked = false
      engine.on_about_to_finish { asked = true }

      engine.load(AudioFixtures.tone(seconds: 1))
      engine.play
      engine.wait_for_end_of_stream(timeout: 8)

      expect(asked).to be(true)
    end

    it 'announces when a queued track actually begins' do
      starts = 0
      engine.on_stream_start { starts += 1 }

      engine.load(AudioFixtures.tone(seconds: 1, frequency: 440))
      engine.on_about_to_finish { engine.queue_next(AudioFixtures.tone(seconds: 1, frequency: 880)) }
      engine.play
      engine.wait_for_state(:playing, timeout: 5)

      engine.wait_until_stream_starts(count: 2, timeout: 8)
      expect(starts).to be >= 2
    end

    it 'plays a queued track without returning to stopped' do
      engine.load(AudioFixtures.tone(seconds: 1, frequency: 440))
      engine.on_about_to_finish { engine.queue_next(AudioFixtures.tone(seconds: 2, frequency: 880)) }
      engine.play
      engine.wait_for_state(:playing, timeout: 5)

      sleep 1.5
      expect(engine.state).to eq(:playing)
    end
  end
end
