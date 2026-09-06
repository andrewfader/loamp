# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::RowGesture do
  let(:shift) { Gdk::ModifierType::SHIFT_MASK.to_i }
  let(:control) { Gdk::ModifierType::CONTROL_MASK.to_i }

  describe '.menu_key?' do
    it 'answers to the key made for it, with or without a modifier held' do
      expect(described_class.menu_key?(Gdk::Keyval::KEY_Menu, 0)).to be(true)
      expect(described_class.menu_key?(Gdk::Keyval::KEY_Menu, shift)).to be(true)
    end

    it 'answers to Shift+F10, for the keyboards without a Menu key' do
      expect(described_class.menu_key?(Gdk::Keyval::KEY_F10, shift)).to be(true)
    end

    # F10 on its own is the menubar's, and Ctrl+F10 is nobody's.
    it 'leaves F10 alone unless Shift is what is held' do
      expect(described_class.menu_key?(Gdk::Keyval::KEY_F10, 0)).to be(false)
      expect(described_class.menu_key?(Gdk::Keyval::KEY_F10, control)).to be(false)
    end

    it 'ignores every other key' do
      expect(described_class.menu_key?(Gdk::Keyval::KEY_space, 0)).to be(false)
      expect(described_class.menu_key?(Gdk::Keyval::KEY_F9, shift)).to be(false)
    end
  end

  describe '.attach_menu_key' do
    let(:widget) { Gtk::Box.new(:vertical, 0) }

    def press(keyval, state = 0)
      controller = widget.observe_controllers.to_a.grep(Gtk::EventControllerKey).first
      controller.signal_emit('key-pressed', keyval, 0, state)
    end

    it 'runs the handler on the menu key and claims the press' do
      opened = 0
      described_class.attach_menu_key(widget) { opened += 1 }

      expect(press(Gdk::Keyval::KEY_Menu)).to be(true)
      expect(opened).to eq(1)
    end

    # A handler that opened nothing has to leave the key for whoever else
    # wanted it, or the press is swallowed to no effect.
    it 'lets the press through when nothing was opened' do
      described_class.attach_menu_key(widget) { false }

      expect(press(Gdk::Keyval::KEY_Menu)).to be(false)
    end

    it 'leaves keys that are not the menu key alone' do
      opened = 0
      described_class.attach_menu_key(widget) { opened += 1 }

      expect(press(Gdk::Keyval::KEY_space)).to be(false)
      expect(opened).to be_zero
    end

    it 'attaches nothing at all without a handler' do
      described_class.attach_menu_key(widget)

      expect(widget.observe_controllers.to_a.grep(Gtk::EventControllerKey)).to be_empty
    end
  end

  describe '.focus_point' do
    let(:list) { Gtk::Box.new(:vertical, 0) }
    let(:row) { Gtk::Entry.new }

    after { @window&.destroy }

    def on_screen
      @window = Gtk::Window.new
      @window.set_default_size(300, 200)
      @window.child = list
      @window.present
      context = GLib::MainContext.default
      10.times { context.iteration(false) while context.pending? }
    end

    # The focus inside a row sits on a widget of its own -- an entry's text, a
    # column view's cell -- so the anchor is that widget's left edge rather
    # than an exact offset into the row. What has to hold is that the point
    # lands on the row the focus is on, and moves when the focus moves.
    it 'points at whichever row holds the focus' do
      second = Gtk::Entry.new
      list.append(row)
      list.append(second)
      on_screen

      row.grab_focus
      expect(described_class.focus_point(list).last).to be_between(*extent(row))

      second.grab_focus
      expect(described_class.focus_point(list).last).to be_between(*extent(second))
    end

    # Where a row sits inside the list, top and bottom.
    def extent(widget)
      top = described_class.point_in(widget, list, 0, 0).last
      [top, top + widget.height]
    end

    # Reaching the list by mouse leaves nothing in it focused, and the top of
    # the list is a better answer than refusing to open at all.
    it 'falls back to the top of the list when the focus is elsewhere' do
      outside = Gtk::Entry.new
      box = Gtk::Box.new(:vertical, 0)
      box.append(list)
      box.append(outside)
      @window = Gtk::Window.new
      @window.child = box
      @window.present
      outside.grab_focus

      expect(described_class.focus_point(list)).to eq([0, 0])
    end

    it 'falls back for a list that is not on screen at all' do
      expect(described_class.focus_point(list)).to eq([0, 0])
      expect(described_class.focus_point(nil)).to eq([0, 0])
    end
  end
end
