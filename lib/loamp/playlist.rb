# frozen_string_literal: true

module Loamp
  # Manages a collection of tracks
  class Playlist
    # Everything GStreamer can decode and taglib can read tags from.
    AUDIO_EXTENSIONS = %w[
      .mp3 .flac .ogg .oga .opus .wav .m4a .m4b .mp4 .aac .wma .wv .ape .aiff .aif
    ].freeze

    attr_reader :tracks, :current_index
    attr_accessor :shuffle_mode

    def initialize
      @tracks = []
      @current_index = 0
      @shuffle_mode = false
      @shuffle_indices = []
      @shuffle_position = 0
    end

    def add_track(file_path)
      append(Track.new(file_path))
    end

    # Queues a track that has already been built. The library index holds the
    # tags for its whole collection, so queueing an album from it must not
    # send TagLib back to the disk for every file.
    def append(track)
      @tracks << track
      track
    end

    def add_station(station)
      append(station.to_track)
    end

    def add_directory(directory_path)
      return unless Dir.exist?(directory_path)

      audio_extensions = AUDIO_EXTENSIONS

      Dir.glob(File.join(directory_path, '**', '*')).each do |file_path|
        next unless File.file?(file_path)
        next unless audio_extensions.include?(File.extname(file_path).downcase)

        add_track(file_path)
      end
    end

    def current_track
      return nil if @tracks.empty? || @current_index >= @tracks.length

      @tracks[@current_index]
    end

    def next_track
      return nil if @tracks.empty?

      if @shuffle_mode
        @shuffle_position = (@shuffle_position + 1) % @tracks.size
        @current_index = @shuffle_indices[@shuffle_position]
      else
        @current_index = (@current_index + 1) % @tracks.length
      end

      current_track
    end

    def previous_track
      return nil if @tracks.empty?

      if @shuffle_mode
        @shuffle_position = (@shuffle_position - 1) % @tracks.size
        @current_index = @shuffle_indices[@shuffle_position]
      else
        @current_index = (@current_index - 1) % @tracks.length
      end

      current_track
    end

    def set_current_track(index)
      return nil if index.nil? || @tracks.empty? || index.negative? || index >= @tracks.length

      @current_index = index
      current_track
    end

    # The index that follows the current one in play order, without moving the
    # cursor. Gapless playback needs to know what comes next long before the
    # current track finishes, so this must not mutate anything.
    # Returns nil at the end of the playlist unless +wrap+ is set.
    def next_index(wrap: false)
      return nil if @tracks.empty?

      step_index(1, wrap: wrap)
    end

    def previous_index(wrap: false)
      return nil if @tracks.empty?

      step_index(-1, wrap: wrap)
    end

    # Removes one track and keeps the cursor pointing at the same music it was
    # pointing at before, which is what a listener expects when they delete a
    # row above the one that is playing.
    def remove_at(index)
      return nil if index.nil? || index.negative? || index >= @tracks.length

      removed = @tracks.delete_at(index)
      @current_index -= 1 if index < @current_index
      @current_index = @current_index.clamp(0, [@tracks.length - 1, 0].max)

      reshuffle_after_removal
      removed
    end

    def clear
      @tracks.clear
      @current_index = 0
      @shuffle_indices.clear
      @shuffle_position = 0
    end

    def empty?
      @tracks.empty?
    end

    def size
      @tracks.size
    end

    def each(&)
      @tracks.each(&)
    end

    def each_with_index(&)
      @tracks.each_with_index(&)
    end

    def [](index)
      @tracks[index]
    end

    def has_next?
      !@tracks.empty? && @current_index < @tracks.length - 1
    end

    def has_previous?
      !@tracks.empty? && @current_index.positive?
    end

    alias select_track set_current_track

    def enable_shuffle
      @shuffle_mode = true
      @shuffle_indices = (0...@tracks.length).to_a.shuffle
      @shuffle_position = @shuffle_indices.index(@current_index) || 0
    end

    def disable_shuffle
      @shuffle_mode = false
      @shuffle_indices = []
      @shuffle_position = 0
    end

    def shuffle_next
      return nil if @tracks.empty? || !@shuffle_mode

      @shuffle_position = (@shuffle_position + 1) % @shuffle_indices.length
      @current_index = @shuffle_indices[@shuffle_position]
      current_track
    end

    def shuffle_previous
      return nil if @tracks.empty? || !@shuffle_mode

      @shuffle_position = (@shuffle_position - 1) % @shuffle_indices.length
      @current_index = @shuffle_indices[@shuffle_position]
      current_track
    end

    def shuffle=(enabled)
      if enabled
        enable_shuffle
      else
        disable_shuffle
      end
    end

    def shuffle?
      @shuffle_mode
    end

    private

    # The shuffle permutation holds indices, so removing a track invalidates
    # it. Rebuilding keeps shuffle pointing at tracks that still exist.
    def reshuffle_after_removal
      return unless @shuffle_mode

      enable_shuffle
    end

    # Walks the play order by +offset+ positions. In shuffle mode the order is
    # the pre-generated permutation rather than the natural track order.
    def step_index(offset, wrap:)
      order = play_order
      position = order.index(@current_index) || 0
      target = position + offset

      return order[target % order.length] if wrap
      return nil if target.negative? || target >= order.length

      order[target]
    end

    def play_order
      return @shuffle_indices if @shuffle_mode && @shuffle_indices.length == @tracks.length

      (0...@tracks.length).to_a
    end
  end
end
