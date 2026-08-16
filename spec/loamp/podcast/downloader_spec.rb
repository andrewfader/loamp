# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Podcast::Downloader do
  let(:server) { StubHttpServer.new }
  let(:downloader) { described_class.new(client: Loamp::Http::Client.new) }

  after { server.stop }

  it 'writes a new file from a full response' do
    Dir.mktmpdir do |directory|
      server.on('/ep.mp3', body: 'abcdef')
      destination = File.join(directory, 'episode.mp3')

      expect(downloader.download(server.url_for('/ep.mp3'), destination)).to eq(destination)
      expect(File.binread(destination)).to eq('abcdef')
    end
  end

  it 'appends when the server honours a Range request' do
    Dir.mktmpdir do |directory|
      destination = File.join(directory, 'episode.mp3')
      File.binwrite(destination, 'abc')
      server.on('/ep.mp3', status: 206, body: 'def')

      downloader.download(server.url_for('/ep.mp3'), destination)

      expect(File.binread(destination)).to eq('abcdef')
      expect(server.requests.last.headers['range']).to eq('bytes=3-')
    end
  end

  it 'treats a completed file as success when the server answers 416' do
    Dir.mktmpdir do |directory|
      destination = File.join(directory, 'episode.mp3')
      File.binwrite(destination, 'complete')
      server.on('/ep.mp3', status: 416, body: '')

      expect(downloader.download(server.url_for('/ep.mp3'), destination)).to eq(destination)
      expect(File.binread(destination)).to eq('complete')
    end
  end

  it 'returns false when the download cannot be fetched' do
    Dir.mktmpdir do |directory|
      server.on('/ep.mp3', status: 404, body: 'missing')

      expect(downloader.download(server.url_for('/ep.mp3'), File.join(directory, 'x.mp3'))).to be(false)
    end
  end
end
