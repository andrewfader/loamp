# frozen_string_literal: true

module Loamp
  # MPRIS2: the D-Bus interface every Linux desktop uses to talk to a media
  # player. Implementing it is what makes the media keys work, puts the track
  # in the GNOME Shell lock screen widget, and lets playerctl drive playback.
  #
  # Spec: https://specifications.freedesktop.org/mpris-spec/latest/
  module Mpris
    BUS_NAME = 'org.mpris.MediaPlayer2.loamp'
    OBJECT_PATH = '/org/mpris/MediaPlayer2'

    ROOT_INTERFACE = 'org.mpris.MediaPlayer2'
    PLAYER_INTERFACE = "#{ROOT_INTERFACE}.Player".freeze
    PROPERTIES_INTERFACE = 'org.freedesktop.DBus.Properties'

    # Track identifiers must be D-Bus object paths, and the spec reserves this
    # one for "no track".
    NO_TRACK = "#{OBJECT_PATH}/TrackList/NoTrack".freeze
    TRACK_PATH_PREFIX = "#{OBJECT_PATH}/loamp/track/".freeze

    MICROSECONDS_PER_SECOND = 1_000_000

    # Position changes continuously during playback; announcing it as a
    # property change would flood the bus, so the spec has readers poll it and
    # listen for Seeked instead. Hence the EmitsChangedSignal annotation.
    INTERFACE_XML = <<~XML
      <node>
        <interface name="org.mpris.MediaPlayer2">
          <method name="Raise"/>
          <method name="Quit"/>
          <property name="CanQuit" type="b" access="read"/>
          <property name="CanRaise" type="b" access="read"/>
          <property name="HasTrackList" type="b" access="read"/>
          <property name="Identity" type="s" access="read"/>
          <property name="DesktopEntry" type="s" access="read"/>
          <property name="SupportedUriSchemes" type="as" access="read"/>
          <property name="SupportedMimeTypes" type="as" access="read"/>
        </interface>
        <interface name="org.mpris.MediaPlayer2.Player">
          <method name="Next"/>
          <method name="Previous"/>
          <method name="Pause"/>
          <method name="PlayPause"/>
          <method name="Stop"/>
          <method name="Play"/>
          <method name="Seek">
            <arg name="Offset" type="x" direction="in"/>
          </method>
          <method name="SetPosition">
            <arg name="TrackId" type="o" direction="in"/>
            <arg name="Position" type="x" direction="in"/>
          </method>
          <method name="OpenUri">
            <arg name="Uri" type="s" direction="in"/>
          </method>
          <signal name="Seeked">
            <arg name="Position" type="x"/>
          </signal>
          <property name="PlaybackStatus" type="s" access="read"/>
          <property name="LoopStatus" type="s" access="readwrite"/>
          <property name="Rate" type="d" access="readwrite"/>
          <property name="Shuffle" type="b" access="readwrite"/>
          <property name="Metadata" type="a{sv}" access="read"/>
          <property name="Volume" type="d" access="readwrite"/>
          <property name="Position" type="x" access="read">
            <annotation name="org.freedesktop.DBus.Property.EmitsChangedSignal" value="false"/>
          </property>
          <property name="MinimumRate" type="d" access="read"/>
          <property name="MaximumRate" type="d" access="read"/>
          <property name="CanGoNext" type="b" access="read"/>
          <property name="CanGoPrevious" type="b" access="read"/>
          <property name="CanPlay" type="b" access="read"/>
          <property name="CanPause" type="b" access="read"/>
          <property name="CanSeek" type="b" access="read"/>
          <property name="CanControl" type="b" access="read"/>
        </interface>
      </node>
    XML

    module_function

    def seconds_to_microseconds(seconds)
      (seconds.to_f * MICROSECONDS_PER_SECOND).round
    end

    def microseconds_to_seconds(microseconds)
      microseconds.to_i / MICROSECONDS_PER_SECOND.to_f
    end
  end
end
