# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "lite_fill_r"
  spec.version = "0.1.0"
  spec.authors = ["LiteFillR Contributors"]
  spec.summary = "A lightweight AgentFS implementation in pure Ruby"
  spec.description = "Filesystem, key-value store, and tool call audit trail for AI agents, backed by SQLite"
  spec.homepage = "https://github.com/unplugandplay/LiteFillR"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # Only external dependency - everything else uses standard library
  spec.add_dependency "sqlite3", "~> 2.0"

  spec.add_development_dependency "minitest", "~> 5.0"
end
