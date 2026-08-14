# frozen_string_literal: true

require 'taglib'

module Loamp
  # Tag data for a single audio file.
  #
  # TagLib gives a common tag interface across every format plus format
  # specific extras. The common fields come from FileRef; the extras that
  # matter to a music library — album artist, disc numbering, ReplayGain —
  # only live in the format specific tag, so they are read separately.
  #
  # Reading never raises. A file that is missing, locked, or not audio at all
  # still yields a usable object with the filename as its title.
  class Metadata
    # Embedded cover art, kept out of Metadata itself so a library scan of
    # thousands of files does not pull megabytes of JPEG into memory.
    Artwork = Struct.new(:data, :mime_type, keyword_init: true)

    ATTRIBUTES = %i[
      title artist album album_artist composer genre comment lyrics
      track_number track_total disc_number disc_total year
      duration bitrate sample_rate channels
      replaygain_track_gain replaygain_album_gain
      musicbrainz_album_id musicbrainz_artist_id
    ].freeze

    attr_reader(*ATTRIBUTES)

    # "3/12" in a single field, which is how ID3v2 stores numbering.
    COMBINED_NUMBER = %r{\A\s*(\d+)\s*(?:/\s*(\d+))?}

    # ReplayGain values are stored as strings like "-6.50 dB".
    GAIN_VALUE = /(-?\d+(?:\.\d+)?)/

    # MusicBrainz identifiers are UUIDs. Taggers write them in every case and
    # occasionally write something else entirely.
    MBID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

    def initialize(**fields)
      track = split_number(fields[:track])
      disc = split_number(fields[:disc])

      assign_text_fields(fields)

      # Vorbis comments hand back strings, ID3v2 hands back integers.
      @track_number = positive_or_nil(fields[:track_number]) || track.first
      @track_total = positive_or_nil(fields[:track_total]) || track.last
      @disc_number = positive_or_nil(fields[:disc_number]) || disc.first
      @disc_total = positive_or_nil(fields[:disc_total]) || disc.last

      @year = positive_or_nil(fields[:year])
      @duration = fields[:duration].to_f
      @bitrate = fields[:bitrate].to_i
      @sample_rate = fields[:sample_rate].to_i
      @channels = fields[:channels].to_i

      @replaygain_track_gain = parse_gain(fields[:replaygain_track_gain])
      @replaygain_album_gain = parse_gain(fields[:replaygain_album_gain])

      @musicbrainz_album_id = mbid(fields[:musicbrainz_album_id])
      @musicbrainz_artist_id = mbid(fields[:musicbrainz_artist_id])

      @artwork = fields.fetch(:artwork, false)
    end

    def artwork?
      @artwork
    end

    class << self
      def read(file_path)
        Reader.new(file_path).read
      end

      def artwork(file_path)
        Reader.new(file_path).artwork
      end
    end

    private

    def assign_text_fields(fields)
      %i[title artist album album_artist composer genre comment lyrics].each do |name|
        instance_variable_set("@#{name}", presence(fields[name]))
      end
    end

    def presence(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end

    def positive_or_nil(value)
      number = value.to_i
      number.positive? ? number : nil
    end

    def split_number(value)
      match = COMBINED_NUMBER.match(value.to_s)
      return [nil, nil] unless match

      [match[1]&.to_i, match[2]&.to_i]
    end

    def parse_gain(value)
      match = GAIN_VALUE.match(value.to_s)
      match && match[1].to_f
    end

    # An identifier read here goes straight into a request URL, so anything
    # that is not a UUID is dropped rather than passed on to MusicBrainz.
    def mbid(value)
      candidate = value.to_s.strip.downcase
      candidate.match?(MBID) ? candidate : nil
    end
  end
end
