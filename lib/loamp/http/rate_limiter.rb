# frozen_string_literal: true

module Loamp
  module Http
    # Spaces requests out so a shared service is never asked for two things at
    # once.
    #
    # MusicBrainz allows roughly one request a second and enforces it, first
    # with 503s and eventually by blocking the client outright, so the polite
    # thing and the working thing are the same thing here. One limiter is
    # shared by every caller of a given service, and callers run on worker
    # threads, so the gate has to hold across threads.
    class RateLimiter
      MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      attr_reader :interval

      # The clock and the sleeper are injectable so a spec can prove the
      # spacing without spending real seconds proving it.
      def initialize(interval:, clock: MONOTONIC, sleeper: nil)
        @interval = interval.to_f
        @clock = clock
        @sleeper = sleeper || ->(seconds) { sleep(seconds) }
        @mutex = Mutex.new
        @last = nil
      end

      # Waits until a full interval has passed since the previous caller was
      # let through, then runs the block.
      #
      # The block runs outside the lock, so requests overlap in flight but
      # still *start* an interval apart — which is what a rate limit counts.
      # Holding the lock across the request would serialise on the slowest
      # response instead.
      def throttle
        @mutex.synchronize do
          wait_out_remaining
          @last = @clock.call
        end

        yield
      end

      private

      def wait_out_remaining
        return unless @last

        remaining = @interval - (@clock.call - @last)
        @sleeper.call(remaining) if remaining.positive?
      end
    end
  end
end
