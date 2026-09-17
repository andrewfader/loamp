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
        return false if response.status == 206 && !valid_range?(response, existing)

        FileUtils.mkdir_p(File.dirname(destination))
        mode = response.status == 206 && existing.positive? ? 'ab' : 'wb'
        File.open(destination, mode) { |file| file.write(response.body.to_s) }
        destination
      rescue SystemCallError, IOError
        false
      end

      private

      # 416 can also mean a partial file is larger than the current resource.
      # Only an exact server-confirmed length proves completion.
      def already_complete?(response, existing)
        existing.positive? && response.status == 416 &&
          response.content_range == "bytes */#{existing}"
      end

      def valid_range?(response, existing)
        range = response.content_range.to_s.match(%r{\Abytes (\d+)-(\d+)/(\d+)\z})
        return false unless range

        first, last, total = range.captures.map(&:to_i)
        first == existing && last >= first && last + 1 == total &&
          response.body.to_s.bytesize == last - first + 1
      end
    end
  end
end
