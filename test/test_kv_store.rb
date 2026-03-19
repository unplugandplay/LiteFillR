# frozen_string_literal: true

require_relative "test_helper"

class TestKvStore < LiteFillRTest
  def setup
    super
    @db = SQLite3::Database.new(test_db_path)
    @db.busy_timeout = 5000
    @kv = LiteFillR::KvStore.from_database(@db)
  end

  def teardown
    @db&.close
    super
  end

  def test_from_database_creates_schema
    tables = @db.execute(<<~SQL).flatten
      SELECT name FROM sqlite_master WHERE type='table' AND name='kv_store'
    SQL
    assert_includes tables, "kv_store"

    indexes = @db.execute(<<~SQL).flatten
      SELECT name FROM sqlite_master WHERE type='index' AND name='idx_kv_store_created_at'
    SQL
    assert_includes indexes, "idx_kv_store_created_at"
  end

  def test_set_and_get_string
    @kv.set("key1", "hello")
    assert_equal "hello", @kv.get("key1")
  end

  def test_set_and_get_integer
    @kv.set("counter", 42)
    assert_equal 42, @kv.get("counter")
  end

  def test_set_and_get_hash
    hash = { "name" => "Alice", "age" => 30 }
    @kv.set("user", hash)
    assert_equal hash, @kv.get("user")
  end

  def test_set_and_get_array
    arr = [1, 2, 3, "four"]
    @kv.set("list", arr)
    assert_equal arr, @kv.get("list")
  end

  def test_set_and_get_boolean
    @kv.set("active", true)
    @kv.set("inactive", false)
    assert_equal true, @kv.get("active")
    assert_equal false, @kv.get("inactive")
  end

  def test_set_and_get_nil
    @kv.set("nothing", nil)
    assert_nil @kv.get("nothing")
  end

  def test_get_non_existing_returns_nil
    assert_nil @kv.get("nonexistent")
  end

  def test_get_with_default
    assert_equal "default", @kv.get("nonexistent", "default")
    assert_equal 123, @kv.get("nonexistent", 123)
  end

  def test_update_existing_key
    @kv.set("key", "first")
    @kv.set("key", "second")
    assert_equal "second", @kv.get("key")
  end

  def test_delete
    @kv.set("key", "value")
    @kv.delete("key")
    assert_nil @kv.get("key")
  end

  def test_delete_non_existing
    @kv.delete("nonexistent") # should not raise
  end

  def test_key_predicate
    @kv.set("key", "value")
    assert @kv.key?("key")
    refute @kv.key?("nonexistent")
  end

  def test_exist_predicate_aliases
    @kv.set("key", "value")
    assert @kv.exist?("key")
    assert @kv.exists?("key")
  end

  def test_list_by_prefix
    @kv.set("user:1", "Alice")
    @kv.set("user:2", "Bob")
    @kv.set("config:theme", "dark")

    users = @kv.list("user:")
    assert_equal 2, users.length
    keys = users.map { |u| u["key"] }.sort
    assert_equal ["user:1", "user:2"], keys
  end

  def test_list_non_matching_prefix
    results = @kv.list("nonexistent:")
    assert_empty results
  end

  def test_keys
    @kv.set("c", 3)
    @kv.set("a", 1)
    @kv.set("b", 2)
    assert_equal ["a", "b", "c"], @kv.keys
  end

  def test_keys_empty_store
    assert_empty @kv.keys
  end

  def test_clear
    @kv.set("key1", "value1")
    @kv.set("key2", "value2")
    @kv.clear
    assert_empty @kv.keys
    assert_nil @kv.get("key1")
  end

  def test_nested_hash
    data = { "user" => { "profile" => { "name" => "Alice" } } }
    @kv.set("nested", data)
    assert_equal data, @kv.get("nested")
  end

  def test_unicode
    unicode = "Hello 世界 🌍"
    @kv.set("unicode", unicode)
    assert_equal unicode, @kv.get("unicode")
  end

  def test_empty_containers
    @kv.set("empty_hash", {})
    @kv.set("empty_array", [])
    assert_equal({}, @kv.get("empty_hash"))
    assert_equal [], @kv.get("empty_array")
  end

  def test_timestamp_tracking
    @kv.set("key", "value")
    row = @db.get_first_row("SELECT created_at FROM kv_store WHERE key = ?", "key")
    created = row[0].to_i
    assert created > 0

    sleep(0.5)
    before_update = Time.now.to_i
    @kv.set("key", "value2")
    row = @db.get_first_row("SELECT updated_at FROM kv_store WHERE key = ?", "key")
    updated = row[0].to_i
    assert updated >= before_update || updated > created
  end
end
