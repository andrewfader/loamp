# frozen_string_literal: true

module Loamp
  # Conversion between local paths and file:// URIs.
  #
  # GStreamer wants a URI to play, MPRIS wants a URI for cover art, and both
  # break on the spaces and accents that real music libraries are full of, so
  # the escaping lives in one place.
  module FileUri
    # A scheme followed by "://" means the caller already gave us a URI.
    SCHEME = %r{\A[a-zA-Z][a-zA-Z0-9+.-]*://}

    # Unreserved characters plus "/", which must stay a separator.
    UNSAFE_CHARACTERS = %r{[^A-Za-z0-9\-_.!~*'()/]}

    PERCENT_ESCAPE = /%([0-9A-Fa-f]{2})/

    module_function

    # Passes anything that is already a URI straight through, so callers can
    # hand us a path, a file:// URI, or an http:// stream without checking.
    def for(location)
      text = location.to_s
      return text if text.match?(SCHEME)

      "file://#{escape(File.expand_path(text))}"
    end

    def uri?(location)
      location.to_s.match?(SCHEME)
    end

    # The inverse, for URIs handed to us from outside — MPRIS OpenUri, say.
    # Returns nil for anything that is not a local file.
    def to_path(uri)
      text = uri.to_s
      return text unless text.match?(SCHEME)
      return nil unless text.start_with?('file://')

      unescape(text.delete_prefix('file://').sub(%r{\A[^/]*}, ''))
    end

    def escape(path)
      path.gsub(UNSAFE_CHARACTERS) do |character|
        character.bytes.map { |byte| format('%%%02X', byte) }.join
      end
    end

    def unescape(text)
      text.gsub(PERCENT_ESCAPE) { Regexp.last_match(1).hex.chr }
        .force_encoding(Encoding::UTF_8)
    end
  end
end
