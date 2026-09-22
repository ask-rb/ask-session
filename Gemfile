source "https://rubygems.org"

gemspec

group :test do
  gem "sqlite3"

  sibling = File.expand_path("../ask-state-providers", __dir__)
  gem "ask-state-providers", path: sibling if File.directory?(sibling)
end
