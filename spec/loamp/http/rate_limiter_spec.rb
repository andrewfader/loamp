# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Http::RateLimiter do
  # A clock the spec drives by hand, so a one-second interval costs nothing to
  # prove. Every sleep the limiter asks for is recorded and then applied to the
  # clock, which is exactly what a real sleep would do.
  let(:now) { [0.0] }
  let(:slept) { [] }

  subject(:limiter) do
    described_class.new(
      interval: 1.0,
      clock: -> { now.first },
      sleeper: ->(seconds) { slept << seconds; now[0] += seconds }
    )
  end

  it 'lets the first caller straight through' do
    limiter.throttle { :done }

    expect(slept).to be_empty
  end

  it 'waits out the rest of the interval for the next caller' do
    limiter.throttle { :first }
    now[0] += 0.25

    limiter.throttle { :second }

    expect(slept).to contain_exactly(be_within(0.001).of(0.75))
  end

  it 'does not wait when the interval has already passed' do
    limiter.throttle { :first }
    now[0] += 5.0

    limiter.throttle { :second }

    expect(slept).to be_empty
  end

  it 'returns whatever the block returned' do
    expect(limiter.throttle { :result }).to eq(:result)
  end

  it 'spaces out a run of calls' do
    5.times { limiter.throttle { :tick } }

    expect(now.first).to be_within(0.001).of(4.0)
  end

  # Lookups run on worker threads, so the gate has to hold across them.
  it 'holds across threads' do
    real = described_class.new(interval: 0.05)
    started = Queue.new

    threads = 3.times.map do
      Thread.new { real.throttle { started << Process.clock_gettime(Process::CLOCK_MONOTONIC) } }
    end
    threads.each(&:join)

    times = Array.new(3) { started.pop }.sort
    expect(times.last - times.first).to be >= 0.09
  end
end
