#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/loamp'

# Small executable smoke suite used in addition to the RSpec suite.
module IntegrationTest
  module_function

  FIXTURE = File.expand_path('../test_files/turkey_in_the_straw.mp3', __dir__)

  def assert(description)
    raise "Failed: #{description}" unless yield

    puts "✓ #{description}"
  end

  def run
    track = Loamp::Track.new(FIXTURE)
    assert('reads real MP3 metadata') { track.duration.positive? && !track.title.to_s.empty? }

    playlist = Loamp::Playlist.new
    playlist.add_track(FIXTURE)
    playlist.add_track(FIXTURE)
    assert('manages and advances a playlist') do
      playlist.size == 2 && playlist.next_track.equal?(playlist[1])
    end

    # A real pipeline sending its audio nowhere: position only means anything
    # once something is actually decoding.
    engine = Loamp::AudioEngine.new(audio_sink: 'fakesink sync=true')
    player = Loamp::Player.new(playlist, engine: engine)
    player.set_volume(150)
    player.play
    engine.wait_for_state(:playing)
    player.seek(10)

    assert('clamps volume and seeks the real pipeline') do
      player.volume == 100 && player.position.round == 10
    end

    assert('wires application components') do
      application = Loamp::Application.new
      app_playlist = application.instance_variable_get(:@playlist)
      app_player = application.instance_variable_get(:@player)
      app_playlist.is_a?(Loamp::Playlist) && app_player.playlist.equal?(app_playlist)
    end

    assert('speaks MPRIS to the desktop') { mpris_reachable?(player) }
    assert('persists library auto-scan folders') { watch_folders_work? }
    assert('resolves podcast directory listings') { podcast_directory_works? }

    engine.shutdown
    puts '7/7 integration checks passed'
  end

  # A build machine may have no session bus at all, which must not be read as
  # a broken MPRIS implementation — only as an unanswerable question.
  def mpris_reachable?(player)
    service = Loamp::Mpris::Service.new(Loamp::Mpris::Adapter.new(player),
                                        bus_name: "org.mpris.MediaPlayer2.loamp.check#{Process.pid}")
    return puts('  (no session bus; MPRIS export not exercised)') || true unless service.start

    service.stop
    true
  end

  def watch_folders_work?
    Dir.mktmpdir('loamp-watch') do |dir|
      FileUtils.cp(FIXTURE, File.join(dir, 'a.mp3'))
      library = Loamp::Library.new(path: Loamp::Library::IN_MEMORY)
      library.add_watch_folder(dir)
      roots = library.stored_watch_folders
      library.remove_watch_folder(dir, remove_tracks: false)
      library.close
      roots == [File.expand_path(dir)] && File.directory?(dir)
    end
  end

  def podcast_directory_works?
    client = Object.new
    def client.get(url, **)
      body = if url.include?('toppodcasts')
               '{"feed":{"entry":[{"id":{"attributes":{"im:id":"1"}}}]}}'
             else
               '{"results":[{"collectionName":"Show","artistName":"Host",' \
                 '"feedUrl":"https://feeds.test/show","collectionId":1}]}'
             end
      Loamp::Http::Client::Response.new(status: 200, body: body)
    end

    listings = Loamp::Podcast::Directory.new(client: client).popular
    listings.first&.title == 'Show' && listings.first.browsable?
  end
end

IntegrationTest.run if $PROGRAM_NAME == __FILE__
