# frozen_string_literal: true

module Loamp
  module Lyrics
    class LrcParser
      TIMESTAMP = /\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]/

      def parse(text, source: :lrc)
        lines = text.to_s.each_line.flat_map { |line| timed_lines(line) }
        lines.sort_by!(&:first)
        plain = lines.empty? ? strip_metadata(text) : lines.map(&:last).join("\n")
        Document.new(plain: plain.strip, lines: lines, source: source)
      end

      private

      def timed_lines(line)
        lyric = line.gsub(TIMESTAMP, '').strip
        line.scan(TIMESTAMP).map do |minutes, seconds, fraction|
          [time(minutes, seconds, fraction), lyric]
        end
      end

      def time(minutes, seconds, fraction)
        decimal = fraction.to_s.empty? ? 0 : fraction.to_i / (10**fraction.length).to_f
        (minutes.to_i * 60) + seconds.to_i + decimal
      end

      def strip_metadata(text)
        text.to_s.each_line.grep_v(/\A\[[a-z]+:/i).join
      end
    end
  end
end
