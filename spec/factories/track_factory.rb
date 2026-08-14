# frozen_string_literal: true

FactoryBot.define do
  factory :track, class: 'Loamp::Track' do
    transient do
      file_path { '/tmp/test_track.mp3' }
      duration { 180 }
    end

    initialize_with { new(file_path).tap { |t| t.duration = duration } }

    trait :with_different_path do
      transient do
        file_path { Faker::File.file_name(dir: '/tmp', ext: 'mp3') }
      end
    end

    trait :mp3_file do
      transient do
        file_path { Faker::File.file_name(dir: '/tmp', ext: 'mp3') }
      end
    end

    trait :flac_file do
      transient do
        file_path { Faker::File.file_name(dir: '/tmp', ext: 'flac') }
      end
    end

    trait :long_duration do
      after(:build) do |track|
        allow(track).to receive(:duration).and_return(rand(300..600))
      end
    end
  end
end
