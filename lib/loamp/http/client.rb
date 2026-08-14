# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'openssl'

module Loamp
  module Http
    # A small, polite HTTP client for the services the player reads from.
    #
    # Everything that talks to MusicBrainz, the Cover Art Archive, LRCLIB or a
    # scrobbling service goes through here, because they all want the same
    # three things: a User-Agent that says who is calling, a rate limit that is
    # actually honoured, and a failure that is reported rather than raised. A
    # cover that cannot be fetched is not an error the player should care
    # about; it is simply a cover it does not have.
    #
    # Nothing here touches GTK. Callers run it on a worker thread and hand the
    # result back through GLib::Idle.
    class Client
      # MusicBrainz refuses requests without a descriptive User-Agent and asks
      # that it name the application and a way to reach whoever is running it.
      # Packagers can point this at their own contact instead.
      CONTACT = ENV.fetch('LOAMP_CONTACT', 'https://github.com/loamp/loamp')

      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15

      # The Cover Art Archive answers with a redirect to wherever the image
      # actually lives, so following them is not optional.
      MAX_REDIRECTS = 5
      MAX_RETRIES = 1
      REDIRECT_CODES = [301, 302, 303, 307, 308].freeze

      SCHEMES = %w[http https].freeze

      # Everything net/http can raise on the way to a reply. A player that
      # crashes because a laptop lid was closed mid-lookup is a worse player.
      NETWORK_ERRORS = [
        Timeout::Error, SystemCallError, SocketError, IOError,
        OpenSSL::SSL::SSLError, ::Net::HTTPBadResponse, ::Net::ProtocolError
      ].freeze

      # What a caller gets back. Never nil, so there is one shape to handle.
      Response = Struct.new(:status, :body, :content_type, keyword_init: true) do
        def success? = (200..299).cover?(status)

        def not_found? = status == 404

        # Whether the answer says anything about the thing that was asked for.
        # A 404 is a fact worth remembering; a timeout, a 503 from a rate limit
        # or a closed laptop are facts about the network, and caching them as
        # "this album has no cover" would be wrong.
        def definitive? = success? || not_found?

        def json
          JSON.parse(body.to_s)
        rescue JSON::ParserError
          nil
        end
      end

      # Stands for every way a request can fail to produce a reply at all.
      UNREACHABLE = Response.new(status: 0, body: nil, content_type: nil).freeze

      attr_reader :user_agent

      def initialize(user_agent: self.class.default_user_agent, limiter: nil,
                     open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT,
                     max_redirects: MAX_REDIRECTS)
        @user_agent = user_agent
        @limiter = limiter
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @max_redirects = max_redirects
      end

      def self.default_user_agent
        "Loamp/#{Loamp::VERSION} ( #{CONTACT} )"
      end

      # Builds "?a=1&b=2" from a hash, leaving out the keys with nothing in
      # them so callers can pass optional parameters without checking first.
      def self.query(parameters)
        pairs = parameters.reject { |_, value| value.nil? || value.to_s.empty? }
        URI.encode_www_form(pairs)
      end

      def get(url, headers: {})
        uri = URI.parse(url.to_s)
        fetch(uri, headers, @max_redirects)
      rescue URI::InvalidURIError
        UNREACHABLE
      end

      # POST is deliberately not retried: a connection may fail after the
      # server accepted a scrobble, and replaying it would duplicate data.
      def post(url, body:, headers: {})
        uri = URI.parse(url.to_s)
        raw = perform(uri, headers, request_class: ::Net::HTTP::Post, body: body)
        return UNREACHABLE unless raw

        Response.new(status: raw.code.to_i, body: raw.body, content_type: raw['content-type'])
      rescue URI::InvalidURIError
        UNREACHABLE
      end

      private

      def fetch(uri, headers, redirects_left)
        raw = perform_with_retry(uri, headers)
        return UNREACHABLE unless raw

        target = redirect_target(uri, raw)
        return fetch(target, headers, redirects_left - 1) if target && redirects_left.positive?

        Response.new(status: raw.code.to_i, body: raw.body, content_type: raw['content-type'])
      end

      # GET is idempotent, so a request that failed before producing any HTTP
      # response is safe to try once more. Actual HTTP replies — including
      # 404s and 503s — are never retried or disguised.
      def perform_with_retry(uri, headers)
        attempts = 0
        raw = nil

        loop do
          raw = perform(uri, headers)
          attempts += 1
          break if raw || attempts > MAX_RETRIES
        end

        raw
      end

      def redirect_target(uri, raw)
        return nil unless REDIRECT_CODES.include?(raw.code.to_i)

        location = raw['location']
        location && URI.join(uri, location)
      rescue URI::Error
        nil
      end

      def perform(uri, headers, request_class: ::Net::HTTP::Get, body: nil)
        # A redirect can point anywhere, including at a scheme net/http cannot
        # speak. Checking here covers the first request and every hop after it.
        return nil unless SCHEMES.include?(uri.scheme)

        throttled { send_request(uri, headers, request_class, body) }
      rescue *NETWORK_ERRORS
        nil
      end

      def throttled(&)
        @limiter ? @limiter.throttle(&) : yield
      end

      def send_request(uri, headers, request_class, body)
        ::Net::HTTP.start(uri.host, uri.port,
                          use_ssl: uri.scheme == 'https',
                          open_timeout: @open_timeout,
                          read_timeout: @read_timeout) do |http|
          http.request(build_request(uri, headers, request_class, body))
        end
      end

      def build_request(uri, headers, request_class, body)
        request_class.new(uri).tap do |request|
          request['User-Agent'] = @user_agent
          headers.each { |name, value| request[name.to_s] = value.to_s }
          request.body = body if body
        end
      end
    end
  end
end
