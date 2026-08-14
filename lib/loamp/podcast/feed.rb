# frozen_string_literal: true

module Loamp
  module Podcast
    Feed = Struct.new(
      :title, :description, :url, :site_url, :image_url, :episodes, keyword_init: true
    )

    Episode = Struct.new(
      :guid, :title, :description, :media_url, :published_at, :duration,
      :image_url, :feed_title, keyword_init: true
    ) do
      def playable?
        %w[http https file].include?(URI.parse(media_url.to_s).scheme)
      rescue URI::InvalidURIError
        false
      end

      def to_track
        Track.new(
          media_url,
          metadata: Metadata.new(title: title, artist: feed_title, album: feed_title,
                                 comment: description, duration: duration),
        )
      end
    end
  end
end
