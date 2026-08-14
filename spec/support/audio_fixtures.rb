# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

# Generates short, real audio files for tests so playback specs run against
# actual decoded audio rather than mocks, without waiting on minute-long tracks.
module AudioFixtures
  module_function

  def fixture_dir
    @fixture_dir ||= File.join(Dir.tmpdir, 'loamp-spec-fixtures').tap do |dir|
      FileUtils.mkdir_p(dir)
    end
  end

  # A real WAV file containing `seconds` of a sine tone.
  def tone(seconds: 1, frequency: 440, name: nil)
    name ||= "tone-#{seconds}s-#{frequency}hz.wav"
    path = File.join(fixture_dir, name)
    return path if File.exist?(path)

    generate_tone(path, seconds, frequency)
    path
  end

  def generate_tone(path, seconds, frequency)
    samples = (44_100 * seconds).to_i
    pipeline = [
      'gst-launch-1.0', '-q',
      'audiotestsrc', 'wave=sine', "freq=#{frequency}", "num-buffers=#{(samples / 1024.0).ceil}",
      '!', 'audio/x-raw,rate=44100,channels=2',
      '!', 'wavenc',
      '!', 'filesink', "location=#{path}"
    ]
    raise "failed to generate audio fixture at #{path}" unless system(*pipeline)
  end

  # A real FLAC file carrying real Vorbis comments.
  def tagged_flac
    build_tagged('loamp-tagged.flac', 'flacenc') do |path|
      TagLib::FLAC::File.open(path) do |file|
        comment = file.xiph_comment(true)
        TAGS.each { |field, value| comment.add_field(field, value.to_s) }
        file.save
      end
    end
  end

  # A real Ogg Vorbis file carrying real Vorbis comments.
  def tagged_ogg
    build_tagged('loamp-tagged.ogg', 'vorbisenc ! oggmux') do |path|
      TagLib::Ogg::Vorbis::File.open(path) do |file|
        comment = file.tag
        TAGS.each { |field, value| comment.add_field(field, value.to_s) }
        file.save
      end
    end
  end

  TAGS = {
    'TITLE' => 'Fixture Song',
    'ARTIST' => 'Fixture Artist',
    'ALBUM' => 'Fixture Album',
    'ALBUMARTIST' => 'Fixture Album Artist',
    'GENRE' => 'Test Tone',
    'DATE' => '1999',
    'TRACKNUMBER' => '4',
    'TRACKTOTAL' => '11',
    'DISCNUMBER' => '2',
    'DISCTOTAL' => '3',
    'REPLAYGAIN_TRACK_GAIN' => '-6.50 dB',
  }.freeze

  # Real MBIDs, so a spec that wants to check one against MusicBrainz by hand
  # can: the release is Radiohead's "OK Computer", the artist is Radiohead.
  MUSICBRAINZ_ALBUM_ID = '0b6b4ba0-d36f-47bd-b4ea-6a5b91842d29'
  MUSICBRAINZ_ARTIST_ID = 'a74b1b7f-71a5-4011-9441-d0b5e4122711'

  # These live in fixtures of their own rather than in TAGS because the built
  # files are cached in the temporary directory between runs: adding a field to
  # a fixture that already exists on disk would not be picked up.
  def musicbrainz_flac
    build_tagged('loamp-musicbrainz.flac', 'flacenc') do |path|
      TagLib::FLAC::File.open(path) do |file|
        comment = file.xiph_comment(true)
        comment.add_field('MUSICBRAINZ_ALBUMID', MUSICBRAINZ_ALBUM_ID)
        comment.add_field('MUSICBRAINZ_ALBUMARTISTID', MUSICBRAINZ_ARTIST_ID)
        file.save
      end
    end
  end

  # The same identifiers in ID3v2, which has no frame for them and so keeps
  # them in user-defined TXXX frames keyed by description.
  def musicbrainz_mp3
    path = File.join(fixture_dir, 'loamp-musicbrainz.mp3')
    return path if File.exist?(path)

    FileUtils.cp(sample_mp3, path)
    TagLib::MPEG::File.open(path) do |file|
      tag = file.id3v2_tag(true)
      tag.add_frame(user_text_frame('MusicBrainz Album Id', MUSICBRAINZ_ALBUM_ID))
      tag.add_frame(user_text_frame('MusicBrainz Album Artist Id', MUSICBRAINZ_ARTIST_ID))
      file.save
    end
    path
  end

  def user_text_frame(description, value)
    TagLib::ID3v2::UserTextIdentificationFrame.new.tap do |frame|
      frame.description = description
      frame.text = value
    end
  end

  def build_tagged(name, encoder)
    path = File.join(fixture_dir, name)
    return path if File.exist?(path)

    pipeline = "audiotestsrc num-buffers=90 ! audio/x-raw,rate=44100,channels=2 ! " \
               "audioconvert ! #{encoder} ! filesink location=#{path}"
    raise "failed to encode #{name}" unless system("gst-launch-1.0 -q #{pipeline}")

    yield(path)
    path
  end

  # A track with exactly the tags a spec cares about, without needing a file
  # on disk that happens to carry them.
  def track_with(file_path: '/tmp/test.mp3', **tags)
    Loamp::Track.new(file_path, metadata: Loamp::Metadata.new(**tags))
  end

  # An engine that runs the real pipeline but sends audio nowhere, so specs
  # exercise genuine playback without making noise.
  def silent_engine
    Loamp::AudioEngine.new(audio_sink: 'fakesink sync=true')
  end

  # Path to a real-world MP3 shipped with the repo. Carries no tags at all,
  # which makes it the fixture for fallback behaviour.
  def sample_mp3
    File.expand_path('../../test_files/turkey_in_the_straw.mp3', __dir__)
  end

  # A commercial MP3 with a complete ID3v2 tag and embedded cover art.
  def sample_mp3_with_tags
    File.expand_path('../../test_files/03 - Relationships.mp3', __dir__)
  end
end
