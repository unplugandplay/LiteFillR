#!/usr/bin/env ruby
# frozen_string_literal: true

# Test runner for LiteFillR
# Usage: ruby test/run_tests.rb

require "fileutils"

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

# Clean up any leftover test databases
FileUtils.rm_rf(File.expand_path("../test_dbs", __dir__))
FileUtils.rm_rf(File.expand_path("../.agentfs", __dir__))

# Require all test files
test_dir = File.expand_path(__dir__)
Dir.glob(File.join(test_dir, "test_*.rb")).each do |file|
  require file
end
