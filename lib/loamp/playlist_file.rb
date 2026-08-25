# frozen_string_literal: true

require 'pathname'

module Loamp
  # Imports and exports standard extended M3U playlists. Keeping this separate
  # from Playlist means file-format failures cannot disturb the live queue.
  module PlaylistFile
    module_function

    def save(path, playlist)
      lines = ['#EXTM3U']
      playlist.each do |track|
        lines << extinf(track)
        lines << track.file_path.to_s
      end
      File.write(path, "#{lines.join("\n")}\n")
      playlist.size
    end

    def load(path)
      base = File.dirname(File.expand_path(path))
      File.foreach(path, chomp: true).filter_map do |line|
        entry = line.strip
        next if entry.empty? || entry.start_with?('#')

        absolute_entry(entry, base)
      end
    end

    def append_to(playlist, path)
      entries = load(path)
      entries.each { |entry| playlist.add_track(entry) }
      entries.size
    end

    def extinf(track)
      seconds = track.duration.to_i
      label = track.to_s.gsub(/[\r\n]/, ' ')
      "#EXTINF:#{seconds},#{label}"
    end
    private_class_method :extinf

    def absolute_entry(entry, base)
      return entry if FileUri.uri?(entry) || Pathname.new(entry).absolute?

      File.expand_path(entry, base)
    end
    private_class_method :absolute_entry
  end
end
