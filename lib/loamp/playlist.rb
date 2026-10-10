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
      add_to_shuffle(@tracks.length - 1) if @shuffle_mode
      track
    end

    # Put a track immediately after the one that is playing. This is the
    # useful meaning of "play next" even while shuffle is enabled: an explicit
    # listener choice outranks the random order.
    def insert_next(index)
      return nil unless valid_index?(index)
      return index if index == @current_index

      track = @tracks.delete_at(index)
      @current_index -= 1 if index < @current_index
      destination = [@current_index + 1, @tracks.length].min
      @tracks.insert(destination, track)
      remap_shuffle(index, destination)
      prioritize_in_shuffle(destination)
      destination
    end

    # Reorder one queue entry while keeping the cursor attached to the same
    # Track object. Returns the new index, or nil for an invalid move.
    def move(index, offset)
      return nil unless valid_index?(index)

      destination = (index + offset).clamp(0, @tracks.length - 1)
      return index if destination == index

      current = current_track
      @tracks.insert(destination, @tracks.delete_at(index))
      @current_index = @tracks.index(current) || 0
      remap_shuffle(index, destination)
      destination
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

      remove_from_shuffle(index)
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

    # The current track leads the shuffled order, so everything else in the
    # queue is still to come. A permutation that happened to place it last
    # would otherwise end the queue after one track.
    def enable_shuffle
      @shuffle_mode = true
      if @tracks.empty?
        @shuffle_indices = []
      else
        rest = (0...@tracks.length).to_a
        rest.delete(@current_index)
        @shuffle_indices = [@current_index] + rest.shuffle
      end
      @shuffle_position = 0
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

    def valid_index?(index)
      index.is_a?(Integer) && index >= 0 && index < @tracks.length
    end

    # A track added while shuffle is on lands somewhere in what is still to
    # come. Re-dealing the whole order would also reorder what the listener
    # has already seen queued up next.
    def add_to_shuffle(index)
      return enable_shuffle if @shuffle_indices.length != @tracks.length - 1

      current_position = @shuffle_indices.index(@current_index)
      # Nothing was queued before this track, so it is the current one.
      return enable_shuffle unless current_position

      @shuffle_indices.insert(rand((current_position + 1)..@shuffle_indices.length), index)
    end

    def prioritize_in_shuffle(index)
      return unless @shuffle_mode

      @shuffle_indices.delete(index)
      current_position = @shuffle_indices.index(@current_index) || 0
      @shuffle_indices.insert(current_position + 1, index)
      @shuffle_position = current_position
    end

    # The shuffle permutation holds indices, so moving a track means
    # renumbering the entries the move shifted -- without changing the order
    # they will play in.
    def remap_shuffle(from, to)
      return unless @shuffle_mode
      return enable_shuffle if @shuffle_indices.length != @tracks.length

      @shuffle_indices.map! { |index| moved_index(index, from, to) }
      @shuffle_position = @shuffle_indices.index(@current_index) || 0
    end

    # Where a track that sat at +index+ sits once the one at +from+ has been
    # moved to +to+: the moved one lands on +to+ and the ones between shift
    # one step towards the hole it left.
    def moved_index(index, from, to)
      return to if index == from
      return index - 1 if from < to && index.between?(from + 1, to)
      return index + 1 if to < from && index.between?(to, from - 1)

      index
    end

    def remove_from_shuffle(index)
      return unless @shuffle_mode
      return enable_shuffle if @shuffle_indices.length != @tracks.length + 1

      @shuffle_indices.delete(index)
      @shuffle_indices.map! { |other| other > index ? other - 1 : other }
      @shuffle_position = @shuffle_indices.index(@current_index) || 0
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
