# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::CoverArt::MissLog do
  subject(:log) { described_class.new(path: path, clock: -> { now.first }) }

  let(:directory) { Dir.mktmpdir('loamp-misses') }
  let(:path) { File.join(directory, 'misses.json') }
  # A clock the spec winds forward by hand, started from the real one so that
  # an instance built with the default clock agrees with it.
  let(:now) { [Time.now.to_i] }

  after { FileUtils.rm_rf(directory) }

  it 'knows nothing to begin with' do
    expect(log.miss?('an-album')).to be false
  end

  it 'remembers a miss' do
    log.record('an-album')

    expect(log.miss?('an-album')).to be true
  end

  it 'keeps one album apart from another' do
    log.record('an-album')

    expect(log.miss?('another-album')).to be false
  end

  # The point of the whole class: surviving a restart.
  it 'remembers across instances' do
    log.record('an-album')

    reopened = described_class.new(path: path)

    expect(reopened.miss?('an-album')).to be true
  end

  describe 'expiry' do
    it 'forgets a miss old enough that art may have been uploaded since' do
      log.record('an-album')
      now[0] += described_class::EXPIRY_SECONDS + 1

      expect(log.miss?('an-album')).to be false
    end

    it 'keeps one that has not aged out yet' do
      log.record('an-album')
      now[0] += described_class::EXPIRY_SECONDS - 1

      expect(log.miss?('an-album')).to be true
    end

    it 'drops what has aged out when the log is loaded' do
      log.record('an-album')
      now[0] += described_class::EXPIRY_SECONDS + 1

      reopened = described_class.new(path: path, clock: -> { now.first })

      expect(reopened.size).to eq(0)
    end
  end

  describe '#forget' do
    it 'drops one album' do
      log.record('an-album')
      log.record('another-album')

      log.forget('an-album')

      expect(log.miss?('an-album')).to be false
      expect(log.miss?('another-album')).to be true
    end

    it 'drops everything when asked for nothing in particular' do
      log.record('an-album')
      log.forget

      expect(log.size).to eq(0)
    end
  end

  # None of this is worth a word to the listener, who did not ask for any of it.
  describe 'a cache that cannot be used' do
    it 'treats a corrupt file as an empty one' do
      File.write(path, 'this is not JSON')

      expect(log.miss?('an-album')).to be false
    end

    it 'treats a file holding the wrong shape as an empty one' do
      File.write(path, '["not", "a", "map"]')

      expect(log.miss?('an-album')).to be false
    end

    it 'ignores an entry whose timestamp is not one' do
      File.write(path, JSON.generate('an-album' => 'yesterday'))

      expect(log.miss?('an-album')).to be false
    end

    it 'reports rather than raises when the log cannot be written' do
      unwritable = described_class.new(path: '/proc/nope/misses.json')

      expect(unwritable.record('an-album')).to be true
      expect(unwritable.miss?('an-album')).to be true
    end

    it 'creates the directory it was pointed at' do
      nested = described_class.new(path: File.join(directory, 'deep', 'down', 'misses.json'))

      nested.record('an-album')

      expect(File.file?(File.join(directory, 'deep', 'down', 'misses.json'))).to be true
    end
  end
end
