require_relative "lib/ask/session/version"

Gem::Specification.new do |spec|
  spec.name = "ask-session"
  spec.version = Ask::Session::VERSION
  spec.authors = ["Kaka Ruto"]
  spec.email = ["kaka@myrrlabs.com"]

  spec.summary = "Event-sourced session state for the ask-rb ecosystem."
  spec.description = "Provides immutable session records, event envelopes, an in-memory store with concurrency guardrails, and a state reducer that reconstructs session snapshots from event history."

  spec.homepage = "https://github.com/ask-rb/ask-session"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.0"
end
