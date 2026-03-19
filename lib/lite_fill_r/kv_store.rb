# frozen_string_literal: true

require "json"
require "sqlite3"

module LiteFillR
  # Key-Value store backed by SQLite
  # Provides a simple key-value interface with JSON serialization
  # for storing arbitrary Ruby objects.
  class KvStore
    # @param db [SQLite3::Database]
    def initialize(db)
      @db = db
      initialize_schema
    end

    # Create a KvStore from an existing database connection
    # @param db [SQLite3::Database]
    # @return [KvStore]
    def self.from_database(db)
      new(db)
    end

    # Initialize the database schema
    def initialize_schema
      @db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS kv_store (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        );

        CREATE INDEX IF NOT EXISTS idx_kv_store_created_at
        ON kv_store(created_at);
      SQL
    end

    # Set a key-value pair
    # @param key [String]
    # @param value [Object] Will be JSON serialized
    # @return [void]
    # @example
    #   kv.set('user:123', { 'name' => 'Alice', 'age' => 30 })
    def set(key, value)
      serialized = JSON.generate(value)
      @db.execute(<<~SQL, [key, serialized])
        INSERT INTO kv_store (key, value, updated_at)
        VALUES (?, ?, strftime('%s', 'now'))
        ON CONFLICT(key) DO UPDATE SET
          value = excluded.value,
          updated_at = strftime('%s', 'now')
      SQL
    end

    # Get a value by key
    # @param key [String]
    # @param default [Object] Default value if key is not found
    # @return [Object, nil] The deserialized value, or default if key doesn't exist
    # @example
    #   user = kv.get('user:123')
    #   puts user['name'] if user
    def get(key, default = nil)
      row = @db.get_first_row("SELECT value FROM kv_store WHERE key = ?", key)
      return default unless row

      JSON.parse(row[0])
    rescue JSON::ParserError
      default
    end

    # List all keys matching a prefix
    # @param prefix [String]
    # @return [Array<Hash>] List of hashes with 'key' and 'value' fields
    # @example
    #   users = kv.list('user:')
    #   users.each { |item| puts "#{item['key']}: #{item['value']}" }
    def list(prefix)
      # Escape special characters for LIKE query
      escaped = prefix.gsub("\\", "\\\\\\\\").gsub("%", "\\%").gsub("_", "\\_")
      pattern = "#{escaped}%"

      rows = @db.execute(<<~SQL, [pattern])
        SELECT key, value FROM kv_store 
        WHERE key LIKE ? ESCAPE '\\'
      SQL

      rows.map do |row|
        {
          "key" => row[0],
          "value" => JSON.parse(row[1])
        }
      rescue JSON::ParserError
        nil
      end.compact
    end

    # Delete a key-value pair
    # @param key [String]
    # @return [void]
    # @example
    #   kv.delete('user:123')
    def delete(key)
      @db.execute("DELETE FROM kv_store WHERE key = ?", key)
    end

    # Check if a key exists
    # @param key [String]
    # @return [Boolean]
    def key?(key)
      row = @db.get_first_row("SELECT 1 FROM kv_store WHERE key = ?", key)
      !row.nil?
    end
    alias exist? key?
    alias exists? key?

    # Get all keys
    # @return [Array<String>]
    def keys
      @db.execute("SELECT key FROM kv_store ORDER BY key ASC").map(&:first)
    end

    # Clear all key-value pairs
    # @return [void]
    def clear
      @db.execute("DELETE FROM kv_store")
    end
  end
end
