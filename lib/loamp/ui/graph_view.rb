# frozen_string_literal: true

module Loamp
  module UI
    class GraphView < Gtk::Box
      NODE_RADIUS = 18
      FEEDBACK_LABELS = { up: '👍', down: '👎', ban: 'Ban artist' }.freeze

      def initialize(similarity)
        super(:vertical, 6)
        @similarity = similarity
        @layout = Radio::GraphLayout.new
        @callbacks = {}
        @pending = Hash.new(0)
        @labels = {}
        @scale = 1.0
        @offset_x = 0
        @offset_y = 0
        build_toolbar
        build_canvas
      end

      def on_start_station(&block) = (@callbacks[:start_station] = block)
      def on_feedback(&block) = (@callbacks[:feedback] = block)
      def on_adventure_changed(&block) = (@callbacks[:adventure] = block)
      def on_now_playing(&block) = (@callbacks[:now_playing] = block)

      def seed(artist, mbid: nil, local: true)
        name = artist.to_s.strip
        return if name.empty?

        id = mbid || name
        @layout = Radio::GraphLayout.new
        @labels = { id => name }
        node = @layout.add_node(id, label: name, local: local)
        node.x = 200
        node.y = 150
        node.pinned = true
        @focus = name
        set_status("Looking up artists similar to #{name}…")
        @spinner.start
        expand(id, artist: name, mbid: mbid)
      end

      def shutdown
        @shutdown = true
        @pending.clear
        @spinner&.stop
      end

      private

      def build_toolbar
        @entry = Gtk::Entry.new
        @entry.placeholder_text = 'Search for an artist'
        @entry.hexpand = true
        @entry.signal_connect('activate') { seed(@entry.text) unless @entry.text.to_s.strip.empty? }

        @now_playing_button = Gtk::Button.new(label: 'This track')
        @now_playing_button.tooltip_text = 'Show artists similar to what is playing'
        @now_playing_button.signal_connect('clicked') { @callbacks[:now_playing]&.call }

        @spinner = Gtk::Spinner.new

        box = Gtk::Box.new(:horizontal, 6)
        box.margin_top = 12
        box.margin_start = 12
        box.margin_end = 12
        box.append(@entry)
        box.append(@now_playing_button)
        box.append(@spinner)
        %i[up down ban].each do |action|
          button = Gtk::Button.new(label: FEEDBACK_LABELS[action])
          button.signal_connect('clicked') { @callbacks[:feedback]&.call(action) }
          box.append(button)
        end
        adventure = Gtk::Scale.new(:horizontal, Gtk::Adjustment.new(0.5, 0, 1, 0.05, 0.1, 0))
        adventure.width_request = 120
        adventure.tooltip_text = 'Familiar ↔ adventurous'
        adventure.signal_connect('value-changed') do
          @callbacks[:adventure]&.call(adventure.value)
        end
        box.append(adventure)
        append(box)

        @status = Gtk::Label.new(idle_status)
        @status.xalign = 0
        @status.wrap = true
        @status.add_css_class('dim-label')
        @status.margin_start = 12
        @status.margin_end = 12
        append(@status)
      end

      def build_canvas
        @canvas = Gtk::DrawingArea.new
        @canvas.vexpand = true
        @canvas.hexpand = true
        @canvas.set_draw_func { |_area, context, width, height| draw(context, width, height) }
        add_gestures
        @canvas.add_tick_callback do
          @layout.step
          @canvas.queue_draw
          true
        end
        append(@canvas)
      end

      def add_gestures
        click = Gtk::GestureClick.new
        click.signal_connect('released') do |_gesture, presses, x, y|
          node = hit(x, y)
          next unless node

          if presses == 2
            @callbacks[:start_station]&.call(node.label, node.id)
          else
            set_status("Looking up artists similar to #{node.label}…")
            @spinner.start
            expand(node.id, artist: node.label, mbid: mbid_for(node.id))
          end
        end
        @canvas.add_controller(click)

        drag = Gtk::GestureDrag.new
        drag.signal_connect('drag-begin') do |_gesture, x, y|
          @dragged_node = hit(x, y)
          next unless @dragged_node

          @drag_origin = [@dragged_node.x, @dragged_node.y]
          @dragged_node.pinned = true
        end
        drag.signal_connect('drag-update') do |_gesture, dx, dy|
          next unless @dragged_node

          @dragged_node.x = @drag_origin[0] + (dx / @scale)
          @dragged_node.y = @drag_origin[1] + (dy / @scale)
          @dragged_node.vx = @dragged_node.vy = 0
          @canvas.queue_draw
        end
        drag.signal_connect('drag-end') do
          @dragged_node = nil
          @drag_origin = nil
        end
        @canvas.add_controller(drag)

        scroll = Gtk::EventControllerScroll.new(:vertical)
        scroll.signal_connect('scroll') do |_controller, _dx, dy|
          @scale = (@scale * (dy.positive? ? 0.9 : 1.1)).clamp(0.4, 2.5)
          true
        end
        @canvas.add_controller(scroll)
      end

      def expand(id, artist:, mbid: nil)
        generation = @pending[id] += 1
        Thread.new do
          edges = @similarity.expand(artist: artist, mbid: mbid || mbid_for(id))
          GLib::Idle.add { apply_edges(generation, id, artist, edges) }
        end
      end

      def apply_edges(generation, seed, artist, edges)
        return false if @shutdown || @pending[seed] != generation

        @spinner.stop
        edges.first(40).each do |target, weight, name|
          label = name.to_s.empty? ? (@labels[target] || target) : name
          @labels[target] = label
          local = @similarity.respond_to?(:local?) && @similarity.local?(target, label)
          @layout.add_node(target, label: label, local: local)
          @layout.add_edge(seed, target, weight: weight)
        end
        count = edges.length
        @status.text = if count.positive?
                         "#{count} artists similar to #{artist}. " \
                           'Click a node to expand it, double-click to start a station.'
                       else
                         "No similar artists found for #{artist}."
                       end
        false
      end

      def draw(context, width, height)
        context.set_source_rgb(0.45, 0.45, 0.45)
        context.set_line_width(1)
        @layout.edges.each do |edge|
          left = screen(@layout.nodes[edge.from], width, height)
          right = screen(@layout.nodes[edge.to], width, height)
          next unless left && right

          context.move_to(*left)
          context.line_to(*right)
          context.stroke
        end
        @layout.nodes.each_value { |node| draw_node(context, node, width, height) }
      end

      def draw_node(context, node, width, height)
        x_position, y_position = screen(node, width, height)
        return unless x_position

        if node.local
          context.set_source_rgb(0.2, 0.65, 0.9)
        else
          context.set_source_rgb(0.55, 0.55, 0.55)
        end
        context.arc(x_position, y_position, NODE_RADIUS, 0, Math::PI * 2)
        context.fill
        context.set_source_rgb(0.95, 0.95, 0.95)
        context.move_to(x_position + NODE_RADIUS + 3, y_position + 4)
        context.show_text(node.label.to_s)
      end

      def screen(node, width, height)
        return unless node

        [((node.x + @offset_x - 200) * @scale) + (width / 2),
         ((node.y + @offset_y - 150) * @scale) + (height / 2)]
      end

      def hit(x_position, y_position)
        width = @canvas.allocated_width
        height = @canvas.allocated_height
        @layout.nodes.values.find do |node|
          sx, sy = screen(node, width, height)
          next unless sx

          ((sx - x_position)**2) + ((sy - y_position)**2) <= NODE_RADIUS**2
        end
      end

      def mbid_for(id)
        id if id.to_s.match?(Metadata::MBID)
      end

      def set_status(text)
        @status.text = text
      end

      def idle_status
        'Play a song and click Similar artists, or search for an artist above.'
      end
    end
  end
end
