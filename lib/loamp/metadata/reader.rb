# frozen_string_literal: true

require 'taglib'

module Loamp
  class Metadata
    # Pulls tags out of a file with TagLib.
    #
    # Two passes: FileRef for the fields every format shares, then a format
    # specific pass for the ones only some formats carry. Any failure along the
    # way degrades to whatever was read so far rather than raising, because a
    # library scan must survive a corrupt file.
    class Reader
      # Front cover, per the ID3v2 APIC picture type table.
      FRONT_COVER = 3

      ID3V2_FRAMES = {
        album_artist: 'TPE2',
        composer: 'TCOM',
        disc: 'TPOS',
      }.freeze

      XIPH_FIELDS = {
        album_artist: ['ALBUMARTIST', 'ALBUM ARTIST'],
        composer: %w[COMPOSER],
        track_number: %w[TRACKNUMBER],
        track_total: %w[TRACKTOTAL TOTALTRACKS],
        disc_number: %w[DISCNUMBER],
        disc_total: %w[DISCTOTAL TOTALDISCS],
        replaygain_track_gain: %w[REPLAYGAIN_TRACK_GAIN],
        replaygain_album_gain: %w[REPLAYGAIN_ALBUM_GAIN],
        musicbrainz_album_id: %w[MUSICBRAINZ_ALBUMID],
        musicbrainz_artist_id: %w[MUSICBRAINZ_ALBUMARTISTID MUSICBRAINZ_ARTISTID],
        lyrics: %w[LYRICS UNSYNCEDLYRICS],
      }.freeze

      MP4_ITEMS = {
        album_artist: 'aART',
        composer: '©wrt',
        # Anything MusicBrainz writes into an MP4 goes in an iTunes freeform
        # atom, spelled exactly like this.
        musicbrainz_album_id: '----:com.apple.iTunes:MusicBrainz Album Id',
        musicbrainz_artist_id: '----:com.apple.iTunes:MusicBrainz Album Artist Id',
        lyrics: '©lyr',
      }.freeze

      # ID3v2 has no frame of its own for any of these; they live in TXXX frames
      # keyed by description. Descriptions are matched upcased because taggers
      # disagree about capitalisation.
      ID3V2_USER_TEXT = {
        'REPLAYGAIN_TRACK_GAIN' => :replaygain_track_gain,
        'REPLAYGAIN_ALBUM_GAIN' => :replaygain_album_gain,
        'MUSICBRAINZ ALBUM ID' => :musicbrainz_album_id,
        'MUSICBRAINZ ALBUM ARTIST ID' => :musicbrainz_artist_id,
      }.freeze

      def initialize(file_path)
        @file_path = file_path.to_s
        @extension = File.extname(@file_path).downcase
      end

      def read
        fields = common_fields.merge(extended_fields)
        # An empty tag is as good as an absent one; either way show the filename.
        fields[:title] = fields[:title].to_s.strip
        fields[:title] = fallback_title if fields[:title].empty?
        Metadata.new(**fields)
      rescue StandardError
        Metadata.new(title: fallback_title)
      end

      # Returns the embedded front cover, or nil when there is not one.
      def artwork
        case @extension
        when '.mp3' then mp3_artwork
        when '.flac' then flac_artwork
        when '.m4a', '.mp4', '.m4b' then mp4_artwork
        end
      rescue StandardError
        nil
      end

      private

      def readable?
        File.file?(@file_path) && File.readable?(@file_path)
      end

      def fallback_title
        File.basename(@file_path, @extension)
      end

      def common_fields
        return {} unless readable?

        TagLib::FileRef.open(@file_path) do |reference|
          next {} if reference.nil? || reference.null?

          tag_fields(reference.tag).merge(audio_fields(reference.audio_properties))
        end || {}
      end

      def tag_fields(tag)
        return {} unless tag

        {
          title: tag.title,
          artist: tag.artist,
          album: tag.album,
          genre: tag.genre,
          comment: tag.comment,
          year: tag.year,
          track_number: positive_or_nil(tag.track),
        }
      end

      def audio_fields(properties)
        return {} unless properties

        {
          duration: properties.length_in_milliseconds / 1000.0,
          bitrate: properties.bitrate,
          sample_rate: properties.sample_rate,
          channels: properties.channels,
        }
      end

      # Fields that only exist in a format's native tag.
      def extended_fields
        return {} unless readable?

        case @extension
        when '.mp3' then id3v2_fields
        when '.flac' then xiph_fields(TagLib::FLAC::File, :xiph_comment)
        when '.ogg', '.oga' then xiph_fields(TagLib::Ogg::Vorbis::File, :tag)
        when '.opus' then xiph_fields(TagLib::Ogg::Opus::File, :tag)
        when '.m4a', '.mp4', '.m4b' then mp4_fields
        else {}
        end
      rescue StandardError
        {}
      end

      def id3v2_fields
        TagLib::MPEG::File.open(@file_path) do |file|
          tag = file.id3v2_tag
          next {} unless tag

          fields = ID3V2_FRAMES.transform_values { |frame| first_frame_text(tag, frame) }
          fields[:lyrics] = first_frame_text(tag, 'USLT')
          fields.merge(user_text_from_txxx(tag)).merge(artwork: artwork?(tag))
        end || {}
      end

      def first_frame_text(tag, frame_id)
        frame = tag.frame_list(frame_id).first
        frame&.to_string
      end

      # ReplayGain and the MusicBrainz identifiers all live in user-defined
      # TXXX frames, so one pass over the list picks up every one of them.
      def user_text_from_txxx(tag)
        tag.frame_list('TXXX').each_with_object({}) do |frame, found|
          name = ID3V2_USER_TEXT[frame.description.to_s.upcase]
          found[name] = frame.field_list.last if name
        end
      end

      def artwork?(tag)
        tag.frame_list('APIC').any?
      end

      def xiph_fields(file_class, tag_method)
        file_class.open(@file_path) do |file|
          comment = file.public_send(tag_method)
          next {} unless comment

          map = comment.field_list_map
          fields = XIPH_FIELDS.each_with_object({}) do |(name, keys), found|
            value = keys.filter_map { |key| map[key]&.first }.first
            found[name] = value if value
          end
          fields.merge(artwork: xiph_artwork?(file, map))
        end || {}
      end

      def xiph_artwork?(file, map)
        return true if file.respond_to?(:picture_list) && file.picture_list.any?

        map.key?('METADATA_BLOCK_PICTURE')
      end

      def mp4_fields
        TagLib::MP4::File.open(@file_path) do |file|
          items = file.tag&.item_map
          next {} unless items

          fields = MP4_ITEMS.each_with_object({}) do |(name, key), found|
            value = items.fetch(key)&.to_string_list&.first
            found[name] = value if value
          end
          fields.merge(artwork: mp4_artwork?(items))
        end || {}
      end

      def mp4_artwork?(items)
        covers = items.fetch('covr')
        !covers.nil? && covers.to_cover_art_list.any?
      rescue StandardError
        false
      end

      def mp3_artwork
        TagLib::MPEG::File.open(@file_path) do |file|
          tag = file.id3v2_tag
          next nil unless tag

          pictures = tag.frame_list('APIC')
          picture = pictures.find { |frame| frame.type == FRONT_COVER } || pictures.first
          next nil unless picture

          Artwork.new(data: picture.picture, mime_type: picture.mime_type)
        end
      end

      def flac_artwork
        TagLib::FLAC::File.open(@file_path) do |file|
          pictures = file.picture_list
          picture = pictures.find { |item| item.type == FRONT_COVER } || pictures.first
          next nil unless picture

          Artwork.new(data: picture.data, mime_type: picture.mime_type)
        end
      end

      def mp4_artwork
        TagLib::MP4::File.open(@file_path) do |file|
          items = file.tag&.item_map
          next nil unless items

          covers = items.fetch('covr')&.to_cover_art_list
          next nil if covers.nil? || covers.empty?

          cover = covers.first
          Artwork.new(data: cover.data, mime_type: mp4_mime_type(cover))
        end
      end

      def mp4_mime_type(cover)
        cover.format == TagLib::MP4::CoverArt::PNG ? 'image/png' : 'image/jpeg'
      rescue StandardError
        'image/jpeg'
      end

      def positive_or_nil(value)
        number = value.to_i
        number.positive? ? number : nil
      end
    end
  end
end
