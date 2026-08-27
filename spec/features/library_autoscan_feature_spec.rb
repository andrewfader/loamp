# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

# Feature: Auto-scan folders keep the library filled without manual rescans.
RSpec.describe 'Library auto-scan folders', :feature do
  before { skip_if_no_gtk }

  let(:playlist) { Loamp::Playlist.new }
  let(:engine) { AudioFixtures.silent_engine }
  let(:player) { Loamp::Player.new(playlist, engine: engine) }
  let(:library) { Loamp::Library.new(path: Loamp::Library::IN_MEMORY) }
  let(:windows) { [] }
  let(:folder) do
    dir = File.join(AudioFixtures.fixture_dir, "auto-scan-feat-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(dir)
    @folder = dir
  end

  after do
    windows.each do |window|
      window.shutdown
      window.destroy
    end
    engine.shutdown
    library.close
    FileUtils.rm_rf(@folder) if @folder
  end

  def build_window
    Loamp::UI::MainWindow.new(player, playlist, library: library).tap { |w| windows << w }
  end

  scenario 'adding a folder persists it as an auto-scan root and indexes tracks' do
    FileUtils.cp(AudioFixtures.sample_mp3, File.join(folder, 'song.mp3'))
    window = build_window

    window.send(:add_folder, Struct.new(:path).new(folder))
    wait_until { library.count == 1 }

    expect(library.count).to eq(1)
    expect(library.stored_watch_folders).to eq([File.expand_path(folder)])
  end

  scenario 'startup auto-scan indexes stored folders without a menu click' do
    FileUtils.cp(AudioFixtures.sample_mp3, File.join(folder, 'song.mp3'))
    library.add_watch_folder(folder)
    window = build_window

    expect(window.auto_scan_library).to be(true)
    wait_until { library.count == 1 }

    expect(library.count).to eq(1)
  end

  scenario 'Library Folders dialog can remove an auto-scan root' do
    library.add_watch_folder(folder)
    dialog = Loamp::UI::LibraryFoldersDialog.new(
      Class.new { def notify(_); end }.new,
      library: library
    )

    dialog.send(:apply_remove_folder, folder)

    expect(library.stored_watch_folders).to be_empty
  end
end
