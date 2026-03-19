#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script for LiteFillR
# Run with: ruby demo.rb

require_relative "lib/lite_fill_r"

puts "=" * 60
puts "LiteFillR Demo - Pure Ruby AgentFS Implementation"
puts "=" * 60

# Clean up previous demo
FileUtils.rm_rf(".agentfs/demo.db")

# Create or open an agent filesystem
LiteFillR::AgentFS.open(id: "demo") do |agent|
  puts "\n1. Key-Value Store Demo"
  puts "-" * 40

  # Set some values
  agent.kv.set("user:123", { "name" => "Alice", "age" => 30, "active" => true })
  agent.kv.set("user:456", { "name" => "Bob", "age" => 25, "active" => false })
  agent.kv.set("config:theme", "dark")
  agent.kv.set("config:language", "en")

  # Get values
  user = agent.kv.get("user:123")
  puts "User 123: #{user.inspect}"

  theme = agent.kv.get("config:theme")
  puts "Theme: #{theme.inspect}"

  # List keys with prefix
  users = agent.kv.list("user:")
  puts "All users:"
  users.each { |item| puts "  - #{item['key']}: #{item['value']['name']}" }

  configs = agent.kv.list("config:")
  puts "All configs:"
  configs.each { |item| puts "  - #{item['key']}: #{item['value']}" }

  puts "\n2. Filesystem Demo"
  puts "-" * 40

  # Write files
  agent.fs.write_file("/hello.txt", "Hello from LiteFillR!")
  agent.fs.write_file("/data/config.json", '{"version": "1.0", "enabled": true}')
  agent.fs.write_file("/data/nested/deep/file.txt", "Deep nested content")

  # Read files
  puts "Content of /hello.txt:"
  puts "  #{agent.fs.read_file("/hello.txt")}"

  puts "Content of /data/config.json:"
  puts "  #{agent.fs.read_file("/data/config.json")}"

  puts "Content of /data/nested/deep/file.txt:"
  puts "  #{agent.fs.read_file("/data/nested/deep/file.txt")}"

  # List directories
  puts "\nRoot directory contents:"
  agent.fs.readdir("/").each { |entry| puts "  - #{entry}" }

  puts "\n/data directory contents:"
  agent.fs.readdir("/data").each { |entry| puts "  - #{entry}" }

  puts "\n/data/nested directory contents:"
  agent.fs.readdir("/data/nested").each { |entry| puts "  - #{entry}" }

  # Get file stats
  puts "\nStats for /hello.txt:"
  stats = agent.fs.stat("/hello.txt")
  puts "  - Inode: #{stats.ino}"
  puts "  - Size: #{stats.size} bytes"
  puts "  - Mode: 0o#{stats.mode.to_s(8)}"
  puts "  - Is file: #{stats.file?}"
  puts "  - Is directory: #{stats.directory?}"

  # Create and remove directories
  puts "\n3. Directory Operations Demo"
  puts "-" * 40

  agent.fs.mkdir("/new_dir")
  puts "Created /new_dir"
  puts "Root directory now contains: #{agent.fs.readdir("/").inspect}"

  agent.fs.rmdir("/new_dir")
  puts "Removed /new_dir"
  puts "Root directory now contains: #{agent.fs.readdir("/").inspect}"

  # Rename files
  puts "\n4. Rename Demo"
  puts "-" * 40

  agent.fs.rename("/hello.txt", "/greetings.txt")
  puts "Renamed /hello.txt to /greetings.txt"
  puts "Content: #{agent.fs.read_file("/greetings.txt")}"

  # Copy files
  puts "\n5. Copy Demo"
  puts "-" * 40

  agent.fs.copy_file("/greetings.txt", "/hello_copy.txt")
  puts "Copied /greetings.txt to /hello_copy.txt"
  puts "Content of copy: #{agent.fs.read_file("/hello_copy.txt")}"

  # Remove files
  puts "\n6. Remove Demo"
  puts "-" * 40

  agent.fs.unlink("/hello_copy.txt")
  puts "Removed /hello_copy.txt"
  puts "Root directory now contains: #{agent.fs.readdir("/").inspect}"

  puts "\n7. Tool Calls Demo"
  puts "-" * 40

  # Record completed tool calls
  call1 = agent.tools.record(
    "web_search",
    started_at: Time.now.to_i - 2,
    completed_at: Time.now.to_i,
    parameters: { "query" => "Ruby programming" },
    result: { "results" => ["Ruby is...", "Ruby was created..."] }
  )
  puts "Recorded tool call ##{call1}"

  call2 = agent.tools.record(
    "file_read",
    started_at: Time.now.to_i - 1,
    completed_at: Time.now.to_i,
    parameters: { "path" => "/data/config.json" },
    result: { "content" => '{"version": "1.0"}' }
  )
  puts "Recorded tool call ##{call2}"

  call3 = agent.tools.record(
    "api_call",
    started_at: Time.now.to_i - 3,
    completed_at: Time.now.to_i,
    parameters: { "endpoint" => "/users" },
    error: "Connection timeout"
  )
  puts "Recorded failed tool call ##{call3}"

  # Start, then complete a tool call
  call4 = agent.tools.start("code_execution", { "language" => "ruby", "code" => "puts 'hello'" })
  puts "Started tool call ##{call4}"
  sleep(0.1)
  agent.tools.success(call4, { "output" => "hello\n", "exit_code" => 0 })
  puts "Completed tool call ##{call4}"

  # Query tool calls
  puts "\nAll tool calls:"
  agent.tools.get_by_name("web_search").each do |call|
    puts "  - ##{call.id}: #{call.name} (#{call.status})"
  end

  puts "\nTool call statistics:"
  agent.tools.get_stats.each do |stat|
    puts "  - #{stat.name}: #{stat.total_calls} calls, #{stat.avg_duration_ms.round(2)}ms avg"
  end

  puts "\n8. Error Handling Demo"
  puts "-" * 40

  begin
    agent.fs.read_file("/nonexistent.txt")
  rescue LiteFillR::ErrnoException => e
    puts "Expected error caught:"
    puts "  Code: #{e.code}"
    puts "  Syscall: #{e.syscall}"
    puts "  Path: #{e.path}"
    puts "  Message: #{e.message}"
  end

  begin
    agent.fs.mkdir("/data/config.json/new")  # Try to create dir inside a file
  rescue LiteFillR::ErrnoException => e
    puts "\nExpected error caught:"
    puts "  Code: #{e.code}"
    puts "  Message: #{e.message}"
  end
end

puts "\n" + "=" * 60
puts "Demo completed successfully!"
puts "Database stored at: .agentfs/demo.db"
puts "=" * 60
