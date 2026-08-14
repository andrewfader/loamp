# frozen_string_literal: true

module Loamp
  module Lyrics
    class Resolver
      def initialize(remote: Lrclib.new, parser: LrcParser.new)
        @remote = remote
        @parser = parser
      end

      attr_reader :last_definitive

      def local(track)
        return nil unless track

        embedded = track.lyrics.to_s
        return parse(embedded, :embedded) unless embedded.empty?

        sidecar = sidecar_for(track.file_path)
        parse(File.read(sidecar), :sidecar) if sidecar
      rescue SystemCallError, IOError
        nil
      end

      def remote(track)
        document = @remote.fetch(track)
        @last_definitive = @remote.definitive?
        document
      end

      private

      def parse(text, source)
        @parser.parse(text, source: source)
      end

      def sidecar_for(path)
        return nil if FileUri.uri?(path)

        candidate = "#{path.to_s.delete_suffix(File.extname(path.to_s))}.lrc"
        candidate if File.file?(candidate)
      end
    end
  end
end
