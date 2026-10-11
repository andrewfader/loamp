# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::WrapBox do
  before { skip_if_no_gtk }

  it 'uses Adw::WrapBox when libadwaita provides it' do
    skip 'libadwaita older than 1.7' unless defined?(Adw::WrapBox)

    box = described_class.new(spacing: 4)

    expect(box).to be_a(Adw::WrapBox)
    expect([box.child_spacing, box.line_spacing]).to eq([4, 4])
  end

  it 'falls back to an unselectable FlowBox on older libadwaita' do
    box = described_class.flow_box(4)
    button = Gtk::Button.new(label: 'Go')
    box.append(button)

    expect(box).to be_a(Gtk::FlowBox)
    expect(box.selection_mode).to eq(Gtk::SelectionMode::NONE)
    expect([box.column_spacing, box.row_spacing]).to eq([4, 4])
    expect(button.parent).to be_a(Gtk::FlowBoxChild)
    expect(button.parent.focusable?).to be(false)
  end
end
