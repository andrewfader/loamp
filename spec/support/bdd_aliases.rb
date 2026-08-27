# frozen_string_literal: true

# BDD-friendly aliases: scenario / given / when / then read as Cucumber-style steps
# while staying pure RSpec (no Cucumber gem required).
module BddAliases
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def scenario(description, *args, &block)
      it(description, *args, &block)
    end

    def feature(description, *args, &block)
      describe(description, *args, &block)
    end
  end
end

RSpec.configure do |config|
  config.include BddAliases
  config.extend BddAliases::ClassMethods
end
