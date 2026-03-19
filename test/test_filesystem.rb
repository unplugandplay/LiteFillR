# frozen_string_literal: true

require_relative "test_helper"

class TestStats < LiteFillRTest
  def test_stores_all_attributes
    stats = LiteFillR::Stats.new(
      ino: 42, mode: 0o100644, nlink: 1, uid: 1000, gid: 1000,
      size: 1234, atime: 1234567890, mtime: 1234567880, ctime: 1234567870
    )

    assert_equal 42, stats.ino
    assert_equal 0o100644, stats.mode
    assert_equal 1, stats.nlink
    assert_equal 1234, stats.size
  end

  def test_file_predicate
    file_stats = LiteFillR::Stats.new(
      ino: 1, mode: 0o100644, nlink: 1, uid: 0, gid: 0, size: 0,
      atime: 0, mtime: 0, ctime: 0
    )
    assert file_stats.file?
    refute file_stats.directory?
  end

  def test_directory_predicate
    dir_stats = LiteFillR::Stats.new(
      ino: 1, mode: 0o040755, nlink: 1, uid: 0, gid: 0, size: 0,
      atime: 0, mtime: 0, ctime: 0
    )
    assert dir_stats.directory?
    refute dir_stats.file?
  end
end

class TestFilesystem < LiteFillRTest
  def setup
    super
    @db = SQLite3::Database.new(test_db_path)
    @db.busy_timeout = 5000
    @fs = LiteFillR::Filesystem.from_database(@db)
  end

  def teardown
    @db&.close
    super
  end

  def test_from_database_creates_schema
    tables = @db.execute(<<~SQL).flatten
      SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'fs_%'
    SQL

    assert_includes tables, "fs_config"
    assert_includes tables, "fs_inode"
    assert_includes tables, "fs_dentry"
    assert_includes tables, "fs_data"
    assert_includes tables, "fs_symlink"
  end

  def test_chunk_size_config
    row = @db.get_first_row("SELECT value FROM fs_config WHERE key = 'chunk_size'")
    assert_equal "4096", row[0]
    assert_equal 4096, @fs.chunk_size
  end

  def test_root_directory_exists
    row = @db.get_first_row("SELECT mode FROM fs_inode WHERE ino = 1")
    assert_equal 16877, row[0]  # 0o040755
  end

  def test_write_and_read_file
    @fs.write_file("/test.txt", "Hello, World!")
    assert_equal "Hello, World!", @fs.read_file("/test.txt")
  end

  def test_creates_parent_directories
    @fs.write_file("/a/b/c/d/file.txt", "nested")
    assert_equal "nested", @fs.read_file("/a/b/c/d/file.txt")
  end

  def test_update_existing_file
    @fs.write_file("/test.txt", "first")
    @fs.write_file("/test.txt", "second")
    assert_equal "second", @fs.read_file("/test.txt")
  end

  def test_empty_file
    @fs.write_file("/empty.txt", "")
    assert_equal "", @fs.read_file("/empty.txt")
  end

  def test_binary_content
    binary = "\x00\x01\x02\xFF\xFE".b
    @fs.write_file("/binary.bin", binary, encoding: nil)
    result = @fs.read_file("/binary.bin", encoding: nil)
    assert_equal binary, result
  end

  def test_large_file
    large_content = "x" * (4096 * 3 + 100)
    @fs.write_file("/large.txt", large_content)
    result = @fs.read_file("/large.txt")
    assert_equal large_content.length, result.length
    assert_equal large_content, result
  end

  def test_unicode_content
    content = "Hello 世界 🌍"
    @fs.write_file("/unicode.txt", content)
    assert_equal content, @fs.read_file("/unicode.txt")
  end

  def test_read_non_existing_raises_enoent
    err = assert_raises(LiteFillR::ErrnoException) { @fs.read_file("/nonexistent.txt") }
    assert_equal "ENOENT", err.code
  end

  def test_mkdir
    @fs.mkdir("/newdir")
    stats = @fs.stat("/newdir")
    assert stats.directory?
  end

  def test_mkdir_raises_eexist_if_exists
    @fs.mkdir("/dir")
    err = assert_raises(LiteFillR::ErrnoException) { @fs.mkdir("/dir") }
    assert_equal "EEXIST", err.code
  end

  def test_readdir
    @fs.write_file("/a.txt", "a")
    @fs.write_file("/b.txt", "b")
    @fs.mkdir("/subdir")

    entries = @fs.readdir("/")
    assert_includes entries, "a.txt"
    assert_includes entries, "b.txt"
    assert_includes entries, "subdir"
  end

  def test_readdir_returns_sorted
    @fs.write_file("/c.txt", "c")
    @fs.write_file("/a.txt", "a")
    @fs.write_file("/b.txt", "b")

    entries = @fs.readdir("/")
    assert_equal entries.sort, entries
  end

  def test_readdir_empty_directory
    @fs.mkdir("/empty")
    assert_empty @fs.readdir("/empty")
  end

  def test_stat_file
    @fs.write_file("/file.txt", "Hello, World!")
    stats = @fs.stat("/file.txt")

    assert stats.file?
    assert_equal 13, stats.size
    assert stats.ino > 0
  end

  def test_stat_directory
    stats = @fs.stat("/")
    assert stats.directory?
    assert_equal 1, stats.ino
  end

  def test_stat_non_existing_raises_enoent
    err = assert_raises(LiteFillR::ErrnoException) { @fs.stat("/nonexistent") }
    assert_equal "ENOENT", err.code
  end

  def test_unlink
    @fs.write_file("/file.txt", "content")
    @fs.unlink("/file.txt")
    refute @fs.exist?("/file.txt")
  end

  def test_unlink_non_existing_raises_enoent
    err = assert_raises(LiteFillR::ErrnoException) { @fs.unlink("/nonexistent.txt") }
    assert_equal "ENOENT", err.code
  end

  def test_unlink_directory_raises_eisdir
    @fs.mkdir("/dir")
    err = assert_raises(LiteFillR::ErrnoException) { @fs.unlink("/dir") }
    assert_equal "EISDIR", err.code
  end

  def test_unlink_root_raises_eperm
    err = assert_raises(LiteFillR::ErrnoException) { @fs.unlink("/") }
    assert_equal "EPERM", err.code
  end

  def test_rmdir_empty
    @fs.mkdir("/empty")
    @fs.rmdir("/empty")
    refute @fs.exist?("/empty")
  end

  def test_rmdir_non_empty_raises_enotempty
    @fs.mkdir("/dir")
    @fs.write_file("/dir/file.txt", "x")
    err = assert_raises(LiteFillR::ErrnoException) { @fs.rmdir("/dir") }
    assert_equal "ENOTEMPTY", err.code
  end

  def test_rm_file
    @fs.write_file("/file.txt", "x")
    @fs.rm("/file.txt")
    refute @fs.exist?("/file.txt")
  end

  def test_rm_directory_recursive
    @fs.mkdir("/dir")
    @fs.write_file("/dir/a.txt", "a")
    @fs.write_file("/dir/b.txt", "b")
    @fs.rm("/dir", recursive: true)
    refute @fs.exist?("/dir")
  end

  def test_rm_directory_without_recursive_raises_eisdir
    @fs.mkdir("/dir")
    err = assert_raises(LiteFillR::ErrnoException) { @fs.rm("/dir") }
    assert_equal "EISDIR", err.code
  end

  def test_rm_non_existing_with_force
    @fs.rm("/nonexistent", force: true) # should not raise
  end

  def test_rename_file
    @fs.write_file("/old.txt", "content")
    @fs.rename("/old.txt", "/new.txt")
    refute @fs.exist?("/old.txt")
    assert @fs.exist?("/new.txt")
    assert_equal "content", @fs.read_file("/new.txt")
  end

  def test_rename_same_path_noop
    @fs.write_file("/file.txt", "content")
    @fs.rename("/file.txt", "/file.txt")
    assert_equal "content", @fs.read_file("/file.txt")
  end

  def test_rename_root_raises_eperm
    err = assert_raises(LiteFillR::ErrnoException) { @fs.rename("/", "/dest") }
    assert_equal "EPERM", err.code
  end

  def test_copy_file
    @fs.write_file("/source.txt", "original")
    @fs.copy_file("/source.txt", "/dest.txt")
    assert_equal "original", @fs.read_file("/dest.txt")
  end

  def test_copy_file_overwrites_existing
    @fs.write_file("/source.txt", "new")
    @fs.write_file("/existing.txt", "old")
    @fs.copy_file("/source.txt", "/existing.txt")
    assert_equal "new", @fs.read_file("/existing.txt")
  end

  def test_copy_file_same_source_dest_raises_einval
    err = assert_raises(LiteFillR::ErrnoException) do
      @fs.copy_file("/same.txt", "/same.txt")
    end
    assert_equal "EINVAL", err.code
  end

  def test_exist_predicate
    @fs.write_file("/file.txt", "x")
    assert @fs.exist?("/file.txt")
    refute @fs.exist?("/nonexistent")
  end

  def test_file_predicate
    @fs.write_file("/file.txt", "x")
    @fs.mkdir("/dir")
    assert @fs.file?("/file.txt")
    refute @fs.file?("/dir")
    refute @fs.file?("/nonexistent")
  end

  def test_directory_predicate
    @fs.write_file("/file.txt", "x")
    @fs.mkdir("/dir")
    assert @fs.directory?("/dir")
    refute @fs.directory?("/file.txt")
    refute @fs.directory?("/nonexistent")
  end

  def test_large_file_stress
    large_content = "x" * (1024 * 1024)  # 1MB
    @fs.write_file("/huge.txt", large_content)
    result = @fs.read_file("/huge.txt")
    assert_equal large_content.length, result.length
  end

  def test_many_files
    100.times do |i|
      @fs.write_file("/file#{i}.txt", "content#{i}")
    end
    100.times do |i|
      assert_equal "content#{i}", @fs.read_file("/file#{i}.txt")
    end
  end

  def test_deep_nesting
    depth = 20
    path = "/" + (1..depth).map { |i| "dir#{i}" }.join("/")
    @fs.write_file("#{path}/file.txt", "deep")
    assert_equal "deep", @fs.read_file("#{path}/file.txt")
  end
end
