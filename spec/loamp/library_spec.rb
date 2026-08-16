# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Loamp::Library do
  let(:library) { described_class.new(path: described_class::IN_MEMORY) }

  after { library.close }

  # Real files, because the whole point of the index is to notice when one
  # changes on disk.
  let(:collection) do
    dir = File.join(AudioFixtures.fixture_dir, "library-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(dir)
    @collection = dir
  end

  after { FileUtils.rm_rf(@collection) if @collection }

  def copy_into(collection, name, source: AudioFixtures.sample_mp3)
    path = File.join(collection, name)
    FileUtils.cp(source, path)
    path
  end

  def index(**tags)
    path = File.join(collection, "#{SecureRandom.hex(4)}.mp3")
    FileUtils.cp(AudioFixtures.sample_mp3, path)
    library.add(path, metadata: Loamp::Metadata.new(**tags))
    path
  end

  describe 'the schema' do
    it 'stores every attribute Metadata reads' do
      expect(Loamp::Metadata::ATTRIBUTES - described_class::Schema::TAG_COLUMNS).to be_empty
    end

    it 'records its own version, so an older index can be recognised' do
      expect(library.instance_variable_get(:@database).user_version).to eq(described_class::Schema::VERSION)
    end
  end

  # An index written by an earlier version is the normal case on an upgrade,
  # and CREATE TABLE IF NOT EXISTS would leave it exactly as it was.
  describe 'an index from an older version' do
    let(:database_path) { File.join(collection, 'old-library.db') }

    # A tracks table as it stood before the MusicBrainz columns existed.
    def build_old_index
      described_class.new(path: database_path).tap do |old|
        database = old.instance_variable_get(:@database)
        %i[musicbrainz_album_id musicbrainz_artist_id].each do |column|
          database.execute("ALTER TABLE tracks DROP COLUMN #{column}")
        end
        database.user_version = 1
        old.close
      end
    end

    it 'gains the columns added since' do
      build_old_index
      library = described_class.new(path: database_path)

      columns = library.instance_variable_get(:@database).table_info('tracks').map { |c| c['name'] }

      expect(columns).to include('musicbrainz_album_id', 'musicbrainz_artist_id')
      expect(library.instance_variable_get(:@database).table_info('folders')).not_to be_empty
      library.close
    end

    it 'can index a file once it has been migrated' do
      build_old_index
      library = described_class.new(path: database_path)

      expect(library.add(AudioFixtures.musicbrainz_flac)).to eq(:added)
      expect(library.tracks.first.musicbrainz_album_id).to eq(AudioFixtures::MUSICBRAINZ_ALBUM_ID)
      library.close
    end

    it 'keeps what the older index already held' do
      build_old_index
      first = described_class.new(path: database_path)
      first.add(AudioFixtures.sample_mp3)
      first.close

      second = described_class.new(path: database_path)

      expect(second.count).to eq(1)
      second.close
    end
  end

  describe '#add' do
    it 'indexes a file it has not seen' do
      expect(library.add(AudioFixtures.sample_mp3)).to eq(:added)
      expect(library.count).to eq(1)
    end

    it 'reads the tags off the file' do
      library.add(AudioFixtures.tagged_flac)

      expect(library.track(AudioFixtures.tagged_flac).title).to eq('Fixture Song')
    end

    it 'leaves an unchanged file alone rather than re-reading it' do
      library.add(AudioFixtures.sample_mp3)

      expect(Loamp::Metadata).not_to receive(:read)
      expect(library.add(AudioFixtures.sample_mp3)).to eq(:unchanged)
    end

    it 'reindexes a file whose contents changed' do
      path = copy_into(collection, 'track.mp3')
      library.add(path)

      FileUtils.cp(AudioFixtures.sample_mp3_with_tags, path)

      expect(library.add(path)).to eq(:updated)
      expect(library.track(path).title).to eq('Relationships')
      expect(library.count).to eq(1)
    end

    it 'notices a file that changed without changing size' do
      path = copy_into(collection, 'track.mp3')
      library.add(path)
      File.utime(Time.now + 60, Time.now + 60, path)

      expect(library.add(path)).to eq(:updated)
    end

    it 'accepts metadata instead of reading the file' do
      path = copy_into(collection, 'track.mp3')

      library.add(path, metadata: Loamp::Metadata.new(title: 'Injected'))

      expect(library.track(path).title).to eq('Injected')
    end

    it 'reports a file that is not there' do
      expect(library.add('/nonexistent/track.mp3')).to eq(:missing)
      expect(library).to be_empty
    end

    it 'stores one row per path however often it is added' do
      3.times { library.add(AudioFixtures.tagged_ogg) }

      expect(library.count).to eq(1)
    end
  end

  describe 'round-tripping a track' do
    it 'rebuilds it without touching the file again' do
      library.add(AudioFixtures.tagged_flac)

      expect(Loamp::Metadata).not_to receive(:read)
      track = library.track(AudioFixtures.tagged_flac)

      expect(track).to be_a(Loamp::Track)
      expect(track.artist).to eq('Fixture Artist')
      expect(track.album).to eq('Fixture Album')
      expect(track.album_artist).to eq('Fixture Album Artist')
      expect(track.track_number).to eq(4)
    end

    it 'keeps the numeric fields numeric' do
      library.add(AudioFixtures.tagged_flac)
      track = library.track(AudioFixtures.tagged_flac)

      expect(track.year).to eq(1999)
      expect(track.disc_number).to eq(2)
      expect(track.duration).to be_positive
      expect(track.replaygain_track_gain).to eq(-6.5)
    end

    it 'remembers whether the file had artwork' do
      library.add(AudioFixtures.sample_mp3_with_tags)

      expect(library.track(AudioFixtures.sample_mp3_with_tags).artwork?).to be true
    end

    it 'returns nil for a path it never indexed' do
      expect(library.track('/nowhere.mp3')).to be_nil
    end
  end

  describe '#remove and #prune' do
    it 'removes one path' do
      library.add(AudioFixtures.sample_mp3)

      expect(library.remove(AudioFixtures.sample_mp3)).to be true
      expect(library).to be_empty
    end

    it 'reports removing something that was never there' do
      expect(library.remove('/nowhere.mp3')).to be false
    end

    it 'drops rows whose file has gone' do
      kept = AudioFixtures.sample_mp3
      deleted = copy_into(collection, 'temporary.mp3')
      library.add(kept)
      library.add(deleted)
      FileUtils.rm(deleted)

      expect(library.prune).to eq([deleted])
      expect(library.paths).to eq([kept])
    end

    it 'empties completely' do
      library.add(AudioFixtures.sample_mp3)
      library.clear

      expect(library).to be_empty
    end
  end

  describe 'browsing' do
    before do
      index(title: 'Falling', artist: 'Haim', album_artist: 'Haim', album: 'Days Are Gone',
            year: 2013, track_number: 1, genre: 'Pop')
      index(title: 'The Wire', artist: 'Haim', album_artist: 'Haim', album: 'Days Are Gone',
            year: 2013, track_number: 2, genre: 'Pop')
      index(title: 'Now I''m In It', artist: 'Haim', album_artist: 'Haim', album: 'WIMPIII',
            year: 2020, track_number: 1, genre: 'Pop')
      index(title: 'Svefn-g-englar', artist: 'Sigur Rós', album: 'Ágætis byrjun',
            year: 1999, track_number: 2, genre: 'Post-rock')
    end

    it 'lists artists with what they contribute' do
      names = library.artists

      expect(names.map(&:name)).to eq(['Haim', 'Sigur Rós'])
      expect(names.first.album_count).to eq(2)
      expect(names.first.track_count).to eq(3)
    end

    it 'falls back to the performing artist when there is no album artist' do
      expect(library.artists.map(&:name)).to include('Sigur Rós')
    end

    it 'lists albums oldest first within an artist' do
      titles = library.albums(artist: 'Haim').map(&:title)

      expect(titles).to eq(['Days Are Gone', 'WIMPIII'])
    end

    it 'counts the tracks on each album' do
      expect(library.albums(artist: 'Haim').first.track_count).to eq(2)
    end

    it 'lists every album when no artist is named' do
      expect(library.albums.size).to eq(3)
    end

    it 'returns an album in the order it was meant to play' do
      titles = library.tracks(artist: 'Haim', album: 'Days Are Gone').map(&:title)

      expect(titles).to eq(['Falling', 'The Wire'])
    end

    it 'lists genres once each' do
      expect(library.genres).to eq(['Pop', 'Post-rock'])
    end

    it 'pages through everything' do
      expect(library.tracks(limit: 2).size).to eq(2)
      expect(library.tracks(limit: 2, offset: 2).size).to eq(2)
      expect(library.tracks(limit: 2).first.title).not_to eq(library.tracks(limit: 2,
                                                                           offset: 2).first.title)
    end

    it 'groups tracks that carry no artist at all under one heading' do
      index(title: 'Untagged')

      unknown = library.artists.find { |artist| artist.name.nil? }

      expect(unknown.display_name).to eq('Unknown Artist')
      expect(library.tracks(artist: nil).map(&:title)).to eq(['Untagged'])
    end

    it 'indexes artists and MusicBrainz ids for the similar-artist graph' do
      expect(library.artist_index).to include('Haim' => true, 'Sigur Rós' => true)
    end
  end

  describe '#search' do
    before do
      index(title: 'Falling', artist: 'Haim', album: 'Days Are Gone')
      index(title: 'Svefn-g-englar', artist: 'Sigur Rós', album: 'Ágætis byrjun')
      index(title: 'The Wire', artist: 'Haim', album: 'Days Are Gone')
    end

    it 'matches a title' do
      expect(library.search('falling').map(&:title)).to eq(['Falling'])
    end

    it 'matches an artist' do
      expect(library.search('haim').map(&:title)).to match_array(['Falling', 'The Wire'])
    end

    it 'matches an album' do
      expect(library.search('days are gone').size).to eq(2)
    end

    it 'matches on a prefix, so results narrow while typing' do
      expect(library.search('fall').map(&:title)).to eq(['Falling'])
    end

    it 'ignores case' do
      expect(library.search('HAIM').size).to eq(2)
    end

    it 'ignores accents, which nobody types' do
      expect(library.search('agætis').size).to eq(1)
      expect(library.search('sigur ros').size).to eq(1)
    end

    it 'requires every word to match' do
      expect(library.search('haim gone').size).to eq(2)
      expect(library.search('haim sigur')).to be_empty
    end

    it 'returns nothing for an empty query rather than everything' do
      expect(library.search('')).to be_empty
      expect(library.search('   ')).to be_empty
    end

    it 'treats search syntax as literal text' do
      expect { library.search('NEAR/2 ()"*') }.not_to raise_error
      expect(library.search('"; DROP TABLE tracks; --')).to be_empty
      expect(library.count).to eq(3)
    end

    it 'honours a limit' do
      expect(library.search('haim', limit: 1).size).to eq(1)
    end

    it 'stops matching a track that was removed' do
      library.remove(library.search('falling').first.file_path)

      expect(library.search('falling')).to be_empty
    end

    it 'follows a track whose tags were rewritten' do
      path = library.search('falling').first.file_path
      library.add(path, metadata: Loamp::Metadata.new(title: 'Renamed', artist: 'Haim'))

      expect(library.search('falling')).to be_empty
      expect(library.search('renamed').map(&:title)).to eq(['Renamed'])
    end
  end

  describe 'on disk' do
    let(:database_path) { File.join(collection, 'library.db') }

    it 'survives being closed and reopened' do
      first = described_class.new(path: database_path)
      first.add(AudioFixtures.sample_mp3)
      first.close

      second = described_class.new(path: database_path)

      expect(second.count).to eq(1)
      second.close
    end

    it 'creates the directory it was pointed at' do
      nested = File.join(collection, 'deep', 'down', 'library.db')

      described_class.new(path: nested).close

      expect(File.file?(nested)).to be true
    end

    it 'defaults to the XDG data directory' do
      expect(described_class.default_path).to end_with('loamp/library.db')
    end

    it 'remembers watch folders after a reopen' do
      first = described_class.new(path: database_path)
      first.add_watch_folder(collection)
      first.close

      second = described_class.new(path: database_path)

      expect(second.watch_folders).to eq([File.expand_path(collection)])
      second.close
    end
  end

  describe '#watch_folders' do
    it 'starts empty' do
      expect(library.watch_folders).to be_empty
    end

    it 'stores a folder the listener asked to index' do
      expect(library.add_watch_folder(collection)).to be true
      expect(library.watch_folders).to eq([File.expand_path(collection)])
    end

    it 'ignores a path that is not a directory' do
      expect(library.add_watch_folder('/nowhere/at/all')).to be false
      expect(library.watch_folders).to be_empty
    end

    it 'does not store a folder twice' do
      2.times { library.add_watch_folder(collection) }

      expect(library.watch_folders).to eq([File.expand_path(collection)])
    end

    it 'collapses a nested folder into its parent' do
      child = File.join(collection, 'Artist', 'Album')
      FileUtils.mkdir_p(child)
      library.add_watch_folder(child)

      library.add_watch_folder(collection)

      expect(library.watch_folders).to eq([File.expand_path(collection)])
    end

    it 'does not store a folder already covered by a parent' do
      child = File.join(collection, 'Artist', 'Album')
      FileUtils.mkdir_p(child)
      library.add_watch_folder(collection)

      library.add_watch_folder(child)

      expect(library.watch_folders).to eq([File.expand_path(collection)])
    end

    it 'falls back to album directories when nothing was stored' do
      path = index(title: 'Falling', artist: 'Haim', album: 'Days Are Gone')

      expect(library.watch_folders).to eq([File.dirname(path)])
    end
  end
end
