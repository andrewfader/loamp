# frozen_string_literal: true

require 'fileutils'

# Captures a GTK widget through its render tree. Unlike a desktop screenshot,
# this is deterministic, works natively on Wayland, and never captures another
# application's pixels.
module ScreenshotHelper
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b

  def settle_gtk(iterations: 20)
    context = GLib::MainContext.default
    iterations.times do
      context.iteration(false) while context.pending?
      sleep 0.01
    end
  end

  def capture_widget(widget, name)
    width = widget.width
    height = widget.height
    raise "#{widget.class} is not allocated" unless width.positive? && height.positive?

    paintable = Gtk::WidgetPaintable.new(widget)
    snapshot = Gtk::Snapshot.new
    paintable.snapshot(snapshot, width, height)
    node = snapshot.to_node
    raise "#{widget.class} produced no render node" unless node

    renderer = Gsk::CairoRenderer.new
    renderer.realize_for_display(widget.display)
    bounds = Graphene::Rect.new.init(0, 0, width, height)
    texture = renderer.render_texture(node, bounds)
    path = screenshot_path(name)
    texture.save_to_png(path)
    renderer.unrealize

    expect(File.binread(path, PNG_SIGNATURE.bytesize)).to eq(PNG_SIGNATURE)
    expect(texture.width).to eq(width)
    expect(texture.height).to eq(height)
    expect(File.size(path)).to be > 1_000
    path
  end

  private

  def screenshot_path(name)
    root = ENV.fetch('LOAMP_SCREENSHOT_DIR', File.join(Dir.tmpdir, 'loamp-e2e-screenshots'))
    FileUtils.mkdir_p(root)
    File.join(root, "#{name}.png")
  end
end

RSpec.configure do |config|
  config.include ScreenshotHelper
end
