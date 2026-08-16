# frozen_string_literal: true

module Loamp
  module UI
    class LyricsView < Gtk::Box
      def initialize
        super(:vertical, 8)
        @rows = []
        @active_index = nil

        @heading = Gtk::Label.new('No lyrics loaded')
        @heading.add_css_class('title-3')
        @heading.margin_top = 12
        append(@heading)

        @list = Gtk::ListBox.new
        @list.selection_mode = :none
        @list.add_css_class('boxed-list')

        @plain = Gtk::Label.new
        @plain.wrap = true
        @plain.xalign = 0
        @plain.selectable = true
        @plain.margin_top = 12
        @plain.margin_bottom = 12
        @plain.margin_start = 16
        @plain.margin_end = 16

        @stack = Gtk::Stack.new
        @stack.add_named(@list, 'synced')
        @stack.add_named(@plain, 'plain')

        scroller = Gtk::ScrolledWindow.new
        scroller.hscrollbar_policy = :never
        scroller.vexpand = true
        scroller.margin_start = 12
        scroller.margin_end = 12
        scroller.margin_bottom = 12
        scroller.child = @stack
        append(scroller)
      end

      def show_document(track, document)
        clear_rows
        @active_index = nil
        @heading.text = document ? "Lyrics · #{track.title}" : "No lyrics for #{track.title}"
        return unless document

        if document.synced?
          document.lines.each { |line| add_line(line.last) }
          @document = document
          @stack.visible_child_name = 'synced'
        else
          @plain.text = document.plain.to_s
          @stack.visible_child_name = 'plain'
          @document = nil
        end
      end

      def update_position(position)
        return unless @document

        index = @document.lines.rindex { |time, _text| time <= position.to_f }
        return if index == @active_index

        @rows[@active_index]&.remove_css_class('accent') unless @active_index.nil?
        @active_index = index
        @rows[index]&.add_css_class('accent') unless index.nil?
      end

      def clear
        @document = nil
        @heading.text = 'No lyrics loaded'
        @plain.text = ''
        clear_rows
      end

      private

      def add_line(text)
        label = Gtk::Label.new(text.to_s.empty? ? '♪' : text)
        label.wrap = true
        label.xalign = 0
        label.margin_top = 7
        label.margin_bottom = 7
        label.margin_start = 12
        label.margin_end = 12
        @list.append(label)
        @rows << label
      end

      def clear_rows
        @list.remove(@list.first_child) while @list.first_child
        @rows.clear
      end
    end
  end
end
