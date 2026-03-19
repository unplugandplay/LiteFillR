# LiteFillR

A lightweight, pure Ruby implementation of the AgentFS specification.

LiteFillR provides a filesystem, key-value store, and tool call audit trail for AI agents, backed by SQLite. It's a complete Ruby port of the [AgentFS](https://github.com/tursodatabase/agentfs) specification with minimal dependencies.

## Features

- **Virtual Filesystem**: POSIX-like filesystem interface with files, directories, and metadata
- **Key-Value Store**: Simple get/set operations with JSON serialization
- **Tool Call Tracking**: Audit trail for debugging and performance analysis
- **SQLite Backend**: Single `.db` file contains everything - portable and queryable
- **Minimal Dependencies**: Only requires the `sqlite3` gem

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lite_fill_r'
```

And then execute:

```bash
bundle install
```

Or install it yourself:

```bash
gem install lite_fill_r
```

## Usage

### Basic Setup

```ruby
require 'lite_fill_r'

# Create or open an agent filesystem
agent = LiteFillR::AgentFS.open(id: 'my-agent')
# Creates: .agentfs/my-agent.db

# Or use a custom path
agent = LiteFillR::AgentFS.open(path: './data/my-agent.db')

# Or use with a block for auto-cleanup
LiteFillR::AgentFS.open(id: 'my-agent') do |agent|
  # Use agent here
  # Automatically closes when block exits
end
```

### Key-Value Store

```ruby
# Store values (JSON serialized automatically)
agent.kv.set('user:preferences', { theme: 'dark', language: 'en' })
agent.kv.set('counter', 42)

# Retrieve values
prefs = agent.kv.get('user:preferences')
# => {"theme" => "dark", "language" => "en"}

# With default value
counter = agent.kv.get('nonexistent', 0)
# => 0

# List keys by prefix
users = agent.kv.list('user:')
# => [{"key" => "user:preferences", "value" => {...}}]

# Delete a key
agent.kv.delete('counter')
```

### Filesystem

```ruby
# Write files (parent directories created automatically)
agent.fs.write_file('/data/config.json', '{"version": "1.0"}')
agent.fs.write_file('/logs/app.log', 'Application started')

# Read files
content = agent.fs.read_file('/data/config.json')
# => '{"version": "1.0"}'

# Read as bytes
bytes = agent.fs.read_file('/data/image.png', encoding: nil)

# List directories
entries = agent.fs.readdir('/data')
# => ["config.json"]

# Create directories
agent.fs.mkdir('/new_directory')

# Remove directories (must be empty)
agent.fs.rmdir('/new_directory')

# Remove files
agent.fs.unlink('/logs/app.log')
# or: agent.fs.delete_file('/logs/app.log')

# Remove recursively
agent.fs.rm('/data', recursive: true)

# Rename/move
agent.fs.rename('/old_name.txt', '/new_name.txt')

# Copy files
agent.fs.copy_file('/source.txt', '/dest.txt')

# Get file stats
stats = agent.fs.stat('/data/config.json')
puts "Size: #{stats.size} bytes"
puts "Is file: #{stats.file?}"
puts "Is directory: #{stats.directory?}"

# Check existence
agent.fs.exist?('/data/config.json')  # => true
agent.fs.file?('/data/config.json')   # => true
agent.fs.directory?('/data')          # => true
```

### Tool Call Tracking

```ruby
# Record a completed tool call
call_id = agent.tools.record(
  'web_search',
  started_at: Time.now.to_i - 2,
  completed_at: Time.now.to_i,
  parameters: { query: 'Ruby programming' },
  result: { results: ['Ruby is...'] }
)

# Or use start/success/error pattern
call_id = agent.tools.start('file_read', { path: '/data.txt' })
begin
  content = File.read('data.txt')
  agent.tools.success(call_id, { content: content })
rescue => e
  agent.tools.error(call_id, e.message)
end

# Query tool calls
calls = agent.tools.get_by_name('web_search', limit: 10)
calls.each do |call|
  puts "#{call.name}: #{call.status} (#{call.duration_ms}ms)"
end

# Get recent calls
recent = agent.tools.get_recent(Time.now.to_i - 3600) # Last hour

# Get statistics
stats = agent.tools.get_stats
stats.each do |stat|
  puts "#{stat.name}: #{stat.total_calls} calls, #{stat.avg_duration_ms.round(2)}ms avg"
end

# Get specific call
call = agent.tools.get(call_id)
puts "Tool: #{call.name}"
puts "Status: #{call.status}"
puts "Parameters: #{call.parameters}"
puts "Result: #{call.result}" if call.success?
puts "Error: #{call.error}" if call.error?
```

### Error Handling

LiteFillR uses POSIX-style error codes:

```ruby
begin
  agent.fs.read_file('/nonexistent.txt')
rescue LiteFillR::ErrnoException => e
  puts "Error: #{e.code}"        # => "ENOENT"
  puts "Syscall: #{e.syscall}"   # => "open"
  puts "Path: #{e.path}"         # => "/nonexistent.txt"
  puts "Message: #{e.message}"   # => "ENOENT: no such file or directory, open '/nonexistent.txt'"
end
```

Available error codes:
- `ENOENT` - No such file or directory
- `EEXIST` - File already exists
- `EISDIR` - Is a directory
- `ENOTDIR` - Not a directory
- `ENOTEMPTY` - Directory not empty
- `EPERM` - Operation not permitted
- `EINVAL` - Invalid argument
- `ENOSYS` - Function not implemented

## Database Schema

LiteFillR uses the same SQLite schema as the original AgentFS specification:

**Filesystem tables:**
- `fs_config` - Configuration (chunk_size)
- `fs_inode` - File/directory metadata
- `fs_dentry` - Directory entries
- `fs_data` - File content chunks (4KB default)
- `fs_symlink` - Symbolic link targets

**Key-Value table:**
- `kv_store` - Key-value pairs with timestamps

**Tool Calls table:**
- `tool_calls` - Tool invocations with timing and results

See [AgentFS SPEC.md](https://github.com/tursodatabase/agentfs/blob/main/SPEC.md) for the full specification.

## Project Structure

```
LiteFillR/
├── lib/
│   ├── lite_fill_r.rb           # Main entry point
│   └── lite_fill_r/
│       ├── constants.rb         # File mode constants
│       ├── errors.rb            # ErrnoException class
│       ├── guards.rb            # Validation helpers
│       ├── filesystem.rb        # POSIX-like filesystem
│       ├── kv_store.rb          # Key-value store
│       ├── tool_calls.rb        # Tool call tracking
│       └── version.rb           # Version constant
├── test/                        # Comprehensive test suite (168 tests)
├── demo.rb                      # Demo script
├── Gemfile                      # Dependencies
└── lite_fill_r.gemspec          # Gem specification
```

## Testing

Run the full test suite:

```bash
cd LiteFillR
bundle exec ruby test/run_tests.rb
```

The test suite includes:
- **168 tests** covering all components
- Unit tests for constants, errors, guards
- Component tests for KvStore, ToolCalls, Filesystem
- Integration tests for full workflows
- Stress tests with large data
- Unicode support tests

See [TESTING.md](TESTING.md) for more details.

## Running the Demo

```bash
cd LiteFillR
bundle install
bundle exec ruby demo.rb
```

## Dependencies

- Ruby >= 3.0.0
- sqlite3 gem (~> 2.0)
- minitest (development)

## License

MIT

## Acknowledgments

LiteFillR is a pure Ruby implementation of the [AgentFS](https://github.com/tursodatabase/agentfs) specification by Turso.
