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
end
