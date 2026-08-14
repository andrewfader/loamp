# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::CoverArt::Fetcher do
  subject(:fetcher) { described_class.new(musicbrainz: musicbrainz, archive: archive) }

  let(:release_id) { AudioFixtures::MUSICBRAINZ_ALBUM_ID }
  let(:image) { Loamp::Metadata::Artwork.new(data: 'JPEG', mime_type: 'image/jpeg') }

  let(:musicbrainz) { instance_double(Loamp::CoverArt::MusicBrainz, release_id: nil, definitive?: true) }
  let(:archive) { instance_double(Loamp::CoverArt::Archive, front: nil, definitive?: true) }

  def track(**tags)
    AudioFixtures.track_with(title: 'Airbag', artist: 'Radiohead', album: 'OK Computer', **tags)
  end

  describe '#fetch' do
    it 'searches for the release, then fetches its cover' do
      allow(musicbrainz).to receive(:release_id).with(artist: 'Radiohead', album: 'OK Computer')
                                                .and_return(release_id)
      allow(archive).to receive(:front).with(release_id).and_return(image)

      result = fetcher.fetch(track)

      expect(result).to be_found
      expect(result.image).to eq(image)
      expect(result.release_id).to eq(release_id)
    end

    # The slow, rate-limited half of the work, skipped for a tagged file.
    it 'skips the search when the file already knows its release' do
      allow(archive).to receive(:front).with(release_id).and_return(image)

      result = fetcher.fetch(track(musicbrainz_album_id: release_id))

      expect(result.image).to eq(image)
      expect(musicbrainz).not_to have_received(:release_id)
    end

    it 'searches by the album artist, so compilations are found' do
      allow(musicbrainz).to receive(:release_id).and_return(nil)

      fetcher.fetch(track(album_artist: 'Various Artists'))

      expect(musicbrainz).to have_received(:release_id)
        .with(artist: 'Various Artists', album: 'OK Computer')
    end

    it 'falls back to the performing artist when there is no album artist' do
      allow(musicbrainz).to receive(:release_id).and_return(nil)

      fetcher.fetch(track)

      expect(musicbrainz).to have_received(:release_id).with(artist: 'Radiohead', album: 'OK Computer')
    end

    it 'does not go to the archive when no release matched' do
      fetcher.fetch(track)

      expect(archive).not_to have_received(:front)
    end

    it 'finds nothing when the release has no cover' do
      allow(musicbrainz).to receive(:release_id).and_return(release_id)

      expect(fetcher.fetch(track)).not_to be_found
    end
  end

  # The distinction the disk cache is built on: a miss the services confirmed
  # is worth writing down, a miss the network caused is not.
  describe 'whether a miss is worth remembering' do
    it 'is when MusicBrainz answered that it knows no such release' do
      expect(fetcher.fetch(track)).to be_definitive
    end

    it 'is not when MusicBrainz could not be reached' do
      allow(musicbrainz).to receive(:definitive?).and_return(false)

      expect(fetcher.fetch(track)).not_to be_definitive
    end

    it 'is when the archive answered that it holds no cover' do
      allow(musicbrainz).to receive(:release_id).and_return(release_id)

      expect(fetcher.fetch(track)).to be_definitive
    end

    it 'is not when the archive could not be reached' do
      allow(musicbrainz).to receive(:release_id).and_return(release_id)
      allow(archive).to receive(:definitive?).and_return(false)

      expect(fetcher.fetch(track)).not_to be_definitive
    end

    it 'is whenever art was actually found' do
      allow(musicbrainz).to receive(:release_id).and_return(release_id)
      allow(archive).to receive_messages(front: image, definitive?: false)

      expect(fetcher.fetch(track)).to be_definitive
    end
  end
end
