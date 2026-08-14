# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Loamp::Library::Scanner do
  let(:root) do
    dir = File.join(AudioFixtures.fixture_dir, "scan-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(dir)
    @root = dir
  end

  let(:database_path) { File.join(root, 'library.db') }
  let(:library) { Loamp::Library.new(path: database_path) }
  let(:scanner) { described_class.new(database_path) }

  after do
    library.close
    FileUtils.rm_rf(@root) if @root
  end

  def add_audio(name, source: AudioFixtures.sample_mp3)
    path = File.join(root, name)
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.cp(source, path)
    path
  end

  describe '#audio_files' do
    it 'finds audio anywhere below the folder' do
      add_audio('a.mp3')
      add_audio('deep/nested/b.mp3')

      expect(scanner.audio_files([root]).size).to eq(2)
    end

    it 'ignores files that are not audio' do
      add_audio('a.mp3')
      File.write(File.join(root, 'cover.jpg'), 'not audio')
      File.write(File.join(root, 'notes.txt'), 'not audio')

      expect(scanner.audio_files([root]).map { |f| File.basename(f) }).to eq(['a.mp3'])
    end

    it 'accepts a single file as well as a folder' do
      path = add_audio('a.mp3')

      expect(scanner.audio_files([path])).to eq([path])
    end

    it 'indexes an overlapping pair of folders only once' do
      add_audio('music/a.mp3')

      expect(scanner.audio_files([root, File.join(root, 'music')]).size).to eq(1)
    end

    it 'shrugs at a folder that does not exist' do
      expect(scanner.audio_files(['/nowhere/at/all'])).to be_empty
    end
  end

  describe '#scan' do
    it 'indexes everything it finds' do
      add_audio('a.mp3')
      add_audio('b.mp3')

      result = scanner.scan([root])

      expect(result.added).to eq(2)
      expect(result.scanned).to eq(2)
      expect(library.count).to eq(2)
    end

    it 'reports progress as it goes' do
      add_audio('a.mp3')
      updates = []

      scanner.scan([root]) { |progress| updates << progress }

      expect(updates).not_to be_empty
      expect(updates.last.scanned).to eq(1)
      expect(updates.last).to be_complete
    end

    it 'adds nothing the second time round' do
      add_audio('a.mp3')
      scanner.scan([root])

      result = scanner.scan([root])

      expect(result.added).to be_zero
      expect(result.updated).to be_zero
      expect(result.scanned).to eq(1)
    end

    it 'picks up a file whose tags were rewritten' do
      path = add_audio('a.mp3')
      scanner.scan([root])
      FileUtils.cp(AudioFixtures.sample_mp3_with_tags, path)

      expect(scanner.scan([root]).updated).to eq(1)
      expect(library.track(path).title).to eq('Relationships')
    end

    it 'keeps going when one file cannot be read' do
      add_audio('good.mp3')
      broken = File.join(root, 'broken.mp3')
      File.binwrite(broken, 'this is not an MP3')

      result = scanner.scan([root])

      expect(result.scanned).to eq(2)
      expect(library.count).to eq(2)
    end

    it 'reports a fraction that can drive a progress bar' do
      add_audio('a.mp3')

      expect(scanner.scan([root]).fraction).to eq(1.0)
    end

    it 'copes with an empty folder' do
      result = scanner.scan([root])

      expect(result.scanned).to be_zero
      expect(result).to be_complete
    end
  end

  describe '#start' do
    it 'scans on another thread and reports back' do
      add_audio('a.mp3')
      finished = nil

      scanner.start([root], on_finished: ->(result) { finished = result })
      scanner.wait(timeout: 20)
      pump_main_loop { !finished.nil? }

      expect(finished).to be_a(described_class::Progress)
      expect(finished.added).to eq(1)
      expect(library.count).to eq(1)
    end

    it 'refuses to start twice at once' do
      10.times { |i| add_audio("track-#{i}.mp3") }
      scanner.start([root])

      expect(scanner.start([root])).to be false
      scanner.wait(timeout: 20)
    end

    it 'hands an unexpected failure to the finished callback rather than losing it' do
      library # opened before the constructor is stubbed out from under it
      allow(Loamp::Library).to receive(:new).and_raise('database on fire')
      failure = nil

      scanner.start([root], on_finished: ->(result) { failure = result })
      scanner.wait(timeout: 20)
      pump_main_loop { !failure.nil? }

      expect(failure).to be_a(StandardError)
    end

    it 'stops early when cancelled' do
      40.times { |i| add_audio("track-#{i}.mp3") }
      seen = 0
      allow(scanner).to receive(:record).and_wrap_original do |original, *arguments|
        seen += 1
        scanner.cancel if seen == 5
        original.call(*arguments)
      end

      result = scanner.scan([root])

      expect(result.scanned).to eq(5)
      expect(library.count).to eq(5)
    end

    it 'starts fresh after a cancelled scan rather than staying cancelled' do
      add_audio('a.mp3')
      scanner.cancel

      expect(scanner.scan([root]).added).to eq(1)
    end
  end

  # Callbacks are delivered through GLib::Idle, so something has to turn the
  # main loop over for them to arrive.
  def pump_main_loop(timeout: 5)
    context = GLib::MainContext.default
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      context.iteration(false)
      sleep 0.01
    end
  end
end
