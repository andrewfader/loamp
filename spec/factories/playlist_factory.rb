# frozen_string_literal: true

FactoryBot.define do
  factory :playlist, class: 'Loamp::Playlist' do
    initialize_with { new }

    trait :with_tracks do
      # Add tracks explicitly in examples that need them.
    end

    trait :empty do
      # Default state - no additional setup needed
    end

    trait :with_many_tracks do
      # Add many tracks in the test, not in the factory
    end
  end
end
