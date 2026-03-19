# frozen_string_literal: true

require_relative "test_helper"

class TestGuards < LiteFillRTest
  def test_dir_mode_with_directory
    assert LiteFillR::Guards.dir_mode?(0o040755)
    assert LiteFillR::Guards.dir_mode?(LiteFillR::Constants::DEFAULT_DIR_MODE)
  end

  def test_dir_mode_with_file
    refute LiteFillR::Guards.dir_mode?(0o100644)
    refute LiteFillR::Guards.dir_mode?(LiteFillR::Constants::DEFAULT_FILE_MODE)
  end

  def test_symlink_mode_with_symlink
    assert LiteFillR::Guards.symlink_mode?(0o120777)
    assert LiteFillR::Guards.symlink_mode?(LiteFillR::Constants::S_IFLNK | 0o644)
  end

  def test_symlink_mode_with_non_symlink
    refute LiteFillR::Guards.symlink_mode?(0o100644)
    refute LiteFillR::Guards.symlink_mode?(0o040755)
  end

  def test_assert_not_root_with_non_root
    LiteFillR::Guards.assert_not_root("/test", LiteFillR::Syscalls::RMDIR)
    LiteFillR::Guards.assert_not_root("/path/to/file", LiteFillR::Syscalls::UNLINK)
  end

  def test_assert_not_root_raises_for_root
    err = assert_raises(LiteFillR::ErrnoException) do
      LiteFillR::Guards.assert_not_root("/", LiteFillR::Syscalls::RMDIR)
    end
    assert_equal "EPERM", err.code
  end

  def test_assert_not_symlink_mode_with_non_symlink
    LiteFillR::Guards.assert_not_symlink_mode(0o100644, LiteFillR::Syscalls::OPEN, "/test")
  end

  def test_assert_not_symlink_mode_raises_for_symlink
    err = assert_raises(LiteFillR::ErrnoException) do
      LiteFillR::Guards.assert_not_symlink_mode(0o120777, LiteFillR::Syscalls::OPEN, "/test")
    end
    assert_equal "ENOSYS", err.code
  end

  def test_normalize_rm_options_defaults
    opts = LiteFillR::Guards.normalize_rm_options({})
    refute opts[:force]
    refute opts[:recursive]
  end

  def test_normalize_rm_options_with_nil
    opts = LiteFillR::Guards.normalize_rm_options(nil)
    refute opts[:force]
    refute opts[:recursive]
  end

  def test_normalize_rm_options_preserves_values
    opts = LiteFillR::Guards.normalize_rm_options(force: true, recursive: true)
    assert opts[:force]
    assert opts[:recursive]
  end

  def test_normalize_rm_options_mixed_values
    opts = LiteFillR::Guards.normalize_rm_options(force: true, recursive: false)
    assert opts[:force]
    refute opts[:recursive]
  end

  def test_throw_enoent_unless_force_with_true
    LiteFillR::Guards.throw_enoent_unless_force("/test", LiteFillR::Syscalls::RM, true)
  end

  def test_throw_enoent_unless_force_with_false
    err = assert_raises(LiteFillR::ErrnoException) do
      LiteFillR::Guards.throw_enoent_unless_force("/test", LiteFillR::Syscalls::RM, false)
    end
    assert_equal "ENOENT", err.code
  end
end

class TestGuardsDatabase < LiteFillRTest
  def setup
    super
    @db = SQLite3::Database.new(test_db_path)
    @db.execute_batch(<<~SQL)
      CREATE TABLE fs_inode (
        ino INTEGER PRIMARY KEY,
        mode INTEGER NOT NULL,
        nlink INTEGER NOT NULL DEFAULT 0,
        uid INTEGER NOT NULL DEFAULT 0,
        gid INTEGER NOT NULL DEFAULT 0,
        size INTEGER NOT NULL DEFAULT 0,
        atime INTEGER NOT NULL,
        mtime INTEGER NOT NULL,
        ctime INTEGER NOT NULL
      );
      INSERT INTO fs_inode (ino, mode, nlink, atime, mtime, ctime)
      VALUES (1, 16877, 1, 0, 0, 0),   -- 0o040755 directory
             (2, 33188, 1, 0, 0, 0),   -- 0o100644 file
             (3, 41471, 1, 0, 0, 0);   -- 0o120777 symlink
    SQL
  end

  def teardown
    @db&.close
    super
  end

  def test_get_inode_mode_existing
    assert_equal 16877, LiteFillR::Guards.get_inode_mode(@db, 1)   # 0o040755
    assert_equal 33188, LiteFillR::Guards.get_inode_mode(@db, 2)   # 0o100644
  end

  def test_get_inode_mode_non_existing
    assert_nil LiteFillR::Guards.get_inode_mode(@db, 999)
  end

  def test_get_inode_mode_or_throw_existing
    mode = LiteFillR::Guards.get_inode_mode_or_throw(@db, 1, LiteFillR::Syscalls::STAT, "/test")
    assert_equal 16877, mode  # 0o040755
  end

  def test_get_inode_mode_or_throw_non_existing
    err = assert_raises(LiteFillR::ErrnoException) do
      LiteFillR::Guards.get_inode_mode_or_throw(@db, 999, LiteFillR::Syscalls::STAT, "/test")
    end
    assert_equal "ENOENT", err.code
  end

  def test_assert_inode_is_directory_with_dir
    LiteFillR::Guards.assert_inode_is_directory(@db, 1, LiteFillR::Syscalls::SCANDIR, "/test")
  end

  def test_assert_inode_is_directory_with_file
    err = assert_raises(LiteFillR::ErrnoException) do
      LiteFillR::Guards.assert_inode_is_directory(@db, 2, LiteFillR::Syscalls::SCANDIR, "/test")
    end
    assert_equal "ENOTDIR", err.code
  end

  def test_assert_inode_is_directory_non_existing
    err = assert_raises(LiteFillR::ErrnoException) do
      LiteFillR::Guards.assert_inode_is_directory(@db, 999, LiteFillR::Syscalls::SCANDIR, "/test")
    end
    assert_equal "ENOENT", err.code
  end

  def test_assert_writable_existing_inode_with_file
    LiteFillR::Guards.assert_writable_existing_inode(@db, 2, LiteFillR::Syscalls::OPEN, "/test")
  end

  def test_assert_writable_existing_inode_with_dir
    err = assert_raises(LiteFillR::ErrnoException) do
      LiteFillR::Guards.assert_writable_existing_inode(@db, 1, LiteFillR::Syscalls::OPEN, "/test")
    end
    assert_equal "EISDIR", err.code
  end

  def test_assert_writable_existing_inode_non_existing
    err = assert_raises(LiteFillR::ErrnoException) do
      LiteFillR::Guards.assert_writable_existing_inode(@db, 999, LiteFillR::Syscalls::OPEN, "/test")
    end
    assert_equal "ENOENT", err.code
  end

  def test_assert_unlink_target_inode_with_file
    LiteFillR::Guards.assert_unlink_target_inode(@db, 2, "/test")
  end

  def test_assert_unlink_target_inode_with_dir
    err = assert_raises(LiteFillR::ErrnoException) do
      LiteFillR::Guards.assert_unlink_target_inode(@db, 1, "/test")
    end
    assert_equal "EISDIR", err.code
  end

  def test_assert_unlink_target_inode_with_symlink
    err = assert_raises(LiteFillR::ErrnoException) do
      LiteFillR::Guards.assert_unlink_target_inode(@db, 3, "/test")
    end
    assert_equal "ENOSYS", err.code
  end
end
