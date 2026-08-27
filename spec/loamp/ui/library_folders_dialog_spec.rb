# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Loamp::UI::LibraryFoldersDialog do
  before(:each) do
    skip_if_no_gtk
  end

  let(:library) { Loamp::Library.new(path: Loamp::Library::IN_MEMORY) }
  let(:parent) do
    Class.new do
      def notify(_message); end
    end.new
  end
  let(:folder) do
    dir = File.join(AudioFixtures.fixture_dir, "folders-dialog-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(dir)
    @folder = dir
  end

  after do
    library.close
    FileUtils.rm_rf(@folder) if @folder
  end

  it 'adds an entire folder as an auto-scan root' do
    changes = []
    dialog = described_class.new(parent, library: library,
                                         on_changed: ->(action, path) { changes << [action, path] })

    dialog.send(:add_folder, folder)

    expect(library.stored_watch_folders).to eq([File.expand_path(folder)])
    expect(changes).to eq([[:added, File.expand_path(folder)]])
  end

  it 'removes a folder from auto-scan after confirmation' do
    library.add_watch_folder(folder)
    changes = []
    dialog = described_class.new(parent, library: library,
                                         on_changed: ->(action, path) { changes << [action, path] })

    dialog.send(:apply_remove_folder, folder)

    expect(library.stored_watch_folders).to be_empty
    expect(changes).to eq([[:removed, File.expand_path(folder)]])
  end

  it 'ignores a path that is not a directory' do
    dialog = described_class.new(parent, library: library)

    expect(dialog.send(:add_folder, '/nowhere/at/all')).to be_nil
    expect(library.stored_watch_folders).to be_empty
  end
end
