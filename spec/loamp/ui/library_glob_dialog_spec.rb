# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Loamp::UI::LibraryGlobDialog do
  before(:each) do
    skip_if_no_gtk
  end

  let(:library) { Loamp::Library.new(path: Loamp::Library::IN_MEMORY) }
  let(:messages) { [] }
  let(:parent) do
    notes = messages
    Class.new do
      define_method(:notify) { |message| notes << message }
    end.new
  end
  let(:root) do
    dir = File.join(AudioFixtures.fixture_dir, "glob-dialog-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(dir)
    @root = dir
  end

  after do
    library.close
    FileUtils.rm_rf(@root) if @root
  end

  def folder(*parts)
    File.join(root, *parts).tap { |path| FileUtils.mkdir_p(path) }
  end

  def dialog(on_added: nil)
    described_class.new(parent, library: library, on_added: on_added)
  end

  it 'previews matches without adding anything to the library' do
    folder('mnt', 'a', 'downloads-2023')
    folder('mnt', 'b', 'downloads')
    view = dialog

    view.preview(File.join(root, 'mnt', '**', 'downloads*'), async: false)

    expect(view.selected_paths.size).to eq(2)
    expect(library.stored_watch_folders).to be_empty
  end

  it 'adds only the ticked folders, as one batch' do
    keep = folder('keep')
    folder('drop')
    added = []
    view = dialog(on_added: ->(paths) { added = paths })

    view.preview(File.join(root, '*'), async: false)
    view.send(:set_all_selected, false)
    view.send(:rows).each { |check, path| check.active = true if path == keep }
    view.add_selected

    expect(library.stored_watch_folders).to eq([keep])
    expect(added).to eq([keep])
  end

  it 'leaves folders the library already watches unticked' do
    watched = folder('watched')
    library.add_watch_folder(watched)
    folder('fresh')
    view = dialog

    view.preview(File.join(root, '*'), async: false)

    expect(view.selected_paths).to eq([File.join(root, 'fresh')])
  end

  it 'says so rather than adding when nothing is ticked' do
    folder('one')
    view = dialog

    view.preview(File.join(root, '*'), async: false)
    view.send(:set_all_selected, false)
    view.add_selected

    expect(library.stored_watch_folders).to be_empty
    expect(messages).to eq(['Nothing selected to add'])
  end

  it 'reports a pattern that matched nothing' do
    view = dialog

    view.preview(File.join(root, 'nope', '*'), async: false)

    expect(view.send(:summary).text).to eq('Nothing matched that pattern')
    expect(view.selected_paths).to be_empty
  end

  it 'summarises the folders and tracks a pattern would pull in' do
    downloads = folder('downloads')
    FileUtils.touch(File.join(downloads, 'a.mp3'))
    view = dialog

    view.preview(File.join(root, '*'), async: false)

    expect(view.send(:summary).text).to eq('1 folder matched · 1 track in total')
  end
end
