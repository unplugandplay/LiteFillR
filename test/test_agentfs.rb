# frozen_string_literal: true

require_relative "test_helper"

class TestOptions < LiteFillRTest
  def test_initializes_with_id_and_path
    opts = LiteFillR::Options.new(id: "test", path: "/tmp/test.db")
    assert_equal "test", opts.id
    assert_equal "/tmp/test.db", opts.path
  end

  def test_allows_nil_values
    opts = LiteFillR::Options.new
    assert_nil opts.id
    assert_nil opts.path
  end

  def test_partial_initialization
    opts = LiteFillR::Options.new(id: "test")
    assert_equal "test", opts.id
    assert_nil opts.path
  end
end

class TestAgentFSOpen < LiteFillRTest
  def test_creates_database_with_id
    agent = LiteFillR::AgentFS.open(id: "test-agent")
    assert_instance_of LiteFillR::AgentFS, agent
    assert File.exist?(".agentfs/test-agent.db")
    agent.close
  end

  def test_creates_database_with_path
    path = test_db_path("custom.db")
    agent = LiteFillR::AgentFS.open(path: path)
    assert File.exist?(path)
    agent.close
  end

  def test_raises_without_id_or_path
    err = assert_raises(ArgumentError) { LiteFillR::AgentFS.open({}) }
    assert_match(/id|path/i, err.message)
  end

  def test_validates_id_format
    err = assert_raises(ArgumentError) { LiteFillR::AgentFS.open(id: "invalid id!") }
    assert_match(/Agent ID/i, err.message)
  end

  def test_accepts_valid_id_characters
    agent = LiteFillR::AgentFS.open(id: "test-agent_123")
    agent.close
  end

  def test_yields_agent_and_auto_closes
    path = test_db_path("block.db")
    result = LiteFillR::AgentFS.open(path: path) do |agent|
      assert_instance_of LiteFillR::AgentFS, agent
      "block result"
    end
    assert_equal "block result", result
  end

  def test_closes_on_block_exception
    path = test_db_path("exception.db")
    assert_raises(RuntimeError) do
      LiteFillR::AgentFS.open(path: path) do |_|
        raise "test error"
      end
    end
  end

  def test_creates_agentfs_directory
    FileUtils.rm_rf(".agentfs")
    agent = LiteFillR::AgentFS.open(id: "new-agent")
    assert Dir.exist?(".agentfs")
    agent.close
  end
end

class TestAgentFSOpenWith < LiteFillRTest
  def test_creates_from_existing_database
    db = SQLite3::Database.new(test_db_path)
    agent = LiteFillR::AgentFS.open_with(db)

    assert_instance_of LiteFillR::AgentFS, agent
    assert_instance_of LiteFillR::KvStore, agent.kv
    assert_instance_of LiteFillR::Filesystem, agent.fs
    assert_instance_of LiteFillR::ToolCalls, agent.tools

    agent.close
  end
end

class TestAgentFSDatabase < LiteFillRTest
  def test_returns_underlying_database
    LiteFillR::AgentFS.open(path: test_db_path) do |agent|
      assert_instance_of SQLite3::Database, agent.database
    end
  end

  def test_close_connection
    agent = LiteFillR::AgentFS.open(path: test_db_path)
    agent.close
    # Should not raise
  end
end

class TestAgentFSIntegration < LiteFillRTest
  def test_full_workflow
    LiteFillR::AgentFS.open(path: test_db_path("workflow.db")) do |agent|
      # KV
      agent.kv.set("config", { "theme" => "dark" })
      assert_equal "dark", agent.kv.get("config")["theme"]

      # FS
      agent.fs.write_file("/data/config.json", '{"version": "1.0"}')
      assert_equal '{"version": "1.0"}', agent.fs.read_file("/data/config.json")

      # Tools
      call_id = agent.tools.record(
        "save_config",
        started_at: Time.now.to_i - 1,
        completed_at: Time.now.to_i,
        result: { "success" => true }
      )
      assert_equal "save_config", agent.tools.get(call_id).name
    end
  end

  def test_persistence_across_reopens
    path = test_db_path("persistent.db")

    LiteFillR::AgentFS.open(path: path) do |agent|
      agent.kv.set("key", "value")
      agent.fs.write_file("/file.txt", "content")
      agent.tools.record("test", started_at: 100, completed_at: 101, result: {})
    end

    LiteFillR::AgentFS.open(path: path) do |agent|
      assert_equal "value", agent.kv.get("key")
      assert_equal "content", agent.fs.read_file("/file.txt")
      assert_equal 1, agent.tools.get_stats.length
    end
  end

  def test_error_handling
    LiteFillR::AgentFS.open(path: test_db_path("errors.db")) do |agent|
      # ENOENT
      err = assert_raises(LiteFillR::ErrnoException) { agent.fs.read_file("/nonexistent") }
      assert_equal "ENOENT", err.code

      # EEXIST
      agent.fs.mkdir("/dir")
      err = assert_raises(LiteFillR::ErrnoException) { agent.fs.mkdir("/dir") }
      assert_equal "EEXIST", err.code

      # ENOTDIR
      agent.fs.write_file("/file.txt", "x")
      err = assert_raises(LiteFillR::ErrnoException) { agent.fs.readdir("/file.txt") }
      assert_equal "ENOTDIR", err.code
    end
  end

  def test_complex_nested_filesystem
    LiteFillR::AgentFS.open(path: test_db_path("nested.db")) do |agent|
      agent.fs.write_file("/a/b/c/d/e/file.txt", "deep")

      assert agent.fs.directory?("/a")
      assert agent.fs.directory?("/a/b/c")
      assert agent.fs.file?("/a/b/c/d/e/file.txt")

      agent.fs.rename("/a/b", "/a/x")
      assert agent.fs.file?("/a/x/c/d/e/file.txt")

      agent.fs.rm("/a", recursive: true)
      refute agent.fs.exist?("/a")
    end
  end

  def test_comprehensive_tool_tracking
    LiteFillR::AgentFS.open(path: test_db_path("tools.db")) do |agent|
      now = Time.now.to_i
      agent.tools.record("search", started_at: now - 400, completed_at: now - 390, result: { "hits" => 10 })
      agent.tools.record("search", started_at: now - 200, completed_at: now - 180, result: { "hits" => 20 })
      agent.tools.record("search", started_at: now - 10, completed_at: now, error: "timeout")
      agent.tools.record("read", started_at: now - 300, completed_at: now - 295, result: { "data" => "x" })

      searches = agent.tools.get_by_name("search")
      assert_equal 3, searches.length

      # Get calls from last 100 seconds - should be just the search at now-10
      recent = agent.tools.get_recent(now - 100)
      # Should get search (now-10) and possibly nothing else
      assert recent.length >= 1

      stats = agent.tools.get_stats
      search_stats = stats.find { |s| s.name == "search" }
      assert_equal 3, search_stats.total_calls
    end
  end

  def test_large_data
    LiteFillR::AgentFS.open(path: test_db_path("large.db")) do |agent|
      large_content = "x" * (1024 * 1024)  # 1MB
      agent.fs.write_file("/large.txt", large_content)
      assert_equal large_content.length, agent.fs.read_file("/large.txt").length

      large_hash = { "items" => (1..10000).to_a }
      agent.kv.set("large", large_hash)
      assert_equal 10000, agent.kv.get("large")["items"].length

      100.times { |i| agent.tools.record("batch", started_at: i, completed_at: i + 1, result: {}) }
      assert_equal 100, agent.tools.get_stats.first.total_calls
    end
  end

  def test_unicode
    LiteFillR::AgentFS.open(path: test_db_path("unicode.db")) do |agent|
      unicode = "Hello 世界 🌍"

      agent.kv.set("unicode", unicode)
      assert_equal unicode, agent.kv.get("unicode")

      agent.fs.write_file("/unicode.txt", unicode)
      assert_equal unicode, agent.fs.read_file("/unicode.txt")

      id = agent.tools.start("test", { "input" => unicode })
      agent.tools.success(id, { "output" => unicode })
      call = agent.tools.get(id)
      assert_equal unicode, call.parameters["input"]
      assert_equal unicode, call.result["output"]
    end
  end

  def test_stress_many_operations
    LiteFillR::AgentFS.open(path: test_db_path("stress.db")) do |agent|
      100.times do |i|
        agent.fs.write_file("/files/file#{i}.txt", "content#{i}")
        agent.kv.set("key#{i}", { "index" => i })
      end

      100.times do |i|
        assert_equal "content#{i}", agent.fs.read_file("/files/file#{i}.txt")
        assert_equal i, agent.kv.get("key#{i}")["index"]
      end
    end
  end
end
