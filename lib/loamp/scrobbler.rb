# frozen_string_literal: true

require 'fileutils'
require 'json'

module Loamp
  class Scrobbler
    MAX_THRESHOLD = 240
    RETRY_INTERVAL = 30

    def initialize(services, path: self.class.default_path, clock: -> { Time.now.to_i })
      @services = services
      @path = path
      @clock = clock
      @queue = load_queue
      @mutex = Mutex.new
      @delivery_mutex = Mutex.new
      @workers = []
      @last_retry = 0
    end

    def self.default_path
      root = ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache'))
      File.join(root, 'loamp', 'scrobbles.json')
    end

    def track_started(track)
      return if @shutdown

      @track = track
      @started_at = @clock.call
      @submitted = false
      @listened = @last_position = 0.0
      return unless track

      started_at = @started_at
      @services.each do |service|
        remember(Thread.new do
          service.submit(track, listened_at: started_at, now_playing: true)
        rescue StandardError
          nil
        end)
      end
    end

    def seeked(position)
      @last_position = position.to_f
    end

    def tick(position, duration)
      return if @shutdown

      if @track
        @listened += [position.to_f - @last_position, 0].max
        @last_position = position.to_f
      end
      queue_current if eligible?(duration)
      return if @clock.call - @last_retry < RETRY_INTERVAL || @flush_thread&.alive?
      return if @mutex.synchronize { @queue.empty? }

      @last_retry = @clock.call
      @flush_thread = Thread.new { flush }
      remember(@flush_thread)
    end

    def flush
      @delivery_mutex.synchronize do
        @last_retry = @clock.call
        entries = @mutex.synchronize { @queue.map(&:dup) }
        entries.each { |entry| deliver(entry) }
      end
    end

    def wait(timeout: 5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      @workers.each do |worker|
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        worker.join([remaining, 0].max)
      end
      @workers.none?(&:alive?)
    end

    def shutdown
      @shutdown = true
      wait
      save
    end

    private

    def remember(worker)
      @workers.select!(&:alive?)
      @workers << worker
    end

    def eligible?(duration)
      return false if @services.empty? || @submitted || !@track || duration.to_f < 30

      @listened >= [duration.to_f / 2, MAX_THRESHOLD].min
    end

    def queue_current
      @submitted = true
      entry = { 'track' => track_fields(@track), 'listened_at' => @started_at,
                'pending' => (0...@services.length).to_a }
      @mutex.synchronize { @queue << entry }
      save
    end

    def deliver(entry)
      track = track_from(entry['track'])
      remaining = Array(entry['pending']).reject do |index|
        @services[index]&.submit(track, listened_at: entry['listened_at'], now_playing: false)
      rescue StandardError
        false
      end
      @mutex.synchronize do
        queued = @queue.find do |candidate|
          candidate['listened_at'] == entry['listened_at'] && candidate['track'] == entry['track']
        end
        next unless queued

        remaining.empty? ? @queue.delete(queued) : queued['pending'] = remaining
      end
      save
    end

    def track_fields(track)
      { 'title' => track.title, 'artist' => track.artist, 'album' => track.album,
        'duration' => track.duration }
    end

    def track_from(fields)
      Track.new('scrobble://history', metadata: Metadata.new(**fields.transform_keys(&:to_sym)))
    end

    def load_queue
      fields = JSON.parse(File.read(@path))
      fields.is_a?(Array) ? fields : []
    rescue JSON::ParserError, SystemCallError
      []
    end

    def save
      FileUtils.mkdir_p(File.dirname(@path))
      temporary = "#{@path}.#{Process.pid}.tmp"
      @mutex.synchronize do
        File.write(temporary, JSON.generate(@queue))
        File.rename(temporary, @path)
      end
      true
    rescue SystemCallError, IOError
      false
    end
  end
end
