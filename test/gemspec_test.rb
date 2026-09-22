# frozen_string_literal: true

require_relative "test_helper"

class GemspecTest < Minitest::Test
  def test_gemspec_loads
    spec = Gem::Specification.load("ask-session.gemspec")
    assert spec, "gemspec should load"
    assert_equal "ask-session", spec.name
    assert_equal "0.1.0", spec.version.to_s
    assert spec.required_ruby_version.to_s.include?("3.2")
  end

  def test_version_constant
    assert_equal "0.1.0", Ask::Session::VERSION
  end

  def test_no_runtime_dependencies
    spec = Gem::Specification.load("ask-session.gemspec")
    runtime_deps = spec.dependencies.select { |d| d.type == :runtime }
    assert_empty runtime_deps
  end

  def test_package_contents
    spec = Gem::Specification.load("ask-session.gemspec")
    files = spec.files

    assert_includes files, "lib/ask/session.rb"
    assert_includes files, "LICENSE"
    assert_includes files, "README.md"
    assert_includes files, "CHANGELOG.md"
    refute_includes files, "GOAL.md"
    refute files.any? { |f| f.start_with?("test/") }, "test files must not be packaged"
    assert(files.all? { |f| File.file?(f) }, "spec.files must contain only files")
  end

  def test_mfa_metadata
    spec = Gem::Specification.load("ask-session.gemspec")
    assert_equal "true", spec.metadata["rubygems_mfa_required"]
  end
end
