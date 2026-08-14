# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Http::Client do
  subject(:client) { described_class.new }

  let(:server) { StubHttpServer.new }

  after { server.stop }

  describe '#get' do
    it 'returns the body of a successful reply' do
      server.on('/hello', body: 'world')

      response = client.get(server.url_for('/hello'))

      expect(response).to be_success
      expect(response.body).to eq('world')
    end

    it 'reports the content type, which is how an image is named on disk' do
      server.on('/cover', body: 'JPEG', headers: { 'Content-Type' => 'image/jpeg' })

      expect(client.get(server.url_for('/cover')).content_type).to eq('image/jpeg')
    end

    it 'parses a JSON body' do
      server.on('/search', body: '{"count":2}', headers: { 'Content-Type' => 'application/json' })

      expect(client.get(server.url_for('/search')).json).to eq('count' => 2)
    end

    it 'returns nil rather than raising when a body is not the JSON it claimed' do
      server.on('/search', body: '<html>down for maintenance</html>')

      expect(client.get(server.url_for('/search')).json).to be_nil
    end

    # MusicBrainz refuses requests that do not identify their caller.
    it 'identifies itself' do
      server.on('/hello', body: 'ok')

      client.get(server.url_for('/hello'))

      expect(server.requests.first.headers['user-agent']).to eq(described_class.default_user_agent)
    end

    it 'names the application and a contact in its User-Agent' do
      expect(described_class.default_user_agent).to match(%r{\ALoamp/\S+ \( \S+ \)\z})
    end

    it 'sends the headers it was given' do
      server.on('/hello', body: 'ok')

      client.get(server.url_for('/hello'), headers: { 'Accept' => 'application/json' })

      expect(server.requests.first.headers['accept']).to eq('application/json')
    end
  end

  # The Cover Art Archive answers with a redirect to wherever the image really
  # lives, so following them is the whole point rather than an edge case.
  describe 'redirects' do
    it 'follows one to the body it points at' do
      server.on('/front', status: 302, headers: { 'Location' => '/front.jpg' })
      server.on('/front.jpg', body: 'JPEG')

      expect(client.get(server.url_for('/front')).body).to eq('JPEG')
    end

    it 'follows a relative location' do
      server.on('/a/front', status: 307, headers: { 'Location' => 'front.jpg' })
      server.on('/a/front.jpg', body: 'JPEG')

      expect(client.get(server.url_for('/a/front')).body).to eq('JPEG')
    end

    it 'gives up rather than looping forever' do
      server.on('/loop', status: 302, headers: { 'Location' => '/loop' })

      expect(client.get(server.url_for('/loop')).status).to eq(302)
    end

    it 'refuses to follow one out of http' do
      server.on('/away', status: 302, headers: { 'Location' => 'file:///etc/passwd' })

      expect(client.get(server.url_for('/away')).status).to eq(0)
    end
  end

  describe 'failure' do
    it 'retries a transient transport failure once' do
      server.on('/eventually', body: 'ok')
      resilient = described_class.new
      attempts = 0

      allow(resilient).to receive(:send_request).and_wrap_original do |original, *arguments|
        attempts += 1
        raise Errno::ECONNRESET if attempts == 1

        original.call(*arguments)
      end

      expect(resilient.get(server.url_for('/eventually')).body).to eq('ok')
      expect(attempts).to eq(2)
    end

    it 'reports a 404 rather than raising' do
      response = client.get(server.url_for('/nothing/here'))

      expect(response).to be_not_found
      expect(response).not_to be_success
    end

    it 'reports an unreachable host rather than raising' do
      # Port 1 on the loopback interface has nothing listening on it.
      response = client.get('http://127.0.0.1:1/anything')

      expect(response.status).to eq(0)
      expect(response).not_to be_success
    end

    it 'reports a URL that is not one rather than raising' do
      expect(client.get('http://[').status).to eq(0)
    end

    it 'refuses a scheme it cannot speak' do
      expect(client.get('file:///etc/passwd').status).to eq(0)
    end

    it 'gives up on a server that never answers' do
      slow = described_class.new(read_timeout: 0.1)
      server.on('/slow') { sleep 5 }

      expect(slow.get(server.url_for('/slow')).status).to eq(0)
    end
  end

  # Whether a miss is worth writing down depends on who said so: the service,
  # or the network on the way to it.
  describe 'definitive?' do
    it 'is true for a reply that arrived' do
      server.on('/hello', body: 'ok')

      expect(client.get(server.url_for('/hello'))).to be_definitive
    end

    it 'is true for a 404, which is an answer' do
      expect(client.get(server.url_for('/nothing'))).to be_definitive
    end

    it 'is false for a rate limit, which says nothing about the album' do
      server.on('/busy', status: 503, body: 'slow down')

      expect(client.get(server.url_for('/busy'))).not_to be_definitive
    end

    it 'is false when nothing answered at all' do
      expect(client.get('http://127.0.0.1:1/anything')).not_to be_definitive
    end
  end

  describe 'rate limiting' do
    it 'passes every request through the limiter it was given' do
      calls = 0
      limiter = instance_double(Loamp::Http::RateLimiter)
      allow(limiter).to receive(:throttle) { |&block| calls += 1 and block.call }
      throttled = described_class.new(limiter: limiter)
      server.on('/one', body: 'ok')

      throttled.get(server.url_for('/one'))

      expect(calls).to eq(1)
    end

    it 'throttles each hop of a redirect, since each one is a request' do
      calls = 0
      limiter = instance_double(Loamp::Http::RateLimiter)
      allow(limiter).to receive(:throttle) { |&block| calls += 1 and block.call }
      throttled = described_class.new(limiter: limiter)
      server.on('/front', status: 302, headers: { 'Location' => '/front.jpg' })
      server.on('/front.jpg', body: 'JPEG')

      throttled.get(server.url_for('/front'))

      expect(calls).to eq(2)
    end
  end

  describe '.query' do
    it 'builds a query string' do
      expect(described_class.query(artist: 'Boards of Canada', limit: 1))
        .to eq('artist=Boards+of+Canada&limit=1')
    end

    it 'leaves out what was not given, so callers need not check first' do
      expect(described_class.query(artist: 'Autechre', album: nil, mbid: ''))
        .to eq('artist=Autechre')
    end
  end
end
