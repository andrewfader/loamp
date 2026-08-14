# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::CoverArt::Archive do
  subject(:archive) { described_class.new(client: Loamp::Http::Client.new, base_url: server.url_for('')) }

  let(:server) { StubHttpServer.new }
  let(:release_id) { AudioFixtures::MUSICBRAINZ_ALBUM_ID }

  after { server.stop }

  def front_path(size = '-500')
    "/release/#{release_id}/front#{size}"
  end

  describe '#front' do
    it 'returns the image the archive holds' do
      server.on(front_path, body: 'JPEG DATA', headers: { 'Content-Type' => 'image/jpeg' })

      image = archive.front(release_id)

      expect(image.data).to eq('JPEG DATA')
      expect(image.mime_type).to eq('image/jpeg')
    end

    # The archive answers with a redirect to wherever the file really lives.
    it 'follows the redirect the archive answers with' do
      server.on(front_path, status: 307, headers: { 'Location' => '/storage/cover.jpg' })
      server.on('/storage/cover.jpg', body: 'JPEG DATA', headers: { 'Content-Type' => 'image/jpeg' })

      expect(archive.front(release_id).data).to eq('JPEG DATA')
    end

    it 'returns nil when the release has no cover' do
      expect(archive.front(release_id)).to be_nil
    end

    it 'returns nil rather than raising when the archive is unreachable' do
      unreachable = described_class.new(client: Loamp::Http::Client.new, base_url: 'http://127.0.0.1:1')

      expect(unreachable.front(release_id)).to be_nil
    end

    it 'ignores an empty body dressed up as a success' do
      server.on(front_path, body: '', headers: { 'Content-Type' => 'image/jpeg' })

      expect(archive.front(release_id)).to be_nil
    end

    it 'takes the image type from the reply rather than assuming one' do
      server.on(front_path, body: 'PNG DATA', headers: { 'Content-Type' => 'image/png; charset=binary' })

      expect(archive.front(release_id).mime_type).to eq('image/png')
    end

    it 'falls back to JPEG when the reply does not say what it sent' do
      server.on(front_path, body: 'DATA')

      expect(archive.front(release_id).mime_type).to eq('image/jpeg')
    end

    # The id is interpolated into a path, so it is checked before it is sent.
    it 'refuses an id that is not one' do
      expect(archive.front('../../../etc/passwd')).to be_nil
      expect(server.requests).to be_empty
    end

    it 'refuses a missing id' do
      expect(archive.front(nil)).to be_nil
    end
  end

  describe 'sizes' do
    it 'asks for a thumbnail when one was asked of it' do
      server.on(front_path('-250'), body: 'SMALL', headers: { 'Content-Type' => 'image/jpeg' })
      thumbnails = described_class.new(client: Loamp::Http::Client.new,
                                       base_url: server.url_for(''), size: :small)

      expect(thumbnails.front(release_id).data).to eq('SMALL')
    end

    it 'can be asked for a different size than it was built with' do
      server.on(front_path(''), body: 'FULL', headers: { 'Content-Type' => 'image/jpeg' })

      expect(archive.front(release_id, size: :original).data).to eq('FULL')
    end

    it 'defaults to a size that is worth caching' do
      expect(archive.front_url(release_id)).to end_with('/front-500')
    end
  end

  describe '#definitive?' do
    it 'is true when the archive said there is no cover' do
      archive.front(release_id)

      expect(archive).to be_definitive
    end

    it 'is false when nothing answered' do
      unreachable = described_class.new(client: Loamp::Http::Client.new, base_url: 'http://127.0.0.1:1')
      unreachable.front(release_id)

      expect(unreachable).not_to be_definitive
    end

    it 'is false before anything has been asked' do
      expect(archive).not_to be_definitive
    end
  end
end
