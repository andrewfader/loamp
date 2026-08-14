# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::Metadata do
  # Read from genuine files with genuine tags. The commercial MP3 in the repo
  # carries a full ID3v2 tag including embedded cover art.
  let(:tagged_mp3) { AudioFixtures.sample_mp3_with_tags }
  let(:untagged_mp3) { AudioFixtures.sample_mp3 }

  describe '.read on a fully tagged MP3' do
    subject(:metadata) { described_class.read(tagged_mp3) }

    it 'reads the basic tag fields' do
      expect(metadata.title).to eq('Relationships')
      expect(metadata.artist).to eq('Haim')
      expect(metadata.album).to eq('I quit')
      expect(metadata.year).to eq(2025)
    end

    it 'reads the track number' do
      expect(metadata.track_number).to eq(3)
    end

    it 'reads fields that only exist in ID3v2' do
      expect(metadata.album_artist).to eq('Haim')
      expect(metadata.disc_number).to eq(1)
      expect(metadata.disc_total).to eq(1)
      expect(metadata.composer).to include('Danielle Haim')
    end

    it 'reads the audio properties' do
      expect(metadata.duration).to be_within(0.5).of(202.0)
      expect(metadata.bitrate).to eq(276)
      expect(metadata.sample_rate).to eq(44_100)
      expect(metadata.channels).to eq(2)
    end

    it 'knows the file carries embedded artwork' do
      expect(metadata).to be_artwork
    end
  end

  describe '.read on an untagged MP3' do
    subject(:metadata) { described_class.read(untagged_mp3) }

    it 'falls back to the filename for the title' do
      expect(metadata.title).to eq('turkey_in_the_straw')
    end

    it 'leaves genuinely absent fields empty rather than inventing them' do
      expect(metadata.artist).to be_nil
      expect(metadata.album).to be_nil
      expect(metadata.track_number).to be_nil
    end

    it 'still reads the real duration' do
      expect(metadata.duration).to be_within(1.0).of(110.4)
    end

    it 'reports no artwork' do
      expect(metadata).not_to be_artwork
    end
  end

  describe '.read on a FLAC file' do
    subject(:metadata) { described_class.read(AudioFixtures.tagged_flac) }

    it 'reads Vorbis comments' do
      expect(metadata.title).to eq('Fixture Song')
      expect(metadata.artist).to eq('Fixture Artist')
      expect(metadata.album).to eq('Fixture Album')
      expect(metadata.album_artist).to eq('Fixture Album Artist')
    end

    it 'reads numbering split across separate fields' do
      expect(metadata.track_number).to eq(4)
      expect(metadata.track_total).to eq(11)
      expect(metadata.disc_number).to eq(2)
      expect(metadata.disc_total).to eq(3)
    end

    it 'reads the ReplayGain track gain' do
      expect(metadata.replaygain_track_gain).to be_within(0.01).of(-6.5)
    end
  end

  describe '.read on an Ogg Vorbis file' do
    subject(:metadata) { described_class.read(AudioFixtures.tagged_ogg) }

    it 'reads Vorbis comments' do
      expect(metadata.title).to eq('Fixture Song')
      expect(metadata.artist).to eq('Fixture Artist')
      expect(metadata.album_artist).to eq('Fixture Album Artist')
    end
  end

  # Files tagged by Picard already know which release they belong to, which
  # saves a search against MusicBrainz before any cover can be fetched.
  describe 'MusicBrainz identifiers' do
    it 'reads them from Vorbis comments' do
      metadata = described_class.read(AudioFixtures.musicbrainz_flac)

      expect(metadata.musicbrainz_album_id).to eq(AudioFixtures::MUSICBRAINZ_ALBUM_ID)
      expect(metadata.musicbrainz_artist_id).to eq(AudioFixtures::MUSICBRAINZ_ARTIST_ID)
    end

    it 'reads them from the TXXX frames ID3v2 keeps them in' do
      metadata = described_class.read(AudioFixtures.musicbrainz_mp3)

      expect(metadata.musicbrainz_album_id).to eq(AudioFixtures::MUSICBRAINZ_ALBUM_ID)
      expect(metadata.musicbrainz_artist_id).to eq(AudioFixtures::MUSICBRAINZ_ARTIST_ID)
    end

    it 'is nil for a file that carries none' do
      metadata = described_class.read(AudioFixtures.tagged_flac)

      expect(metadata.musicbrainz_album_id).to be_nil
    end

    it 'accepts an identifier however it was capitalised' do
      metadata = described_class.new(musicbrainz_album_id: AudioFixtures::MUSICBRAINZ_ALBUM_ID.upcase)

      expect(metadata.musicbrainz_album_id).to eq(AudioFixtures::MUSICBRAINZ_ALBUM_ID)
    end

    # The identifier is interpolated into a request URL, so a tag holding
    # something else must not reach the network.
    it 'drops anything that is not a UUID' do
      metadata = described_class.new(musicbrainz_album_id: 'see notes/../../etc')

      expect(metadata.musicbrainz_album_id).to be_nil
    end
  end

  describe 'combined numbering' do
    it 'splits a "3/12" track field into number and total' do
      metadata = described_class.new(track: '3/12')

      expect(metadata.track_number).to eq(3)
      expect(metadata.track_total).to eq(12)
    end

    it 'handles a bare number with no total' do
      metadata = described_class.new(track: '7')

      expect(metadata.track_number).to eq(7)
      expect(metadata.track_total).to be_nil
    end
  end

  describe 'unreadable files' do
    it 'does not raise for a file that does not exist' do
      expect { described_class.read('/nonexistent/nope.mp3') }.not_to raise_error
    end

    it 'returns a usable object for a missing file' do
      metadata = described_class.read('/nonexistent/nope.mp3')

      expect(metadata.title).to eq('nope')
      expect(metadata.artist).to be_nil
      expect(metadata.duration).to eq(0)
    end

    it 'does not raise for a file that is not audio' do
      text = File.join(AudioFixtures.fixture_dir, 'not-audio.mp3')
      File.write(text, 'this is definitely not an MP3')

      expect { described_class.read(text) }.not_to raise_error
    end
  end

  describe '.artwork' do
    it 'extracts the embedded picture bytes' do
      artwork = described_class.artwork(tagged_mp3)

      expect(artwork.mime_type).to eq('image/jpeg')
      expect(artwork.data.bytesize).to be > 10_000
    end

    it 'returns nil when there is no embedded picture' do
      expect(described_class.artwork(untagged_mp3)).to be_nil
    end

    it 'returns nil for an unreadable file' do
      expect(described_class.artwork('/nonexistent/nope.mp3')).to be_nil
    end
  end
end
