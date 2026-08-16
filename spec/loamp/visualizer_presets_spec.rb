# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Loamp::VisualizerPresets do
  # Stands in for the GStreamer projectm element: a preset property and a
  # record of everything written to it.
  def fake_element(properties)
    Class.new do
      define_singleton_method(:properties) { properties }

      def assignments = @assignments ||= []
      def set_property(name, value) = assignments << [name, value]
    end.new
  end

  def projectm_element = fake_element(%w[name parent preset preset-duration])
  def goom_element = fake_element(%w[name parent shader])

  subject(:presets) { described_class.new(element, search_paths: [dir]) }

  let(:dir) { Dir.mktmpdir('loamp-presets') }
  let(:element) { projectm_element }

  before do
    %w[bravo.milk alpha.milk charlie.prjm notes.txt].each do |name|
      File.write(File.join(dir, name), 'preset')
    end
  end

  after { FileUtils.remove_entry(dir) }

  def preset_path(name) = File.join(dir, name)

  describe '#paths' do
    it 'finds preset files in sorted order and ignores anything else' do
      expect(presets.paths.map { |path| File.basename(path) })
        .to eq(%w[alpha.milk bravo.milk charlie.prjm])
    end

    it 'searches nested directories' do
      nested = File.join(dir, 'pack', 'deep')
      FileUtils.mkdir_p(nested)
      File.write(File.join(nested, 'zulu.milk'), 'preset')
      expect(presets.paths.map { |path| File.basename(path) }).to include('zulu.milk')
    end

    it 'takes a search path that is a single preset file' do
      file = preset_path('alpha.milk')
      expect(described_class.new(element, search_paths: [file]).paths).to eq([file])
    end

    it 'skips search paths that do not exist' do
      missing = described_class.new(element, search_paths: [preset_path('nope')])
      expect(missing.paths).to be_empty
    end
  end

  describe '#available?' do
    it 'is true for an element with a preset property and presets on disk' do
      expect(presets).to be_available
    end

    it 'is false for an element without a preset property' do
      expect(described_class.new(goom_element, search_paths: [dir])).not_to be_available
    end

    it 'is false without an element' do
      expect(described_class.new(nil, search_paths: [dir])).not_to be_available
    end

    it 'is false when no presets are installed' do
      empty = Dir.mktmpdir('loamp-empty')
      expect(described_class.new(element, search_paths: [empty])).not_to be_available
    ensure
      FileUtils.remove_entry(empty)
    end
  end

  describe 'cycling' do
    it 'starts on the first preset' do
      expect(presets.current_name).to eq('alpha')
      expect(presets.count).to eq(3)
    end

    it 'advances to the next preset and hands it to the element' do
      expect(presets.next_preset).to eq('bravo')
      expect(element.assignments.last).to eq(['preset', preset_path('bravo.milk')])
    end

    it 'wraps around the end of the list' do
      2.times { presets.next_preset }
      expect(presets.next_preset).to eq('alpha')
    end

    it 'steps backwards, wrapping past the start' do
      expect(presets.previous_preset).to eq('charlie')
      expect(presets.previous_preset).to eq('bravo')
    end

    it 'jumps to a position, wrapping out-of-range values' do
      expect(presets.select(4)).to eq('bravo')
      expect(presets.index).to eq(1)
    end

    it 'picks a random preset from the list' do
      names = Array.new(20) { presets.random_preset }
      expect(names.uniq.sort - %w[alpha bravo charlie]).to be_empty
      expect(element.assignments.size).to eq(20)
    end

    it 'does nothing for an element that has no preset property' do
      other = described_class.new(goom_element, search_paths: [dir])
      expect(other.next_preset).to be_nil
      expect(other.index).to eq(0)
    end

    it 'reports nothing when the element refuses the assignment' do
      allow(element).to receive(:set_property).and_raise(StandardError, 'no such preset')
      expect(presets.next_preset).to be_nil
    end
  end

  describe 'the restart hook' do
    it 'runs after the preset is handed over, so the element reloads it' do
      order = []
      allow(element).to receive(:set_property) { order << :preset }
      presets = described_class.new(element, search_paths: [dir],
                                             restart: -> { order << :restart })
      expect(presets.next_preset).to eq('bravo')
      expect(order).to eq(%i[preset restart])
    end

    it 'stays put when there is nothing to cycle' do
      restarted = false
      presets = described_class.new(goom_element, search_paths: [dir],
                                                  restart: -> { restarted = true })
      presets.next_preset
      expect(restarted).to be(false)
    end
  end

  describe '#element=' do
    it 'adopts a plugin element built after construction' do
      late = described_class.new(nil, search_paths: [dir])
      expect(late).not_to be_available
      late.element = element
      expect(late).to be_available
      expect(late.next_preset).to eq('bravo')
    end
  end

  describe '.search_paths' do
    it 'includes the XDG data directories and the projectM preset folders' do
      paths = with_environment('XDG_DATA_DIRS' => '/opt/share') { described_class.search_paths }
      expect(paths).to include('/opt/share/projectM/presets')
    end

    it 'puts explicit environment overrides first' do
      paths = with_environment('LOAMP_PROJECTM_PRESETS' => '/a/presets:/b/presets') do
        described_class.search_paths
      end
      expect(paths.first(2)).to eq(['/a/presets', '/b/presets'])
    end
  end

  def with_environment(values)
    original = values.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end
end
