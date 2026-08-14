# frozen_string_literal: true

module Loamp
  module CoverArt
    # The Cover Art Archive: cover images keyed by MusicBrainz release id.
    #
    # Free, no key, no rate limit worth the name — and it answers with a
    # redirect to wherever the image actually lives, which is why the client
    # follows them.
    class Archive
      BASE_URL = 'https://coverartarchive.org'

      # Covers are large. A release with no front cover answers 404 quickly;
      # one with a 5MB scan does not, and the point of the whole exercise is a
      # thumbnail in a list row.
      SIZES = {
        small: '-250',
        large: '-500',
        original: '',
      }.freeze

      # Anything bigger than this is not a cover, it is a mistake, and decoding
      # it would cost more than the art is worth.
      MAX_BYTES = 20 * 1024 * 1024

      # Reuses Metadata's shape, so art from the network and art from a tag are
      # the same kind of thing to everything downstream.
      Image = Metadata::Artwork

      # base_url is injectable so specs can point at a local server rather than
      # downloading real cover art to prove a redirect was followed.
      def initialize(client: nil, size: :large, base_url: BASE_URL)
        @client = client || Http::Client.new
        @size = size
        @base_url = base_url
      end

      attr_reader :last_response

      # The front cover for a release, or nil when the archive does not hold
      # one. Never raises.
      def front(release_id, size: @size)
        return nil unless valid_id?(release_id)

        @last_response = @client.get(front_url(release_id, size))
        return nil unless @last_response.success?

        image_from(@last_response)
      end

      # Whether the archive itself answered. A network failure is not evidence
      # that a release has no cover.
      def definitive?
        @last_response ? @last_response.definitive? : false
      end

      def front_url(release_id, size = @size)
        "#{@base_url}/release/#{release_id}/front#{SIZES.fetch(size, '')}"
      end

      private

      # The id goes straight into a path, so anything that is not one is
      # refused here rather than sent.
      def valid_id?(release_id)
        release_id.to_s.match?(Metadata::MBID)
      end

      def image_from(response)
        data = response.body.to_s
        return nil if data.empty? || data.bytesize > MAX_BYTES

        Image.new(data: data, mime_type: mime_type(response))
      end

      # The archive serves what was uploaded, so the type comes from the reply
      # rather than being assumed.
      def mime_type(response)
        type = response.content_type.to_s.split(';').first.to_s.strip.downcase
        type.start_with?('image/') ? type : 'image/jpeg'
      end
    end
  end
end
