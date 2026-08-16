# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Lastfm do
  let(:http) { instance_double(Loamp::Http::Client) }
  let(:service) do
    described_class.new(api_key: 'KEY', secret: 'SECRET', session_key: 'SESSION',
                        client: http, endpoint: 'https://ws.test/')
  end

  def json_reply(payload)
    Loamp::Http::Client::Response.new(status: 200, body: JSON.generate(payload))
  end

  it 'wraps a single similar artist instead of treating the object as pairs' do
    allow(http).to receive(:get).and_return(json_reply('similarartists' => {
                                                         'artist' => { 'name' => 'Slowdive',
                                                                       'match' => '0.91',
                                                                       'mbid' => 'mbid-1' },
                                                       }))

    expect(service.similar_artists('My Bloody Valentine')).to eq(
      [['Slowdive', 0.91, 'mbid-1']],
    )
  end

  it 'returns every similar artist when Last.fm sends an array' do
    allow(http).to receive(:get).and_return(json_reply('similarartists' => {
                                                         'artist' => [
                                                           { 'name' => 'Slowdive', 'match' => '0.9',
                                                             'mbid' => 'a' },
                                                           { 'name' => 'Ride', 'match' => '0.8',
                                                             'mbid' => 'b' },
                                                         ],
                                                       }))

    expect(service.similar_artists('MBV').map(&:first)).to eq(%w[Slowdive Ride])
  end

  it 'wraps a single top artist the same way' do
    allow(http).to receive(:get).and_return(json_reply('topartists' => {
                                                         'artist' => { 'name' => 'Slowdive' },
                                                       }))

    expect(service.top_artists('shoegaze')).to eq([{ 'name' => 'Slowdive' }])
  end

  it 'signs scrobbles without blank album fields so the signature matches the body' do
    posted = nil
    allow(http).to receive(:post) do |_url, body:, headers:|
      posted = { body: body, headers: headers }
      Loamp::Http::Client::Response.new(status: 200, body: '{}')
    end
    track = AudioFixtures.track_with(title: 'Song', artist: 'Artist', album: nil, duration: 60)

    expect(service.submit(track, listened_at: 123)).to be(true)

    fields = URI.decode_www_form(posted[:body]).to_h
    expect(fields).not_to have_key('album')
    unsigned = fields.except('api_sig', 'format')
    text = unsigned.sort.map { |key, value| "#{key}#{value}" }.join
    expect(fields['api_sig']).to eq(Digest::MD5.hexdigest("#{text}SECRET"))
    expect(posted[:headers]['Content-Type']).to eq('application/x-www-form-urlencoded')
  end

  it 'refuses to scrobble without a session' do
    anonymous = described_class.new(api_key: 'KEY', client: http)
    track = AudioFixtures.track_with(title: 'Song', artist: 'Artist')

    expect(anonymous.submit(track, listened_at: 1)).to be(false)
  end
end
