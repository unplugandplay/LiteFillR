# frozen_string_literal: true

require "sqlite3"
require "fileutils"

require_relative "lite_fill_r/constants"
require_relative "lite_fill_r/errors"
require_relative "lite_fill_r/guards"
require_relative "lite_fill_r/kv_store"
require_relative "lite_fill_r/tool_calls"
require_relative "lite_fill_r/filesystem"

module LiteFillR
  # Configuration options for opening a LiteFillR instance
  class Options
    attr_accessor :id, :path

    # @param id [String, nil] Unique identifier for the agent
    # @param path [String, nil] Explicit path to the database file
    def initialize(id: nil, path: nil)
      @id = id
      @path = path
    end
  end

  # LiteFillR - A filesystem and key-value store for AI agents
  # Provides a unified interface for persistent storage using SQLite,
  # with support for key-value storage, filesystem operations, and
  # tool call tracking.
  class AgentFS
    attr_reader :kv, :fs, :tools

    # Private constructor - use AgentFS.open() instead
    # @param db [SQLite3::Database]
    # @param kv [KvStore]
    # @param fs [Filesystem]
    # @param tools [ToolCalls]
    def initialize(db:, kv:, fs:, tools:)
      @db = db
      @kv = kv
      @fs = fs
      @tools = tools
    end

    # Open an agent filesystem
    # @param options [Options, Hash] Configuration options (id and/or path required)
    # @yieldparam agent [AgentFS] If a block is given, yields the agent and closes it after
    # @return [AgentFS, Object] Returns the agent if no block given, or the block result if block given
    # @raise [ArgumentError] If neither id nor path is provided, or if id contains invalid characters
    # @example Using id without block (creates .agentfs/my-agent.db)
    #   agent = LiteFillR::AgentFS.open(id: 'my-agent')
    #   # ... use agent ...
    #   agent.close
    # @example Using id with block (auto-closes)
    #   LiteFillR::AgentFS.open(id: 'my-agent') do |agent|
    #     agent.kv.set('key', 'value')
    #   end
    # @example Using path
    #   agent = LiteFillR::AgentFS.open(path: './data/mydb.db')
    def self.open(options = {})
      opts = options.is_a?(Options) ? options : Options.new(**options)

      # Require at least id or path
      unless opts.id || opts.path
        raise ArgumentError, "AgentFS.open() requires at least 'id' or 'path'."
      end

      # Validate agent ID if provided
      if opts.id && !opts.id.match?(/\A[a-zA-Z0-9_-]+\z/)
        raise ArgumentError, "Agent ID must contain only alphanumeric characters, hyphens, and underscores"
      end

      # Determine database path
      db_path = if opts.path
                  opts.path
                else
                  directory = ".agentfs"
                  FileUtils.mkdir_p(directory)
                  "#{directory}/#{opts.id}.db"
                end

      # Connect to the database
      db = SQLite3::Database.new(db_path)
      db.busy_timeout = 5000
      db.foreign_keys = true

      agent = open_with(db)

      if block_given?
        begin
          yield agent
        ensure
          agent.close
        end
      else
        agent
      end
    end

    # Open an AgentFS instance with an existing database connection
    # @param db [SQLite3::Database] An existing SQLite3 database connection
    # @return [AgentFS] Fully initialized AgentFS instance
    def self.open_with(db)
      kv = KvStore.from_database(db)
      fs = Filesystem.from_database(db)
      tools = ToolCalls.from_database(db)

      new(db: db, kv: kv, fs: fs, tools: tools)
    end

    # Get the underlying database connection
    # @return [SQLite3::Database]
    def database
      @db
    end

    # Close the database connection
    # @return [void]
    def close
      @db.close
    end
  end
end
