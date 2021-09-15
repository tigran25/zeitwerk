# frozen_string_literal: true

require_relative "lib/zeitwerk/version"

Gem::Specification.new do |spec|
  spec.name        = "zeitwerk"
  spec.summary     = "Efficient and thread-safe constant autoloader"
  spec.description = <<-EOS
    Zeitwerk implements constant autoloading with Ruby semantics. Each gem
    and application may have their own independent autoloader, with its own
    configuration, inflector, and logger. Supports autoloading,
    reloading, and eager loading.
  EOS

  spec.author   = "Xavier Noria"
  spec.email    = 'fxn@hashref.com'
  spec.license  = "MIT"
  spec.homepage = "https://github.com/fxn/zeitwerk"
  spec.files    = Dir["README.md", "MIT-LICENSE", "lib/**/*.rb"]
  spec.version  = Zeitwerk::VERSION
  spec.metadata = {
    "homepage_uri"    => "https://github.com/fxn/zeitwerk",
    "changelog_uri"   => "https://github.com/fxn/zeitwerk/blob/master/CHANGELOG.md",
    "source_code_uri" => "https://github.com/fxn/zeitwerk",
    "bug_tracker_uri" => "https://github.com/fxn/zeitwerk/issues"
  }

  spec.required_ruby_version = ">= 2.5"
end
