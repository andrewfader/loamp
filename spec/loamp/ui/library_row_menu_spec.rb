# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::LibraryRowMenu do
  let(:host) { Gtk::Box.new(:vertical, 0) }
  let(:chosen) { [] }
  let(:row) { Object.new }
  let(:menu) { described_class.new(host) { |action, item| chosen << [action, item] } }

  after do
    menu.shutdown
    @window&.destroy
  end

  # A popover cannot be popped up until its widget has a toplevel above it.
  def in_a_window
    @window = Gtk::Window.new
    @window.child = host
    @window.present
    pump_layout
  end

  # Coordinates only translate once the widgets have been given a size.
  def pump_layout
    context = GLib::MainContext.default
    10.times { context.iteration(false) while context.pending? }
  end

  def popover
    menu.instance_variable_get(:@popover)
  end

  # The heading label sits above the three buttons.
  def children
    child = popover.child.first_child
    [].tap do |found|
      while child
        found << child
        child = child.next_sibling
      end
    end
  end

  def heading
    children.first
  end

  def buttons
    children.drop(1)
  end

  it 'stays shut while the list is not inside a window yet' do
    expect(menu.show(row, 5, 5)).to be(false)
    expect(menu).not_to be_open
  end

  it 'stays shut when there is no row under the pointer' do
    in_a_window

    expect(menu.show(nil, 5, 5)).to be(false)
  end

  it 'points at the click once the list is inside a window' do
    in_a_window

    expect(menu.show(row, 37, 21)).to be(true)
    expect([popover.pointing_to.x, popover.pointing_to.y]).to eq([37, 21])
  end

  it 'reuses one popover rather than parenting a fresh one per click' do
    in_a_window
    menu.show(row, 1, 1)
    first = popover

    menu.show(row, 9, 9)

    expect(popover).to equal(first)
  end

  it 'spells all three consequences out' do
    in_a_window
    menu.show(row, 1, 1)

    expect(buttons.map(&:label)).to eq(['Play', 'Play Next', 'Add to Queue'])
  end

  it 'hands back the chosen action along with the row it was chosen for' do
    in_a_window
    menu.show(row, 1, 1)

    buttons[1].signal_emit('clicked')

    expect(chosen).to eq([[:play_next, row]])
  end

  it 'closes as it acts' do
    in_a_window
    menu.show(row, 1, 1)

    buttons[0].signal_emit('clicked')

    expect(menu).not_to be_open
  end

  it 'names what the actions will act on' do
    in_a_window
    menu.show(row, 1, 1, heading: 'Days Are Gone')

    expect(heading.text).to eq('Days Are Gone')
    expect(heading.get_property('visible')).to be(true)
  end

  it 'keeps the heading out of the way when the row does not need one' do
    in_a_window
    menu.show(row, 1, 1, heading: 'Days Are Gone')
    menu.show(row, 1, 1)

    expect(heading.get_property('visible')).to be(false)
  end

  it 'moves a click made on a row into the list the popover hangs off' do
    inner = Gtk::Box.new(:vertical, 0)
    inner.margin_top = 12
    inner.margin_start = 8
    inner.width_request = 50
    inner.height_request = 20
    host.append(inner)
    host.width_request = 200
    host.height_request = 200
    in_a_window

    menu.show(row, 3, 5, source: inner)

    expect([popover.pointing_to.x, popover.pointing_to.y]).to eq([11, 17])
  end

  it 'falls back to the click as given when it came from the list itself' do
    in_a_window

    menu.show(row, 4, 6, source: host)

    expect([popover.pointing_to.x, popover.pointing_to.y]).to eq([4, 6])
  end

  it 'unparents itself, however often it is asked to' do
    in_a_window
    menu.show(row, 1, 1)

    expect { 2.times { menu.shutdown } }.not_to raise_error
  end
end
