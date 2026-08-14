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
      @last_retry = 0
    end

    def self.default_path
      root = ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache'))
      File.join(root, 'loamp', 'scrobbles.json')
    end

    def track_started(track)
      @track = track
      @started_at = @clock.call
      @submitted = false
      @services.each do |service|
        Thread.new do
          service.submit(track, listened_at: @started_at, now_playing: true)
        end
      end
    end

    def tick(position, duration)
      queue_current if eligible?(position, duration)
      flush if @clock.call - @last_retry >= RETRY_INTERVAL
    end

    def flush
      @last_retry = @clock.call
      entries = @mutex.synchronize { @queue.map(&:dup) }
      entries.each { |entry| deliver(entry) }
    end

    def shutdown
      save
    end

    private

    def eligible?(position, duration)
      return false if @services.empty? || @submitted || !@track || duration.to_f < 30

      position.to_f >= [duration.to_f / 2, MAX_THRESHOLD].min
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
        queued = @queue.find { |candidate| candidate['listened_at'] == entry['listened_at'] }
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
      @mutex.synchronize { File.write(temporary, JSON.generate(@queue)) }
      File.rename(temporary, @path)
      true
    rescue SystemCallError, IOError
      false
    end
  end
end
