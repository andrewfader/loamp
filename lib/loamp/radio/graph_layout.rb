# frozen_string_literal: true

module Loamp
  module Radio
    class GraphLayout
      Node = Struct.new(:id, :label, :x, :y, :vx, :vy, :pinned, :local, keyword_init: true)
      Edge = Struct.new(:from, :to, :weight, keyword_init: true)

      attr_reader :nodes, :edges

      def initialize(random: Random.new)
        @random = random
        @nodes = {}
        @edges = []
      end

      def add_node(id, label: id, local: false)
        node = @nodes[id]
        if node
          node.label = label if better_label?(node, id, label)
          node.local = true if local
          return node
        end

        @nodes[id] = Node.new(id: id, label: label, x: @random.rand * 400,
                              y: @random.rand * 300, vx: 0, vy: 0,
                              pinned: false, local: local)
      end

      def add_edge(from, to, weight: 1)
        add_node(from)
        add_node(to)
        edge = Edge.new(from: from, to: to, weight: weight.to_f)
        @edges << edge unless @edges.any? { |known| known.from == from && known.to == to }
      end

      def step(delta = 1.0 / 60)
        repel
        spring
        @nodes.each_value do |node|
          next if node.pinned

          node.vx *= 0.86
          node.vy *= 0.86
          node.x += node.vx * delta
          node.y += node.vy * delta
        end
      end

      private

      def repel
        @nodes.values.combination(2) do |left, right|
          dx = left.x - right.x
          dy = left.y - right.y
          distance_sq = [(dx * dx) + (dy * dy), 25].max
          force = 18_000.0 / distance_sq
          distance = Math.sqrt(distance_sq)
          push(left, right, dx / distance * force, dy / distance * force)
        end
      end

      def spring
        @edges.each do |edge|
          left = @nodes[edge.from]
          right = @nodes[edge.to]
          dx = right.x - left.x
          dy = right.y - left.y
          distance = [Math.sqrt((dx * dx) + (dy * dy)), 1].max
          force = (distance - 110) * 0.04 * [edge.weight, 0.1].max
          push(left, right, dx / distance * -force, dy / distance * -force)
        end
      end

      def push(left, right, x_force, y_force)
        unless left.pinned
          left.vx += x_force
          left.vy += y_force
        end
        return if right.pinned

        right.vx -= x_force
        right.vy -= y_force
      end

      def better_label?(node, id, label)
        !label.to_s.empty? && label != id && (node.label.to_s.empty? || node.label == id)
      end
    end
  end
end
