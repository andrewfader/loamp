# frozen_string_literal: true

module Loamp
  class Library
    # Turns what somebody typed into an FTS5 query.
    #
    # FTS5's syntax has operators of its own — quotes, NEAR, AND, a bare `-`
    # or `*` — and a search box is full of them by accident. Rather than
    # rejecting the input, every token is quoted, which makes it literal, and
    # given a trailing `*` so results narrow as the listener keeps typing.
    module Search
      # Anything that is not a letter, digit or apostrophe separates words.
      # Apostrophes stay so "don't" is one token rather than two.
      SEPARATOR = /[^[[:alnum:]]']+/

      module_function

      # nil when there is nothing to search for, which callers read as "show
      # everything" rather than "show nothing".
      def expression(query)
        tokens = terms(query)
        return nil if tokens.empty?

        tokens.map { |token| "\"#{token}\"*" }.join(' ')
      end

      def terms(query)
        query.to_s.split(SEPARATOR).filter_map do |token|
          # A doubled quote is FTS5's own escape; a token cannot contain one
          # after splitting, but the guard costs nothing and the alternative
          # is a syntax error in somebody's search box.
          cleaned = token.gsub('"', '""').strip
          cleaned unless cleaned.empty?
        end
      end
    end
  end
end
