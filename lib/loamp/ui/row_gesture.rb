# frozen_string_literal: true

module Loamp
  module UI
    # How a list row's menu gets summoned, by pointer and by keyboard.
    #
    # Which row a click found is only knowable from the row itself: a list
    # recycles its widgets as it scrolls, and GTK exposes no way to ask a view
    # what sits at a point. So every row carries its own gesture, set up once
    # and reading whatever the row is bound to at the moment of the click —
    # which is what stops a menu acting on whatever happens to be selected
    # instead of on the row the listener pointed at.
    #
    # The keyboard comes at it from the opposite direction: there is no point
    # to look under, so the row is whatever the list has selected and the
    # anchor is worked back out of where the focus sits.
    module RowGesture
      module_function

      # +on_context+ is called with the list item, the widget the click landed
      # on and where in that widget it landed. A proc rather than a block: it
      # is called long after the method it was handed to has returned.
      def attach(widget, list_item, on_context = nil)
        return unless on_context

        gesture = Gtk::GestureClick.new
        gesture.button = 3
        gesture.signal_connect('pressed') do |_gesture, _count, x_position, y_position|
          on_context.call(list_item, widget, x_position, y_position)
        end
        widget.add_controller(gesture)
        gesture
      end

      # GTK owns each controller's C object, but its Ruby signal handler also
      # needs a live wrapper. The factory owns these references until a cell
      # is torn down, so scrolling cannot leak one controller per old row.
      def retain_for(factory)
        gestures = {}
        handler = factory.signal_connect('teardown') { |_source, item| gestures.delete(item) }
        factory.instance_variable_set(:@loamp_gestures, [gestures, handler])
        gestures
      end

      def release_for(factory)
        state = factory.instance_variable_get(:@loamp_gestures)
        return unless state

        gestures, handler = state
        factory.signal_handler_disconnect(handler)
        gestures.clear
        factory.instance_variable_set(:@loamp_gestures, nil)
      end

      # A click on a row arrives in that row's own coordinates. Anything
      # anchored to the list — a popover parented to it — wants them in the
      # list's, and an unallocated widget cannot answer at all.
      def point_in(source, target, x_position, y_position)
        point = [x_position, y_position]
        return point if source.nil? || target.nil? || source == target

        source.translate_coordinates(target, x_position, y_position) || point
      end

      # The keyboard's way to the same menu. Menu is the key made for it, and
      # Shift+F10 is what keyboards without one have always used; GTK's own
      # context menus answer to both, so a list that answered to only one
      # would be the odd one out.
      def menu_key?(keyval, state)
        return true if keyval == Gdk::Keyval::KEY_Menu

        keyval == Gdk::Keyval::KEY_F10 &&
          state.to_i.anybits?(Gdk::ModifierType::SHIFT_MASK.to_i)
      end

      # +on_menu+ is called with no arguments and answers whether it opened
      # anything; a menu that did not open leaves the key to whatever else
      # wanted it, rather than swallowing the press to no effect.
      def attach_menu_key(widget, on_menu = nil, &block)
        handler = on_menu || block
        return unless handler

        controller = Gtk::EventControllerKey.new
        controller.signal_connect('key-pressed') do |_controller, keyval, _code, state|
          next false unless menu_key?(keyval, state)

          handler.call ? true : false
        end
        widget.add_controller(controller)
      end

      # Where inside +widget+ a menu the keyboard asked for should point.
      #
      # An arrow key leaves the focus on the row it moved to, so that is where
      # the menu belongs — over the row it is about to act on, at its left edge
      # so the popover does not cover the name it is headed with. The focus can
      # be several widgets deep inside a row, and in a column view always is,
      # so anything below the list will do as the anchor. With nothing focused
      # inside it — the list was reached by mouse, or has just been filled —
      # the top of the list is the honest answer.
      def focus_point(widget)
        focus = widget&.root&.focus
        return [0, 0] unless focus && focus != widget && inside?(focus, widget)

        point_in(focus, widget, 0, focus.height / 2.0)
      end

      def inside?(child, ancestor)
        return false unless child && ancestor

        # Popover's introspected `parent` field can shadow Widget#parent.
        child == ancestor || child.ancestor?(ancestor)
      end
    end
  end
end
