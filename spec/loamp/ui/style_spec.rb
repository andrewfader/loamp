# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Loamp::UI::Style do
  before { skip_if_no_gtk }

  # Restore whatever the session was using so specs do not leave the desktop
  # in a different colour scheme than they found it.
  around do |example|
    manager = Adw::StyleManager.default
    previous = manager.color_scheme
    example.run
    manager.color_scheme = previous
  end

  describe '.color_scheme=' do
    it 'follows the system preference by default' do
      described_class.color_scheme = :system

      expect(Adw::StyleManager.default.color_scheme).to eq(Adw::ColorScheme::DEFAULT)
    end

    it 'can force dark' do
      described_class.color_scheme = :dark

      expect(Adw::StyleManager.default.color_scheme).to eq(Adw::ColorScheme::FORCE_DARK)
    end

    it 'can force light' do
      described_class.color_scheme = :light

      expect(Adw::StyleManager.default.color_scheme).to eq(Adw::ColorScheme::FORCE_LIGHT)
    end

    it 'ignores a scheme it does not recognise' do
      described_class.color_scheme = :dark
      described_class.color_scheme = :nonsense

      expect(Adw::StyleManager.default.color_scheme).to eq(Adw::ColorScheme::FORCE_DARK)
    end
  end

  describe '.color_scheme' do
    it 'reports the scheme that was set' do
      described_class.color_scheme = :light

      expect(described_class.color_scheme).to eq(:light)
    end
  end

  describe '.dark?' do
    it 'reports dark after forcing dark' do
      described_class.color_scheme = :dark

      expect(described_class).to be_dark
    end
  end

  describe '.load_css' do
    it 'ignores a stylesheet that is not there' do
      expect { described_class.load_css('/nonexistent/style.css') }.not_to raise_error
    end

    it 'loads a real stylesheet without raising' do
      path = File.join(AudioFixtures.fixture_dir, 'test-style.css')
      File.write(path, '.loamp-test { color: red; }')

      expect { described_class.load_css(path) }.not_to raise_error
    end

    it 'survives a stylesheet with invalid syntax' do
      path = File.join(AudioFixtures.fixture_dir, 'broken-style.css')
      File.write(path, 'this is not valid css {{{')

      expect { described_class.load_css(path) }.not_to raise_error
    end
  end
end
