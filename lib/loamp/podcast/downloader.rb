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
        return false unless response.success?

        FileUtils.mkdir_p(File.dirname(destination))
        mode = response.status == 206 && existing.positive? ? 'ab' : 'wb'
        File.open(destination, mode) { |file| file.write(response.body.to_s) }
        destination
      rescue SystemCallError, IOError
        false
      end
    end
  end
end
