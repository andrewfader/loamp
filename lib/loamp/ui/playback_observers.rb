# frozen_string_literal: true

module Loamp
  module UI
    module PlaybackObservers
      private

      def setup_player_callbacks
        @player.on_track_changed do |track|
          @track_info.update_track(track)
          update_window_title(track)
          refill_station_queue
        end
        @player.on_position_changed { |position, _duration| @lyrics_view.update_position(position) }
        @player.on_error { |message| notify("Playback failed: #{message}") }
        @player.on_stream_metadata { |metadata| show_stream_metadata(metadata) }
      end

      def show_stream_metadata(metadata)
        @track_info.update_stream_metadata(metadata)
        title = metadata[:title]
        set_title("#{title} - #{self.class::TITLE}") if title
      end
    end
  end
end
