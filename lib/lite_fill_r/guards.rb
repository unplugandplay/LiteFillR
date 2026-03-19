# frozen_string_literal: true

require_relative "constants"
require_relative "errors"

module LiteFillR
  # Guard functions for filesystem operations validation
  module Guards
    module_function

    # @param mode [Integer]
    # @return [Boolean]
    def dir_mode?(mode)
      (mode & Constants::S_IFMT) == Constants::S_IFDIR
    end

    # @param mode [Integer]
    # @return [Boolean]
    def symlink_mode?(mode)
      (mode & Constants::S_IFMT) == Constants::S_IFLNK
    end

    # @param db [SQLite3::Database]
    # @param ino [Integer]
    # @return [Integer, nil]
    def get_inode_mode(db, ino)
      row = db.get_first_row("SELECT mode FROM fs_inode WHERE ino = ?", ino)
      row&.first
    end

    # @param db [SQLite3::Database]
    # @param ino [Integer]
    # @param syscall [String]
    # @param path [String]
    # @return [Integer]
    # @raise [ErrnoException]
    def get_inode_mode_or_throw(db, ino, syscall, path)
      mode = get_inode_mode(db, ino)
      unless mode
        raise ErrnoException.new(
          code: ErrorCodes::ENOENT,
          syscall: syscall,
          path: path,
          message: "no such file or directory"
        )
      end
      mode
    end

    # @param path [String]
    # @param syscall [String]
    # @raise [ErrnoException]
    def assert_not_root(path, syscall)
      return unless path == "/"

      raise ErrnoException.new(
        code: ErrorCodes::EPERM,
        syscall: syscall,
        path: path,
        message: "operation not permitted on root directory"
      )
    end

    # @param mode [Integer]
    # @param syscall [String]
    # @param path [String]
    # @raise [ErrnoException]
    def assert_not_symlink_mode(mode, syscall, path)
      return unless symlink_mode?(mode)

      raise ErrnoException.new(
        code: ErrorCodes::ENOSYS,
        syscall: syscall,
        path: path,
        message: "symbolic links not supported yet"
      )
    end

    # @param db [SQLite3::Database]
    # @param ino [Integer]
    # @param syscall [String]
    # @param path [String]
    # @raise [ErrnoException]
    def assert_inode_is_directory(db, ino, syscall, path)
      mode = get_inode_mode(db, ino)
      unless mode
        raise ErrnoException.new(
          code: ErrorCodes::ENOENT,
          syscall: syscall,
          path: path,
          message: "no such file or directory"
        )
      end
      unless dir_mode?(mode)
        raise ErrnoException.new(
          code: ErrorCodes::ENOTDIR,
          syscall: syscall,
          path: path,
          message: "not a directory"
        )
      end
    end

    # @param db [SQLite3::Database]
    # @param ino [Integer]
    # @param syscall [String]
    # @param path [String]
    # @raise [ErrnoException]
    def assert_writable_existing_inode(db, ino, syscall, path)
      mode = get_inode_mode(db, ino)
      unless mode
        raise ErrnoException.new(
          code: ErrorCodes::ENOENT,
          syscall: syscall,
          path: path,
          message: "no such file or directory"
        )
      end
      if dir_mode?(mode)
        raise ErrnoException.new(
          code: ErrorCodes::EISDIR,
          syscall: syscall,
          path: path,
          message: "illegal operation on a directory"
        )
      end
      assert_not_symlink_mode(mode, syscall, path)
    end

    # @param db [SQLite3::Database]
    # @param ino [Integer]
    # @param syscall [String]
    # @param path [String]
    # @raise [ErrnoException]
    def assert_readable_existing_inode(db, ino, syscall, path)
      # Same logic as writable for now
      assert_writable_existing_inode(db, ino, syscall, path)
    end

    # @param db [SQLite3::Database]
    # @param ino [Integer]
    # @param path [String]
    # @raise [ErrnoException]
    def assert_readdir_target_inode(db, ino, path)
      mode = get_inode_mode(db, ino)
      unless mode
        raise ErrnoException.new(
          code: ErrorCodes::ENOENT,
          syscall: Syscalls::SCANDIR,
          path: path,
          message: "no such file or directory"
        )
      end
      assert_not_symlink_mode(mode, Syscalls::SCANDIR, path)
      unless dir_mode?(mode)
        raise ErrnoException.new(
          code: ErrorCodes::ENOTDIR,
          syscall: Syscalls::SCANDIR,
          path: path,
          message: "not a directory"
        )
      end
    end

    # @param db [SQLite3::Database]
    # @param ino [Integer]
    # @param path [String]
    # @raise [ErrnoException]
    def assert_unlink_target_inode(db, ino, path)
      mode = get_inode_mode(db, ino)
      unless mode
        raise ErrnoException.new(
          code: ErrorCodes::ENOENT,
          syscall: Syscalls::UNLINK,
          path: path,
          message: "no such file or directory"
        )
      end
      if dir_mode?(mode)
        raise ErrnoException.new(
          code: ErrorCodes::EISDIR,
          syscall: Syscalls::UNLINK,
          path: path,
          message: "illegal operation on a directory"
        )
      end
      assert_not_symlink_mode(mode, Syscalls::UNLINK, path)
    end

    # @param options [Hash, nil]
    # @return [Hash]
    def normalize_rm_options(options = {})
      options ||= {}
      {
        force: options[:force] || false,
        recursive: options[:recursive] || false
      }
    end

    # @param path [String]
    # @param syscall [String]
    # @param force [Boolean]
    # @raise [ErrnoException]
    def throw_enoent_unless_force(path, syscall, force)
      return if force

      raise ErrnoException.new(
        code: ErrorCodes::ENOENT,
        syscall: syscall,
        path: path,
        message: "no such file or directory"
      )
    end
  end
end
