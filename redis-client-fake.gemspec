# frozen_string_literal: true

require_relative "lib/redis/client/fake/version"

Gem::Specification.new do |spec|
  spec.name = "redis-client-fake"
  spec.version = Redis::Client::Fake::VERSION
  spec.authors = ["Craig McNamara"]
  spec.email = ["craig@monami.io"]

  spec.summary = "An in-memory backend for redis-client, similar to Fakeredis"
  spec.description = "Provides a fake Redis driver for redis-client that stores data in-memory for testing purposes"
  spec.homepage = "https://github.com/mes-amis/redis-client-fake"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/mes-amis/redis-client-fake"
  spec.metadata["changelog_uri"] = "https://github.com/mes-amis/redis-client-fake/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "redis-client", ">= 0.11.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
