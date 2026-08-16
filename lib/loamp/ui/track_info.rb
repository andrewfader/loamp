# frozen_string_literal: true

module Loamp
  module UI
    # The now-playing pane: cover art above the track's details.
    #
    # Artwork is the point of this pane, so it gets the space. Everything else
    # is typographic hierarchy using Adwaita's own style classes rather than
    # hand-rolled markup.
    class TrackInfo < Gtk::Box
      # The largest the artwork is ever decoded at. The widget itself is free
      # to render smaller when the window is short.
      ART_SIZE = 260

      # A floor small enough that the pane never forces the window taller than
      # it is, which libadwaita rightly complains about.
      MIN_ART_SIZE = 96

      PLACEHOLDER_ICON = 'folder-music-symbolic'

      def initialize
        super(:vertical, 12)
        add_css_class('loamp-track-info')
        @callbacks = {}

        create_widgets
        layout_widgets
        clear
      end

      def on_discover(&block)
        @callbacks[:discover] = block
        @similar_button.visible = true
      end

      def update_track(track)
        return clear unless track

        @title_label.text = track.title || 'Unknown Title'
        @artist_label.text = track.artist || 'Unknown Artist'
        @album_label.text = track.album || 'Unknown Album'
        @duration_label.text = track.duration_formatted

        update_track_number(track)
        update_artwork(track)
        @similar_button.sensitive = !track.artist.to_s.strip.empty?
      end

      def update_stream_metadata(metadata)
        @title_label.text = metadata[:title] if metadata[:title]
        @artist_label.text = metadata[:artist] if metadata[:artist]
        @album_label.text = metadata[:album] if metadata[:album]
      end

      # Draws cover art that arrived after the track started — a network lookup
      # finishing. Ignored when the listener has skipped on in the meantime,
      # which is the whole reason the pane remembers what it is showing.
      def show_artwork_from(track, url)
        return false unless url && @showing.equal?(track)

        show_texture(decode_texture(read_image(url)))
      end

      def clear
        @showing = nil
        @title_label.text = 'No Track Selected'
        @artist_label.text = ''
        @album_label.text = ''
        @duration_label.text = ''
        @track_number_label.hide
        @similar_button.sensitive = false
        show_placeholder_art
      end

      private

      def update_track_number(track)
        if track.track_number&.positive?
          @track_number_label.text = "Track #{track.track_number}"
          @track_number_label.show
        else
          @track_number_label.hide
        end
      end

      # Decoding happens here rather than in the resolver so the UI decides how
      # big a texture it needs.
      def update_artwork(track)
        # Remembered so that art arriving from the network later can be checked
        # against what the pane is actually showing before it is drawn.
        @showing = track

        image = Artwork.for(track)
        show_placeholder_art unless image && show_texture(decode_texture(image.data))
      rescue StandardError
        show_placeholder_art
      end

      def show_texture(texture)
        return false unless texture

        @artwork_picture.paintable = texture
        @artwork_stack.visible_child_name = 'artwork'
        true
      end

      # The art the cache found is a file on disk by the time it is announced.
      def read_image(url)
        path = FileUri.to_path(url)
        path && File.binread(path)
      rescue StandardError
        nil
      end

      # Cover art is routinely far larger than it is displayed, so it is scaled
      # down while decoding rather than after.
      def decode_texture(data)
        return nil if data.nil? || data.empty?

        loader = GdkPixbuf::PixbufLoader.new
        loader.signal_connect('size-prepared') do |source, width, height|
          scaled = scaled_dimensions(width, height)
          source.set_size(*scaled) if scaled
        end

        loader.write(data)
        loader.close

        pixbuf = loader.pixbuf
        pixbuf && Gdk::Texture.new(pixbuf)
      rescue StandardError
        nil
      end

      # Fits the image inside ART_SIZE without distorting it. Returns nil when
      # the image is already small enough to leave alone.
      def scaled_dimensions(width, height)
        largest = [width, height].max
        return nil if largest <= ART_SIZE || largest.zero?

        ratio = ART_SIZE.to_f / largest
        [(width * ratio).round, (height * ratio).round]
      end

      def show_placeholder_art
        @artwork_stack.visible_child_name = 'placeholder'
      end

      def create_widgets
        create_artwork_widgets

        @eyebrow_label = Gtk::Label.new('NOW PLAYING  •  DECK A')
        @eyebrow_label.add_css_class('loamp-kicker')

        @title_label = build_label('title-2')
        @title_label.wrap = true
        @title_label.max_width_chars = 30

        @artist_label = build_label('heading')
        @album_label = build_label('dim-label')
        @track_number_label = build_label('caption', 'dim-label')
        @duration_label = build_label('caption', 'dim-label')

        @similar_button = Gtk::Button.new(label: 'Similar artists')
        @similar_button.tooltip_text = 'Find artists similar to this track'
        @similar_button.halign = :center
        @similar_button.visible = false
        @similar_button.sensitive = false
        @similar_button.signal_connect('clicked') { @callbacks[:discover]&.call(@showing) }

        @details_box = Gtk::Box.new(:vertical, 4)
        @details_box.add_css_class('loamp-track-details')
      end

      def create_artwork_widgets
        @artwork_picture = Gtk::Picture.new
        @artwork_picture.content_fit = :contain
        @artwork_picture.can_shrink = true
        @artwork_picture.add_css_class('loamp-artwork')

        @artwork_placeholder = Gtk::Image.new(icon_name: PLACEHOLDER_ICON)
        @artwork_placeholder.pixel_size = MIN_ART_SIZE
        @artwork_placeholder.add_css_class('dim-label')

        @artwork_stack = Gtk::Stack.new
        @artwork_stack.add_named(@artwork_placeholder, 'placeholder')
        @artwork_stack.add_named(@artwork_picture, 'artwork')
        @artwork_stack.set_size_request(MIN_ART_SIZE, MIN_ART_SIZE)
        @artwork_stack.halign = :center
        @artwork_stack.valign = :center
        @artwork_stack.add_css_class('loamp-artwork-deck')
      end

      def build_label(*css_classes)
        label = Gtk::Label.new
        label.halign = :center
        label.ellipsize = :end
        css_classes.each { |name| label.add_css_class(name) }
        label
      end

      def layout_widgets
        append(@eyebrow_label)
        @artwork_stack.vexpand = true
        append(@artwork_stack)

        @details_box.halign = :center
        [@title_label, @artist_label, @album_label].each { |label| @details_box.append(label) }

        metadata = Gtk::Box.new(:horizontal, 6)
        metadata.halign = :center
        [@track_number_label, @duration_label].each do |label|
          label.add_css_class('loamp-chip')
          metadata.append(label)
        end
        @details_box.append(metadata)
        @details_box.append(@similar_button)

        append(@details_box)
      end
    end
  end
end
