# frozen_string_literal: true

module Loamp
  module Radio
    # A normalized Radio Browser result. Keeping API field names out of the UI
    # makes it possible to change directory providers without changing playback.
    Station = Struct.new(
      :id, :name, :stream_uri, :homepage, :favicon, :country, :language,
      :tags, :codec, :bitrate, :votes, keyword_init: true
    ) do
      def playable?
        %w[http https].include?(URI.parse(stream_uri.to_s).scheme)
      rescue URI::InvalidURIError
        false
      end

      def label
        details = [country, language].reject { |value| value.to_s.empty? }.join(' · ')
        details.empty? ? name.to_s : "#{name} — #{details}"
      end

      def to_track
        metadata = Metadata.new(
          title: name, artist: country, album: tags&.first,
          genre: tags&.join(', '), bitrate: bitrate
        )
        Track.new(stream_uri, metadata: metadata)
      end
    end
  end
end
