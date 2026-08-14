# frozen_string_literal: true

require 'gio2'

module Loamp
  module Mpris
    # The D-Bus half of MPRIS: owns the well-known name, exports the two
    # interfaces, routes calls into the Adapter, and announces changes.
    #
    # GIO is used rather than a D-Bus gem because it is already a dependency
    # and already runs on the GLib main loop the application spins.
    #
    # Nothing here raises outward. A machine with no session bus — a container,
    # a CI runner — must still get a working music player, just without media
    # key integration, so every entry point degrades to a quiet false.
    class Service
      attr_reader :adapter, :connection, :bus_name

      def initialize(adapter, bus_name: BUS_NAME, object_path: OBJECT_PATH)
        @adapter = adapter
        @bus_name = bus_name
        @object_path = object_path
        @registrations = []
        @owner_id = nil
        @connection = nil
      end

      def running?
        !@registrations.empty?
      end

      # Returns false rather than raising when there is no bus to talk to.
      def start(connection: nil)
        return true if running?

        @connection = connection || session_bus
        return false unless @connection

        export
        @owner_id = own_name
        running?
      rescue StandardError => e
        warn "MPRIS unavailable: #{e.message}"
        shutdown_partial_start
        false
      end

      def stop
        @registrations.each { |id| safely { @connection&.unregister_object(id) } }
        @registrations.clear
        safely { Gio.bus_unown_name(@owner_id) } if @owner_id
        @owner_id = nil
        @connection = nil
      end

      # --- Change announcements ---------------------------------------------
      #
      # The application wires these to the player's callbacks. Each one is a
      # no-op when MPRIS never started, so callers need no conditionals.

      def track_changed
        emit_properties_changed(PLAYER_INTERFACE, Adapter::TRACK_CHANGE_PROPERTIES)
      end

      def state_changed
        emit_properties_changed(PLAYER_INTERFACE, Adapter::STATE_CHANGE_PROPERTIES)
      end

      def volume_changed
        emit_properties_changed(PLAYER_INTERFACE, %w[Volume])
      end

      def options_changed
        emit_properties_changed(PLAYER_INTERFACE, %w[LoopStatus Shuffle])
      end

      # Position is not a signalling property; a jump is reported with this
      # signal instead.
      def seeked(seconds = nil)
        return false unless running?

        position = seconds ? Mpris.seconds_to_microseconds(seconds) : @adapter.position_microseconds
        # The trailing comma is what makes this a one-element tuple rather
        # than a parenthesised expression, and GVariant insists on it.
        emit(PLAYER_INTERFACE, 'Seeked', "(#{Variant.literal('x', position)},)", '(x)')
      end

      def emit_properties_changed(interface, names)
        return false unless running?

        changed = @adapter.properties(interface, names)
        body = "(#{Variant.quote(interface)}, #{Variant.dictionary_text(changed)}, @as [])"
        emit(PROPERTIES_INTERFACE, 'PropertiesChanged', body, '(sa{sv}as)')
      end

      private

      def session_bus
        Gio.bus_get_sync(Gio::BusType::SESSION)
      rescue StandardError => e
        warn "No session bus for MPRIS: #{e.message}"
        nil
      end

      def export
        node = Gio::DBusNodeInfo.new(INTERFACE_XML)

        [ROOT_INTERFACE, PLAYER_INTERFACE].each do |name|
          info = node.lookup_interface(name)
          raise "MPRIS interface #{name} missing from introspection XML" unless info

          # GDBus wants closures, so the handlers are wrapped rather than
          # passed as Method objects.
          @registrations << @connection.register_object(
            @object_path, info,
            ->(*arguments) { handle_call(*arguments) },
            ->(*arguments) { handle_get(*arguments) },
            ->(*arguments) { handle_set(*arguments) }
          )
        end
      end

      def own_name
        Gio.bus_own_name_on_connection(@connection, @bus_name, Gio::BusNameOwnerFlags::NONE)
      end

      # --- GDBus callbacks ---------------------------------------------------
      #
      # GDBus decides the shape of these: connection, sender and path lead
      # every one of them and are of no interest here, so each is destructured
      # rather than declared. A raise inside one unwinds through C, so they
      # catch their own errors and answer the caller instead.

      def handle_call(*call)
        interface, member, arguments, invocation = call[3..]
        @adapter.invoke(interface, member, Array(arguments))
        invocation.return_value(nil)
      rescue Adapter::UnknownMember => e
        invocation.return_dbus_error('org.freedesktop.DBus.Error.UnknownMethod', e.message)
      rescue StandardError => e
        invocation.return_dbus_error('org.freedesktop.DBus.Error.Failed', e.message)
      end

      def handle_get(*call)
        interface, name = call[3..]
        signature, value = @adapter.property(interface, name)
        Variant.build(signature, value)
      rescue StandardError => e
        warn "MPRIS could not read #{call[3]}.#{call[4]}: #{e.message}"
        nil
      end

      def handle_set(*call)
        interface, name, value = call[3..]
        @adapter.set_property(interface, name, unwrap(value))
        emit_properties_changed(interface, [name])
        true
      rescue StandardError => e
        warn "MPRIS could not write #{call[3]}.#{call[4]}: #{e.message}"
        false
      end

      # Property writes arrive boxed in a variant.
      def unwrap(value)
        value.respond_to?(:value) ? value.value : value
      end

      def emit(interface, signal, body, signature)
        parameters = GLib::Variant.parse(body, signature)
        @connection.emit_signal(nil, @object_path, interface, signal, parameters)
        true
      rescue StandardError => e
        warn "MPRIS could not emit #{interface}.#{signal}: #{e.message}"
        false
      end

      def shutdown_partial_start
        stop
      rescue StandardError
        nil
      end

      def safely
        yield
      rescue StandardError
        nil
      end
    end
  end
end
