# frozen_string_literal: true

module Loamp
  module UI
    module LibraryNameFactory
      module_function

      def build
        Gtk::SignalListItemFactory.new.tap do |factory|
          factory.signal_connect('setup') { |_source, item| setup(item) }
          factory.signal_connect('bind') { |_source, item| bind(item) }
        end
      end

      def setup(list_item)
        row_box = Gtk::Box.new(:horizontal, 8)
        row_box.margin_top = 4
        row_box.margin_bottom = 4
        row_box.margin_start = 8
        row_box.margin_end = 8

        image = Gtk::Image.new
        image.pixel_size = 42
        image.visible = false

        labels = Gtk::Box.new(:vertical, 0)
        labels.hexpand = true
        labels.append(label)
        labels.append(label(secondary: true))
        row_box.append(image)
        row_box.append(labels)
        list_item.child = row_box
      end

      def bind(list_item)
        row_box = list_item.child
        image = row_box.first_child
        labels = row_box.last_child
        row = list_item.item
        labels.first_child.text = row.primary.to_s
        labels.last_child.text = row.secondary.to_s
        labels.last_child.visible = !row.secondary.to_s.empty?
        path = FileUri.to_path(row.art_url)
        image.set_from_file(path) if path
        image.visible = !path.nil?
      end

      def label(secondary: false)
        Gtk::Label.new.tap do |label|
          label.xalign = 0
          label.ellipsize = :end
          if secondary
            label.add_css_class('dim-label')
            label.add_css_class('caption')
          end
        end
      end
    end
  end
end
