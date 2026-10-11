# frozen_string_literal: true

module Loamp
  module UI
    # A row of toolbar groups that wraps onto further lines when narrow.
    #
    # Adw::WrapBox only exists from libadwaita 1.7; Ubuntu 24.04 ships 1.5.
    # There a non-selectable Gtk::FlowBox does the same job.
    module WrapBox
      module_function

      def new(spacing: 6)
        return adw_box(spacing) if defined?(Adw::WrapBox)

        flow_box(spacing)
      end

      def adw_box(spacing)
        box = Adw::WrapBox.new
        box.child_spacing = spacing
        box.line_spacing = spacing
        box
      end

      def flow_box(spacing)
        box = Gtk::FlowBox.new
        box.selection_mode = :none
        box.homogeneous = false
        box.column_spacing = spacing
        box.row_spacing = spacing
        # Keyboard focus should land on the entries and buttons, not on the
        # FlowBoxChild wrappers around them.
        box.define_singleton_method(:append) do |child|
          super(child)
          child.parent.focusable = false
        end
        box
      end
    end
  end
end
