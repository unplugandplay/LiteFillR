# frozen_string_literal: true

require "json"
require "sqlite3"

module LiteFillR
  # Represents a single tool call record
  class ToolCall
    attr_reader :id, :name, :parameters, :result, :error, :status, :started_at, :completed_at, :duration_ms

    # @param id [Integer]
    # @param name [String]
    # @param parameters [Object, nil]
    # @param result [Object, nil]
    # @param error [String, nil]
    # @param status [String]
    # @param started_at [Integer]
    # @param completed_at [Integer, nil]
    # @param duration_ms [Integer, nil]
    def initialize(id:, name:, parameters: nil, result: nil, error: nil,
                   status: "pending", started_at: 0, completed_at: nil, duration_ms: nil)
      @id = id
      @name = name
      @parameters = parameters
      @result = result
      @error = error
      @status = status
      @started_at = started_at
      @completed_at = completed_at
      @duration_ms = duration_ms
    end

    # @return [Boolean]
    def pending?
      @status == "pending"
    end

    # @return [Boolean]
    def success?
      @status == "success"
    end

    # @return [Boolean]
    def error?
      @status == "error"
    end
  end

  # Tool call statistics
  class ToolCallStats
    attr_reader :name, :total_calls, :successful, :failed, :avg_duration_ms

    # @param name [String]
    # @param total_calls [Integer]
    # @param successful [Integer]
    # @param failed [Integer]
    # @param avg_duration_ms [Float]
    def initialize(name:, total_calls:, successful:, failed:, avg_duration_ms:)
      @name = name
      @total_calls = total_calls
      @successful = successful
      @failed = failed
      @avg_duration_ms = avg_duration_ms
    end
  end

  # Tool calls tracking backed by SQLite
  # Provides tracking and analytics for tool/function calls,
  # recording timing, parameters, results, and errors.
  class ToolCalls
    # @param db [SQLite3::Database]
    def initialize(db)
      @db = db
      initialize_schema
    end

    # Create a ToolCalls from an existing database connection
    # @param db [SQLite3::Database]
    # @return [ToolCalls]
    def self.from_database(db)
      new(db)
    end

    # Initialize the database schema
    def initialize_schema
      @db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS tool_calls (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          parameters TEXT,
          result TEXT,
          error TEXT,
          status TEXT NOT NULL DEFAULT 'pending',
          started_at INTEGER NOT NULL,
          completed_at INTEGER,
          duration_ms INTEGER
        );

        CREATE INDEX IF NOT EXISTS idx_tool_calls_name
        ON tool_calls(name);

        CREATE INDEX IF NOT EXISTS idx_tool_calls_started_at
        ON tool_calls(started_at);
      SQL
    end

    # Start a new tool call and mark it as pending
    # @param name [String] Name of the tool
    # @param parameters [Object, nil] Tool parameters (will be JSON serialized)
    # @return [Integer] ID of the created tool call record
    # @example
    #   call_id = tools.start('search', { 'query' => 'Ruby' })
    def start(name, parameters = nil)
      serialized_params = parameters ? JSON.generate(parameters) : nil
      started_at = Time.now.to_i

      @db.execute(<<~SQL, [name, serialized_params, started_at])
        INSERT INTO tool_calls (name, parameters, status, started_at)
        VALUES (?, ?, 'pending', ?)
      SQL

      @db.last_insert_row_id
    end

    # Mark a tool call as successful
    # @param call_id [Integer] ID of the tool call
    # @param result [Object, nil] Tool result (will be JSON serialized)
    # @return [void]
    # @example
    #   tools.success(call_id, { 'results' => [...] })
    def success(call_id, result = nil)
      serialized_result = result ? JSON.generate(result) : nil
      completed_at = Time.now.to_i

      row = @db.get_first_row("SELECT started_at FROM tool_calls WHERE id = ?", call_id)
      raise ArgumentError, "Tool call with ID #{call_id} not found" unless row

      duration_ms = (completed_at - row[0]) * 1000

      @db.execute(<<~SQL, [serialized_result, completed_at, duration_ms, call_id])
        UPDATE tool_calls
        SET status = 'success', result = ?, completed_at = ?, duration_ms = ?
        WHERE id = ?
      SQL
    end

    # Mark a tool call as failed
    # @param call_id [Integer] ID of the tool call
    # @param error [String] Error message
    # @return [void]
    # @example
    #   tools.error(call_id, 'Connection timeout')
    def error(call_id, error)
      completed_at = Time.now.to_i

      row = @db.get_first_row("SELECT started_at FROM tool_calls WHERE id = ?", call_id)
      raise ArgumentError, "Tool call with ID #{call_id} not found" unless row

      duration_ms = (completed_at - row[0]) * 1000

      @db.execute(<<~SQL, [error, completed_at, duration_ms, call_id])
        UPDATE tool_calls
        SET status = 'error', error = ?, completed_at = ?, duration_ms = ?
        WHERE id = ?
      SQL
    end

    # Record a completed tool call in one operation
    # Either result or error should be provided, not both.
    # @param name [String] Name of the tool
    # @param started_at [Integer] Unix timestamp when the call started
    # @param completed_at [Integer] Unix timestamp when the call completed
    # @param parameters [Object, nil] Tool parameters (will be JSON serialized)
    # @param result [Object, nil] Tool result (will be JSON serialized)
    # @param error [String, nil] Error message if the call failed
    # @return [Integer] ID of the created tool call record
    # @example
    #   call_id = tools.record(
    #     'search',
    #     started_at: 1234567890,
    #     completed_at: 1234567892,
    #     parameters: { 'query' => 'Ruby' },
    #     result: { 'results' => [...] }
    #   )
    def record(name, started_at:, completed_at:, parameters: nil, result: nil, error: nil)
      serialized_params = parameters ? JSON.generate(parameters) : nil
      serialized_result = result ? JSON.generate(result) : nil
      duration_ms = (completed_at - started_at) * 1000
      status = error ? "error" : "success"

      @db.execute(<<~SQL, [name, serialized_params, serialized_result, error, status, started_at, completed_at, duration_ms])
        INSERT INTO tool_calls (
          name, parameters, result, error, status,
          started_at, completed_at, duration_ms
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL

      @db.last_insert_row_id
    end

    # Get a specific tool call by ID
    # @param call_id [Integer]
    # @return [ToolCall, nil]
    # @example
    #   call = tools.get(123)
    #   puts "Tool: #{call.name}, Status: #{call.status}" if call
    def get(call_id)
      row = @db.get_first_row("SELECT * FROM tool_calls WHERE id = ?", call_id)
      return nil unless row

      row_to_tool_call(row)
    end

    # Query tool calls by name
    # @param name [String] Name of the tool
    # @param limit [Integer, nil] Maximum number of results
    # @return [Array<ToolCall>] List ordered by most recent first
    # @example
    #   calls = tools.get_by_name('search', limit: 10)
    #   calls.each { |call| puts "ID: #{call.id}, Status: #{call.status}" }
    def get_by_name(name, limit: nil)
      sql = <<~SQL
        SELECT * FROM tool_calls
        WHERE name = ?
        ORDER BY started_at DESC
      SQL
      sql += " LIMIT #{limit.to_i}" if limit

      rows = @db.execute(sql, name)
      rows.map { |row| row_to_tool_call(row) }
    end

    # Query recent tool calls
    # @param since [Integer] Unix timestamp to filter calls after
    # @param limit [Integer, nil] Maximum number of results
    # @return [Array<ToolCall>] List ordered by most recent first
    # @example
    #   since = Time.now.to_i - 3600
    #   calls = tools.get_recent(since)
    def get_recent(since, limit: nil)
      sql = <<~SQL
        SELECT * FROM tool_calls
        WHERE started_at > ?
        ORDER BY started_at DESC
      SQL
      sql += " LIMIT #{limit.to_i}" if limit

      rows = @db.execute(sql, since)
      rows.map { |row| row_to_tool_call(row) }
    end

    # Get performance statistics for all tools
    # Only includes completed calls (success or error), not pending ones.
    # @return [Array<ToolCallStats>] List ordered by total calls descending
    # @example
    #   stats = tools.get_stats
    #   stats.each do |stat|
    #     puts "#{stat.name}: #{stat.total_calls} calls, #{stat.avg_duration_ms.round(2)}ms avg"
    #   end
    def get_stats
      rows = @db.execute(<<~SQL)
        SELECT
          name,
          COUNT(*) as total_calls,
          SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) as successful,
          SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END) as failed,
          AVG(duration_ms) as avg_duration_ms
        FROM tool_calls
        WHERE status != 'pending'
        GROUP BY name
        ORDER BY total_calls DESC
      SQL

      rows.map do |row|
        ToolCallStats.new(
          name: row[0],
          total_calls: row[1],
          successful: row[2],
          failed: row[3],
          avg_duration_ms: row[4] || 0.0
        )
      end
    end

    private

    # Convert database row to ToolCall object
    # @param row [Array]
    # @return [ToolCall]
    def row_to_tool_call(row)
      ToolCall.new(
        id: row[0],
        name: row[1],
        parameters: row[2] ? JSON.parse(row[2]) : nil,
        result: row[3] ? JSON.parse(row[3]) : nil,
        error: row[4],
        status: row[5],
        started_at: row[6],
        completed_at: row[7],
        duration_ms: row[8]
      )
    rescue JSON::ParserError
      ToolCall.new(
        id: row[0],
        name: row[1],
        parameters: nil,
        result: nil,
        error: row[4],
        status: row[5],
        started_at: row[6],
        completed_at: row[7],
        duration_ms: row[8]
      )
    end
  end
end
