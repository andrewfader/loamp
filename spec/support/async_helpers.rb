# frozen_string_literal: true

# Shared helpers for BDD-style feature specs and GTK idle-driven UI tests.
module AsyncHelpers
  def wait_until(timeout: 5)
    context = GLib::MainContext.default
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      context.iteration(false) while context.pending?
      sleep 0.01
    end

    expect(yield).to be(true)
  end

  alias pump_until wait_until
end

RSpec.configure do |config|
  config.include AsyncHelpers
end
