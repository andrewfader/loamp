# frozen_string_literal: true

require 'fileutils'

module Loamp
  module Podcast
    class Downloader
      def initialize(client: Http::Client.new)
        @client = client
      end

      def download(url, destination)
        existing = File.file?(destination) ? File.size(destination) : 0
        headers = existing.positive? ? { 'Range' => "bytes=#{existing}-" } : {}
        response = @client.get(url, headers: headers)
        return destination if already_complete?(response, existing)
        return false unless response.success?

        FileUtils.mkdir_p(File.dirname(destination))
        mode = response.status == 206 && existing.positive? ? 'ab' : 'wb'
        File.open(destination, mode) { |file| file.write(response.body.to_s) }
        destination
      rescue SystemCallError, IOError
        false
      end

      private

      # A completed file asked for bytes past its end: the server answers 416,
      # which is success for our purposes rather than a failed download.
      def already_complete?(response, existing)
        existing.positive? && response.status == 416
      end
    end
  end
end
