# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require_relative "../lib/lite_fill_r"

# Base class for all LiteFillR tests
class LiteFillRTest < Minitest::Test
  TEST_DB_DIR = File.expand_path("../test_dbs", __dir__)

  def setup
    super
    FileUtils.rm_rf(TEST_DB_DIR)
    FileUtils.mkdir_p(TEST_DB_DIR)
  end

  def teardown
    super
    FileUtils.rm_rf(TEST_DB_DIR)
    FileUtils.rm_rf(".agentfs")
  end

  def test_db_path(name = "test.db")
    File.join(TEST_DB_DIR, name)
  end

  def with_database(name = "test.db")
    path = test_db_path(name)
    db = SQLite3::Database.new(path)
    db.busy_timeout = 5000
    yield db
  ensure
    db&.close
  end

  def with_agentfs(name = "test.db", &block)
    path = test_db_path(name)
    LiteFillR::AgentFS.open(path: path, &block)
  end
end
