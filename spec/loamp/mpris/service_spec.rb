# frozen_string_literal: true

require 'spec_helper'

# Exercised against a real session bus rather than a mocked one: the whole
# point of this class is that GDBus accepts what it hands over, and a double
# would happily accept a malformed variant that dbus-daemon would reject.
RSpec.describe Loamp::Mpris::Service do
  let(:playlist) { Loamp::Playlist.new }
  let(:engine) { AudioFixtures.silent_engine }
  let(:player) { Loamp::Player.new(playlist, engine: engine) }
  let(:adapter) { Loamp::Mpris::Adapter.new(player) }
  let(:bus_name) { "org.mpris.MediaPlayer2.loamp.spec#{Process.pid}" }
  let(:service) { described_class.new(adapter, bus_name: bus_name) }

  # A pipeline left running past the end of an example goes on emitting into
  # an engine nothing references any more, which GStreamer answers with a
  # segfault rather than an exception.
  after { engine.shutdown }

  let(:player_interface) { Loamp::Mpris::PLAYER_INTERFACE }
  let(:object_path) { Loamp::Mpris::OBJECT_PATH }

  before { skip 'no D-Bus session bus available' unless session_bus }

  after { service.stop }

  describe '#start' do
    it 'takes the MPRIS name on the bus' do
      expect(service.start).to be true
      expect(service).to be_running
      expect(name_has_owner?(bus_name)).to be true
    end

    it 'is idempotent' do
      service.start

      expect { service.start }.not_to change(service, :running?).from(true)
    end

    it 'reports failure rather than raising when there is no bus' do
      allow(Gio).to receive(:bus_get_sync).and_raise(GLib::Error.new('no bus'))

      expect(service.start).to be false
      expect(service).not_to be_running
    end

    it 'exports both MPRIS interfaces' do
      service.start

      xml = introspect

      expect(xml).to include('org.mpris.MediaPlayer2"')
      expect(xml).to include('org.mpris.MediaPlayer2.Player"')
    end
  end

  describe '#stop' do
    it 'gives the name back' do
      service.start
      service.stop

      expect(service).not_to be_running
      expect(name_has_owner?(bus_name)).to be false
    end

    it 'is safe to call when it never started' do
      expect { service.stop }.not_to raise_error
    end
  end

  describe 'properties over the bus' do
    before { service.start }

    it 'answers a Get' do
      expect(get_property('PlaybackStatus')).to eq('Stopped')
    end

    # ruby-gnome cannot convert an a{sv} reply back into Ruby, so the two
    # dictionary-shaped answers are read with gdbus instead — which is closer
    # to how a real client sees them anyway.
    it 'answers GetAll with every property of the interface' do
      properties = gdbus('GetAll', player_interface)

      expect(properties).to include('CanControl', 'PlaybackStatus', 'Volume')
    end

    it 'serialises metadata as a dictionary a client can read' do
      playlist.add_track(AudioFixtures.tagged_flac)
      playlist.set_current_track(0)

      metadata = gdbus('Get', player_interface, 'Metadata')

      expect(metadata).to include('Fixture Song', 'mpris:trackid', 'xesam:artist')
    end

    it 'accepts a Set and applies it to the player' do
      set_property('Volume', '<0.5>')

      expect(player.volume).to eq(50)
    end

    it 'reports an unknown property as an error rather than crashing' do
      expect { get_property('Warp') }.to raise_error(StandardError)
    end
  end

  describe 'methods over the bus' do
    before do
      playlist.add_track(AudioFixtures.tone(seconds: 2))
      service.start
    end

    it 'starts playback' do
      call(player_interface, 'Play')
      engine.wait_for_state(:playing)

      expect(player).to be_playing
    end

    it 'passes arguments through' do
      call(player_interface, 'Play')
      engine.wait_for_state(:playing)

      call(player_interface, 'Seek', '(int64 1000000,)', '(x)')

      expect(player.position).to be_within(0.3).of(1.0)
    end

    it 'answers an unknown method with a D-Bus error instead of dying' do
      expect { call(player_interface, 'Rewind') }.to raise_error(StandardError, /Rewind|Unknown/)
    end
  end

  describe 'change announcements' do
    before { service.start }

    it 'emits PropertiesChanged for the track' do
      playlist.add_track(AudioFixtures.tone(seconds: 1))

      expect(service.track_changed).to be true
    end

    it 'emits PropertiesChanged for the state' do
      expect(service.state_changed).to be true
    end

    it 'emits PropertiesChanged for the volume' do
      expect(service.volume_changed).to be true
    end

    it 'emits PropertiesChanged for the play options' do
      expect(service.options_changed).to be true
    end

    it 'emits Seeked with the position in microseconds' do
      received = []
      subscription = subscribe(player_interface, 'Seeked') { |position| received << position }

      service.seeked(12.5)
      pump_until { !received.empty? }
      session_bus.signal_unsubscribe(subscription)

      expect(received.first).to eq([12_500_000])
    end
  end

  describe 'without a running service' do
    it 'ignores announcements instead of failing' do
      expect(service.track_changed).to be false
      expect(service.seeked(1)).to be false
    end
  end

  # --- Bus helpers ---------------------------------------------------------
  #
  # Every call is asynchronous and pumped from this thread: the service is
  # exported on the same main context, so a synchronous call would wait for a
  # reply that only this thread can produce.

  def session_bus
    return @session_bus if defined?(@session_bus)

    @session_bus = begin
      Gio.bus_get_sync(Gio::BusType::SESSION)
    rescue StandardError
      nil
    end
  end

  def call(interface, method, body = nil, signature = nil)
    parameters = body && GLib::Variant.parse(body, signature)
    reply = nil
    failure = nil

    session_bus.call(bus_name, object_path, interface, method, parameters, nil,
                     Gio::DBusCallFlags::NONE, 2000, nil) do |source, result|
      reply = source.call_finish(result)
    # ScriptError included: ruby-gnome raises NotImplementedError for reply
    # types it cannot convert, and letting that escape a GIO callback aborts
    # the whole run.
    rescue StandardError, ScriptError => e
      failure = e
    end

    pump_until { reply || failure }
    raise failure if failure

    reply
  end

  def get_property(name)
    call('org.freedesktop.DBus.Properties', 'Get',
         "('#{player_interface}', '#{name}')", '(ss)').first
  end

  def set_property(name, value)
    call('org.freedesktop.DBus.Properties', 'Set',
         "('#{player_interface}', '#{name}', #{value})", '(ssv)')
  end

  # Runs a gdbus call without blocking the main context the service answers
  # on, and returns whatever it printed.
  def gdbus(method, *arguments)
    skip 'gdbus is not installed' unless system('which gdbus > /dev/null 2>&1')

    read, write = IO.pipe
    pid = Process.spawn('gdbus', 'call', '--session', '--dest', bus_name,
                        '--object-path', object_path,
                        '--method', "org.freedesktop.DBus.Properties.#{method}",
                        *arguments, out: write, err: write)
    write.close
    pump_until { Process.waitpid(pid, Process::WNOHANG) }
    read.read.tap { read.close }
  end

  def introspect
    call('org.freedesktop.DBus.Introspectable', 'Introspect').first
  end

  def name_has_owner?(name)
    reply = nil
    session_bus.call('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
                     'NameHasOwner', GLib::Variant.parse("('#{name}',)", '(s)'), nil,
                     Gio::DBusCallFlags::NONE, 2000, nil) do |source, result|
      reply = source.call_finish(result)
    end

    pump_until { !reply.nil? }
    reply&.first
  end

  def subscribe(interface, signal, &block)
    session_bus.signal_subscribe(nil, interface, signal, object_path, nil,
                                 Gio::DBusSignalFlags::NONE) do |*arguments|
      block.call(arguments.last)
    end
  end

  def pump_until(timeout: 5)
    context = GLib::MainContext.default
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      context.iteration(false)
      sleep 0.005
    end
  end
end
