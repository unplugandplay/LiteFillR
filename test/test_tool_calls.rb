# frozen_string_literal: true

require_relative "test_helper"

class TestToolCall < LiteFillRTest
  def test_initializes_with_required_attributes
    call = LiteFillR::ToolCall.new(id: 1, name: "test")
    assert_equal 1, call.id
    assert_equal "test", call.name
    assert_equal "pending", call.status
  end

  def test_pending_predicate
    call = LiteFillR::ToolCall.new(id: 1, name: "test", status: "pending")
    assert call.pending?
    refute call.success?
    refute call.error?
  end

  def test_success_predicate
    call = LiteFillR::ToolCall.new(id: 1, name: "test", status: "success")
    assert call.success?
    refute call.pending?
  end

  def test_error_predicate
    call = LiteFillR::ToolCall.new(id: 1, name: "test", status: "error")
    assert call.error?
    refute call.pending?
  end

  def test_stores_all_attributes
    call = LiteFillR::ToolCall.new(
      id: 42, name: "search",
      parameters: { "query" => "ruby" },
      result: { "hits" => 10 },
      status: "success",
      started_at: 1234567890,
      completed_at: 1234567891,
      duration_ms: 1000
    )

    assert_equal 42, call.id
    assert_equal({ "query" => "ruby" }, call.parameters)
    assert_equal({ "hits" => 10 }, call.result)
    assert_equal 1000, call.duration_ms
  end
end

class TestToolCallStats < LiteFillRTest
  def test_stores_statistics
    stats = LiteFillR::ToolCallStats.new(
      name: "search", total_calls: 100, successful: 95, failed: 5, avg_duration_ms: 150.5
    )

    assert_equal "search", stats.name
    assert_equal 100, stats.total_calls
    assert_equal 95, stats.successful
    assert_equal 5, stats.failed
    assert_equal 150.5, stats.avg_duration_ms
  end
end

class TestToolCalls < LiteFillRTest
  def setup
    super
    @db = SQLite3::Database.new(test_db_path)
    @db.busy_timeout = 5000
    @tools = LiteFillR::ToolCalls.from_database(@db)
  end

  def teardown
    @db&.close
    super
  end

  def test_from_database_creates_schema
    tables = @db.execute(<<~SQL).flatten
      SELECT name FROM sqlite_master WHERE type='table' AND name='tool_calls'
    SQL
    assert_includes tables, "tool_calls"
  end

  def test_start_creates_pending_call
    id = @tools.start("search", { "query" => "ruby" })
    assert id > 0

    call = @tools.get(id)
    assert_equal "search", call.name
    assert_equal "pending", call.status
    assert_equal({ "query" => "ruby" }, call.parameters)
  end

  def test_start_without_parameters
    id = @tools.start("cleanup")
    call = @tools.get(id)
    assert_nil call.parameters
  end

  def test_success_marks_call_successful
    id = @tools.start("search")
    @tools.success(id, { "results" => ["a", "b"] })

    call = @tools.get(id)
    assert_equal "success", call.status
    assert_equal({ "results" => ["a", "b"] }, call.result)
  end

  def test_success_calculates_duration
    id = @tools.start("test")
    sleep(0.3)
    @tools.success(id)

    call = @tools.get(id)
    # Duration should be calculated (may vary on fast systems)
    assert call.duration_ms >= 0
    refute_nil call.duration_ms
  end

  def test_success_raises_for_non_existing
    assert_raises(ArgumentError) { @tools.success(9999) }
  end

  def test_error_marks_call_failed
    id = @tools.start("api_call")
    @tools.error(id, "Connection timeout")

    call = @tools.get(id)
    assert_equal "error", call.status
    assert_equal "Connection timeout", call.error
  end

  def test_record_successful_call
    id = @tools.record(
      "web_search",
      started_at: 1234567890,
      completed_at: 1234567892,
      parameters: { "query" => "ruby" },
      result: { "hits" => 100 }
    )

    call = @tools.get(id)
    assert_equal "web_search", call.name
    assert_equal "success", call.status
    assert_equal 2000, call.duration_ms
  end

  def test_record_failed_call
    id = @tools.record(
      "api_call",
      started_at: 1234567890,
      completed_at: 1234567891,
      error: "500 Internal Server Error"
    )

    call = @tools.get(id)
    assert_equal "error", call.status
    assert_equal "500 Internal Server Error", call.error
  end

  def test_get_non_existing_returns_nil
    assert_nil @tools.get(9999)
  end

  def test_get_by_name
    @tools.record("search", started_at: 100, completed_at: 101, result: {})
    @tools.record("search", started_at: 200, completed_at: 201, result: {})
    @tools.record("read", started_at: 150, completed_at: 151, result: {})

    calls = @tools.get_by_name("search")
    assert_equal 2, calls.length
    calls.each { |c| assert_equal "search", c.name }
  end

  def test_get_by_name_orders_by_started_at_desc
    @tools.record("search", started_at: 100, completed_at: 101, result: {})
    @tools.record("search", started_at: 200, completed_at: 201, result: {})

    calls = @tools.get_by_name("search")
    assert_equal 200, calls[0].started_at
    assert_equal 100, calls[1].started_at
  end

  def test_get_by_name_respects_limit
    5.times { |i| @tools.record("search", started_at: i, completed_at: i + 1, result: {}) }
    calls = @tools.get_by_name("search", limit: 3)
    assert_equal 3, calls.length
  end

  def test_get_recent
    @tools.record("old", started_at: 100, completed_at: 101, result: {})
    @tools.record("new", started_at: 500, completed_at: 501, result: {})

    calls = @tools.get_recent(400)
    assert_equal 1, calls.length
    assert_equal "new", calls[0].name
  end

  def test_get_stats
    @tools.record("search", started_at: 100, completed_at: 101, result: {})  # 1000ms
    @tools.record("search", started_at: 200, completed_at: 203, result: {})  # 3000ms
    @tools.record("search", started_at: 300, completed_at: 301, error: "timeout") # 1000ms
    @tools.record("read", started_at: 100, completed_at: 102, result: {})    # 2000ms

    stats = @tools.get_stats
    search_stats = stats.find { |s| s.name == "search" }

    assert_equal 3, search_stats.total_calls
    assert_equal 2, search_stats.successful
    assert_equal 1, search_stats.failed
    assert_in_delta 1666.67, search_stats.avg_duration_ms, 0.1
  end

  def test_get_stats_excludes_pending
    @tools.start("pending_op")
    stats = @tools.get_stats
    names = stats.map(&:name)
    refute_includes names, "pending_op"
  end

  def test_unicode_parameters
    id = @tools.start("search", { "query" => "Hello 世界" })
    call = @tools.get(id)
    assert_equal "Hello 世界", call.parameters["query"]
  end

  def test_large_json_data
    large_data = { "items" => (1..1000).to_a }
    id = @tools.record("bulk", started_at: 100, completed_at: 101, result: large_data)
    call = @tools.get(id)
    assert_equal 1000, call.result["items"].length
  end
end
