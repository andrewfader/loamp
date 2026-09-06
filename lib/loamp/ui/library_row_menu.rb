# frozen_string_literal: true

module Loamp
  module UI
    # The right-click menu on a library row — a track, an album or an artist.
    #
    # What activating a row does is not guessable, so the menu spells all
    # three consequences out rather than leaving "double-click replaces the
    # queue, right-click appends" as folklore. The heading names what the
    # actions will act on, which matters most on an album or artist row: the
    # three words underneath stand for a whole record, not the line clicked.
    #
    # It exists as its own object because a popover's lifetime is the awkward
    # part, not its contents: one is built lazily and then re-pointed, since a
    # fresh Gtk::Popover per click leaves the previous one parented to the
    # list, and a popover finalised while still parented takes the process
    # down with it in some later, unrelated place.
    class LibraryRowMenu
      ITEMS = [
        [:play, 'Play', 'Start here, replacing the queue'],
        [:play_next, 'Play Next', 'Play right after the current track'],
        [:enqueue, 'Add to Queue', 'Add to the end of the queue'],
      ].freeze

      # +widget+ is what the popover attaches to; the block is handed the
      # chosen action and the row it was chosen for.
      def initialize(widget, &dispatch)
        @widget = widget
        @dispatch = dispatch
      end

      # Points the menu at (x, y) and opens it. Popping up a popover whose
      # widget is not yet inside a toplevel window segfaults, which is what
      # the guard is for.
      #
      # +source+ is the widget the click landed on when that is not the one
      # the popover hangs off — a row builds its own gesture, so the point
      # arrives in the row's coordinates and has to be moved into the list's.
      def show(row, x_position, y_position, source: nil, heading: nil)
        return false unless row && @widget.root

        @popover ||= build
        @row = row
        set_heading(heading)
        x, y = RowGesture.point_in(source, @widget, x_position, y_position)
        @popover.pointing_to = Gdk::Rectangle.new(x.to_i, y.to_i, 1, 1)
        @popover.popup
        true
      end

      def open?
        @popover&.visible? || false
      end

      # GTK will not unparent a popover on its parent's behalf.
      def shutdown
        @popover&.popdown
        @popover&.unparent
        @popover = nil
        @heading = nil
        @row = nil
      end

      private

      def build
        box = Gtk::Box.new(:vertical, 0)
        box.append(heading_label)
        ITEMS.each { |action, label, tooltip| box.append(button(action, label, tooltip)) }

        Gtk::Popover.new.tap do |popover|
          popover.child = box
          popover.set_parent(@widget)
        end
      end

      def heading_label
        @heading = Gtk::Label.new
        @heading.add_css_class('dim-label')
        @heading.add_css_class('caption')
        @heading.xalign = 0
        @heading.ellipsize = :end
        @heading.max_width_chars = 28
        @heading.margin_start = 8
        @heading.margin_end = 8
        @heading.margin_bottom = 4
        @heading
      end

      def set_heading(heading)
        return unless @heading

        @heading.text = heading.to_s
        @heading.visible = !heading.to_s.empty?
      end

      def button(action, label, tooltip)
        Gtk::Button.new(label: label).tap do |button|
          button.add_css_class('flat')
          button.tooltip_text = tooltip
          button.child.xalign = 0 if button.child.respond_to?(:xalign=)
          button.signal_connect('clicked') do
            @popover&.popdown
            @dispatch&.call(action, @row)
          end
        end
      end
    end
  end
end
