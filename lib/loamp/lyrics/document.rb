# frozen_string_literal: true

module Loamp
  module Lyrics
    Document = Struct.new(:plain, :lines, :source, keyword_init: true) do
      def synced? = !Array(lines).empty?
      def empty? = plain.to_s.strip.empty? && !synced?

      def line_at(position)
        Array(lines).reverse_each.find { |time, _text| time <= position.to_f }
      end
    end
  end
end
