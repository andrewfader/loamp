# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::TrackInfo do
  before(:each) do
    skip_if_no_gtk
  end

  let(:track_info) { described_class.new }
  
  # Create a real track for testing
  let(:test_track) do
    AudioFixtures.track_with(
      file_path: '/path/to/test.mp3',
      title: 'Test Song',
      artist: 'Test Artist',
      album: 'Test Album',
      track_number: 5,
    ).tap { |track| track.duration = 225 } # 3:45
  end

  describe '#initialize' do
    it 'creates the track info widget with proper GTK structure' do
      expect(track_info).to be_a(described_class)
      expect(track_info).to be_a(Gtk::Box)
    end

    it 'creates all required GTK components' do
      # Check that the widget has the expected labels
      title_label = track_info.instance_variable_get(:@title_label)
      artist_label = track_info.instance_variable_get(:@artist_label)
      album_label = track_info.instance_variable_get(:@album_label)
      duration_label = track_info.instance_variable_get(:@duration_label)
      track_number_label = track_info.instance_variable_get(:@track_number_label)
      details_box = track_info.instance_variable_get(:@details_box)

      expect(title_label).to be_a(Gtk::Label)
      expect(artist_label).to be_a(Gtk::Label)
      expect(album_label).to be_a(Gtk::Label)
      expect(duration_label).to be_a(Gtk::Label)
      expect(track_number_label).to be_a(Gtk::Label)
      expect(details_box).to be_a(Gtk::Box)
    end

    it 'creates the artwork widgets' do
      expect(track_info.instance_variable_get(:@artwork_picture)).to be_a(Gtk::Picture)
      expect(track_info.instance_variable_get(:@artwork_stack)).to be_a(Gtk::Stack)
    end

    it 'shows the placeholder until a track with artwork arrives' do
      stack = track_info.instance_variable_get(:@artwork_stack)

      expect(stack.visible_child_name).to eq('placeholder')
    end

    it 'shows embedded cover art for a track that has it' do
      track_info.update_track(Loamp::Track.new(AudioFixtures.sample_mp3_with_tags))

      stack = track_info.instance_variable_get(:@artwork_stack)
      picture = track_info.instance_variable_get(:@artwork_picture)

      expect(stack.visible_child_name).to eq('artwork')
      expect(picture.paintable).to be_a(Gdk::Texture)
    end

    it 'falls back to the placeholder for a track with no art' do
      track_info.update_track(Loamp::Track.new(AudioFixtures.sample_mp3))

      stack = track_info.instance_variable_get(:@artwork_stack)
      expect(stack.visible_child_name).to eq('placeholder')
    end


    it 'starts with cleared display' do
      title_label = track_info.instance_variable_get(:@title_label)
      artist_label = track_info.instance_variable_get(:@artist_label)
      album_label = track_info.instance_variable_get(:@album_label)
      duration_label = track_info.instance_variable_get(:@duration_label)
      track_number_label = track_info.instance_variable_get(:@track_number_label)
      
      # Check initial empty state - use text property which works for both markup and text
      expect(title_label.text).to eq('No Track Selected')
      expect(artist_label.text).to eq('')
      expect(album_label.text).to eq('')
      expect(duration_label.text).to eq('')
      expect(track_number_label.visible?).to be(false)
    end
  end

  # A network lookup finishes long after the track started, and the listener
  # may well have skipped on by then.
  describe '#show_artwork_from' do
    let(:track) { Loamp::Track.new(AudioFixtures.sample_mp3) }
    let(:cover) { File.join(Dir.mktmpdir('loamp-art'), 'cover.png') }

    # A real image, written by GdkPixbuf rather than pasted in as base64,
    # because the point of these examples is that it decodes.
    before { GdkPixbuf::Pixbuf.new(width: 2, height: 2).save(cover, 'png') }

    after { FileUtils.rm_rf(File.dirname(cover)) }

    def stack = track_info.instance_variable_get(:@artwork_stack)

    it 'draws art that arrived for the track being shown' do
      track_info.update_track(track)

      expect(track_info.show_artwork_from(track, Loamp::FileUri.for(cover))).to be true
      expect(stack.visible_child_name).to eq('artwork')
    end

    it 'ignores art for a track the listener has already skipped past' do
      track_info.update_track(track)
      track_info.update_track(Loamp::Track.new(AudioFixtures.sample_mp3_with_tags))

      expect(track_info.show_artwork_from(track, Loamp::FileUri.for(cover))).to be false
    end

    it 'ignores art that turned out not to be there' do
      track_info.update_track(track)

      expect(track_info.show_artwork_from(track, nil)).to be false
      expect(stack.visible_child_name).to eq('placeholder')
    end

    it 'keeps the placeholder when the file has gone since' do
      track_info.update_track(track)

      expect(track_info.show_artwork_from(track, 'file:///nowhere/cover.png')).to be false
      expect(stack.visible_child_name).to eq('placeholder')
    end

    it 'keeps the placeholder when what arrived is not an image' do
      File.binwrite(cover, 'not a PNG at all')
      track_info.update_track(track)

      expect(track_info.show_artwork_from(track, Loamp::FileUri.for(cover))).to be false
    end

    it 'ignores art that arrives after the pane was cleared' do
      track_info.update_track(track)
      track_info.clear

      expect(track_info.show_artwork_from(track, Loamp::FileUri.for(cover))).to be false
    end
  end

  describe '#update_track' do
    context 'with a valid track' do
      it 'updates all track information in GTK widgets' do
        track_info.update_track(test_track)

        title_label = track_info.instance_variable_get(:@title_label)
        artist_label = track_info.instance_variable_get(:@artist_label)
        album_label = track_info.instance_variable_get(:@album_label)
        duration_label = track_info.instance_variable_get(:@duration_label)
        track_number_label = track_info.instance_variable_get(:@track_number_label)

        # Check that the GTK labels were actually updated
        expect(title_label.text).to eq('Test Song')  # markup strips to text
        expect(artist_label.text).to eq('Test Artist')
        expect(album_label.text).to eq('Test Album')
        expect(duration_label.text).to eq('3:45')
        expect(track_number_label.text).to eq('Track 5')
        expect(track_number_label.visible?).to be(true)
      end

      it 'offers a one-click similar-artists action' do
        discovered = []
        track_info.on_discover { |track| discovered << track }
        track_info.update_track(test_track)
        button = track_info.instance_variable_get(:@similar_button)

        expect(button.visible?).to be(true)
        expect(button.sensitive?).to be(true)
        button.signal_emit('clicked')
        expect(discovered).to eq([test_track])
      end

      it 'shows track number when available' do
        track_info.update_track(test_track)
        track_number_label = track_info.instance_variable_get(:@track_number_label)
        
        expect(track_number_label.text).to eq('Track 5')
        expect(track_number_label.visible?).to be(true)
      end

      context 'when track number is not available' do
        it 'hides track number label' do
          track_info.update_track(AudioFixtures.track_with(title: 'No Number', track_number: nil))

          track_number_label = track_info.instance_variable_get(:@track_number_label)
          expect(track_number_label.visible?).to be(false)
        end
      end

      context 'when track number is zero' do
        it 'hides track number label' do
          track_info.update_track(AudioFixtures.track_with(title: 'Zero', track_number: 0))

          track_number_label = track_info.instance_variable_get(:@track_number_label)
          expect(track_number_label.visible?).to be(false)
        end
      end
    end

    context 'with nil track' do
      it 'clears the display' do
        # First populate with a track
        track_info.update_track(test_track)
        
        # Then clear with nil
        track_info.update_track(nil)

        title_label = track_info.instance_variable_get(:@title_label)
        artist_label = track_info.instance_variable_get(:@artist_label)
        album_label = track_info.instance_variable_get(:@album_label)
        duration_label = track_info.instance_variable_get(:@duration_label)
        track_number_label = track_info.instance_variable_get(:@track_number_label)

        expect(title_label.text).to eq('No Track Selected')
        expect(artist_label.text).to eq('')
        expect(album_label.text).to eq('')
        expect(duration_label.text).to eq('')
        expect(track_number_label.visible?).to be(false)
      end
    end

    context 'with track missing metadata' do
      let(:incomplete_track) do
        AudioFixtures.track_with(
          file_path: '/path/to/incomplete.mp3',
          title: nil, artist: nil, album: nil, track_number: nil,
        ).tap { |track| track.duration = 0 }
      end

      it 'handles missing metadata gracefully with fallback values' do
        track_info.update_track(incomplete_track)

        title_label = track_info.instance_variable_get(:@title_label)
        artist_label = track_info.instance_variable_get(:@artist_label)
        album_label = track_info.instance_variable_get(:@album_label)

        expect(title_label.text).to eq('Unknown Title')
        expect(artist_label.text).to eq('Unknown Artist')
        expect(album_label.text).to eq('Unknown Album')
      end
    end
  end

  describe '#clear' do
    it 'resets all GTK labels to default values' do
      # First populate with a track
      track_info.update_track(test_track)
      
      # Then clear
      track_info.clear

      title_label = track_info.instance_variable_get(:@title_label)
      artist_label = track_info.instance_variable_get(:@artist_label)
      album_label = track_info.instance_variable_get(:@album_label)
      duration_label = track_info.instance_variable_get(:@duration_label)
      track_number_label = track_info.instance_variable_get(:@track_number_label)

      expect(title_label.text).to eq('No Track Selected')
      expect(artist_label.text).to eq('')
      expect(album_label.text).to eq('')
      expect(duration_label.text).to eq('')
      expect(track_number_label.visible?).to be(false)
    end
  end

  describe 'markup escaping' do
    let(:track_with_special_chars) do
      AudioFixtures.track_with(
        file_path: '/path/to/special.mp3',
        title: 'Song & Title <test>',
        artist: 'Artist & Name',
        album: 'I quit',
        track_number: 1,
      ).tap { |track| track.duration = 225 }
    end

    it 'properly escapes special characters in markup' do
      track_info.update_track(track_with_special_chars)
      
      title_label = track_info.instance_variable_get(:@title_label)
      
      # The text should be escaped when displayed
      expect(title_label.text).to eq('Song & Title <test>')
      
      # But the markup should have escaping applied internally
      # We can't directly test the markup property, but we can verify
      # that it doesn't cause GTK errors by accessing the text
      expect { title_label.text }.not_to raise_error
    end
  end
end
