# frozen_string_literal: true

require "sqlite3"
require_relative "constants"
require_relative "errors"
require_relative "guards"

module LiteFillR
  # File/directory statistics
  class Stats
    attr_reader :ino, :mode, :nlink, :uid, :gid, :size, :atime, :mtime, :ctime

    # @param ino [Integer] Inode number
    # @param mode [Integer] File mode and permissions
    # @param nlink [Integer] Number of hard links
    # @param uid [Integer] User ID
    # @param gid [Integer] Group ID
    # @param size [Integer] File size in bytes
    # @param atime [Integer] Access time (Unix timestamp)
    # @param mtime [Integer] Modification time (Unix timestamp)
    # @param ctime [Integer] Change time (Unix timestamp)
    def initialize(ino:, mode:, nlink:, uid:, gid:, size:, atime:, mtime:, ctime:)
      @ino = ino
      @mode = mode
      @nlink = nlink
      @uid = uid
      @gid = gid
      @size = size
      @atime = atime
      @mtime = mtime
      @ctime = ctime
    end

    # @return [Boolean]
    def file?
      (@mode & Constants::S_IFMT) == Constants::S_IFREG
    end

    # @return [Boolean]
    def directory?
      (@mode & Constants::S_IFMT) == Constants::S_IFDIR
    end

    # @return [Boolean]
    def symbolic_link?
      (@mode & Constants::S_IFMT) == Constants::S_IFLNK
    end
  end

  # Virtual filesystem backed by SQLite
  # Provides a POSIX-like filesystem interface with support for
  # files, directories, and symbolic links.
  class Filesystem
    attr_reader :chunk_size

    # @param db [SQLite3::Database]
    def initialize(db)
      @db = db
      @root_ino = 1
      initialize_schema
    end

    # Create a Filesystem from an existing database connection
    # @param db [SQLite3::Database]
    # @return [Filesystem]
    def self.from_database(db)
      new(db)
    end

    # Initialize the database schema
    def initialize_schema
      @db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS fs_config (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS fs_inode (
          ino INTEGER PRIMARY KEY AUTOINCREMENT,
          mode INTEGER NOT NULL,
          nlink INTEGER NOT NULL DEFAULT 0,
          uid INTEGER NOT NULL DEFAULT 0,
          gid INTEGER NOT NULL DEFAULT 0,
          size INTEGER NOT NULL DEFAULT 0,
          atime INTEGER NOT NULL,
          mtime INTEGER NOT NULL,
          ctime INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS fs_dentry (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          parent_ino INTEGER NOT NULL,
          ino INTEGER NOT NULL,
          UNIQUE(parent_ino, name)
        );

        CREATE INDEX IF NOT EXISTS idx_fs_dentry_parent
        ON fs_dentry(parent_ino, name);

        CREATE TABLE IF NOT EXISTS fs_data (
          ino INTEGER NOT NULL,
          chunk_index INTEGER NOT NULL,
          data BLOB NOT NULL,
          PRIMARY KEY (ino, chunk_index)
        );

        CREATE TABLE IF NOT EXISTS fs_symlink (
          ino INTEGER PRIMARY KEY,
          target TEXT NOT NULL
        );
      SQL

      @chunk_size = ensure_root
    end

    # Write content to a file
    # @param path [String] Path to the file
    # @param content [String, bytes] Content to write
    # @param encoding [String] Text encoding (default: 'utf-8')
    # @return [void]
    # @example
    #   fs.write_file('/data/config.json', '{"key": "value"}')
    def write_file(path, content, encoding: "utf-8")
      ensure_parent_dirs(path)

      normalized = normalize_path(path)
      ino = resolve_path(normalized)

      if ino
        Guards.assert_writable_existing_inode(@db, ino, Syscalls::OPEN, normalized)
        update_file_content(ino, content, encoding)
      else
        parent = resolve_parent(normalized)
        raise ErrnoException.new(
          code: ErrorCodes::ENOENT,
          syscall: Syscalls::OPEN,
          path: normalized,
          message: "no such file or directory"
        ) unless parent

        parent_ino, name = parent
        Guards.assert_inode_is_directory(@db, parent_ino, Syscalls::OPEN, normalized)

        file_ino = create_inode(Constants::DEFAULT_FILE_MODE)
        create_dentry(parent_ino, name, file_ino)
        update_file_content(file_ino, content, encoding)
      end
    end

    # Read content from a file
    # @param path [String] Path to the file
    # @param encoding [String, nil] Text encoding (default: 'utf-8'). Set to nil to return bytes.
    # @return [String, bytes] File content
    # @example
    #   content = fs.read_file('/data/config.json')
    #   data = fs.read_file('/data/image.png', encoding: nil)
    def read_file(path, encoding: "utf-8")
      normalized, ino = resolve_path_or_throw(path, Syscalls::OPEN)
      Guards.assert_readable_existing_inode(@db, ino, Syscalls::OPEN, normalized)

      rows = @db.execute(<<~SQL, [ino])
        SELECT data FROM fs_data
        WHERE ino = ?
        ORDER BY chunk_index ASC
      SQL

      combined = rows.empty? ? +"" : rows.map(&:first).join

      # Update atime
      now = Time.now.to_i
      @db.execute("UPDATE fs_inode SET atime = ? WHERE ino = ?", [now, ino])

      encoding ? combined.force_encoding(encoding) : combined.force_encoding("ASCII-8BIT")
    end

    # List directory contents
    # @param path [String] Path to the directory
    # @return [Array<String>] List of entry names
    # @example
    #   entries = fs.readdir('/data')
    #   entries.each { |entry| puts entry }
    def readdir(path)
      normalized, ino = resolve_path_or_throw(path, Syscalls::SCANDIR)
      Guards.assert_readdir_target_inode(@db, ino, normalized)

      rows = @db.execute(<<~SQL, [ino])
        SELECT name FROM fs_dentry
        WHERE parent_ino = ?
        ORDER BY name ASC
      SQL

      rows.map(&:first)
    end

    # Delete a file (unlink)
    # @param path [String] Path to the file
    # @return [void]
    # @example
    #   fs.unlink('/data/temp.txt')
    def unlink(path)
      normalized = normalize_path(path)
      Guards.assert_not_root(normalized, Syscalls::UNLINK)
      normalized, ino = resolve_path_or_throw(normalized, Syscalls::UNLINK)
      Guards.assert_unlink_target_inode(@db, ino, normalized)

      parent = resolve_parent(normalized)
      return unless parent # Should not happen due to assert_not_root

      parent_ino, name = parent
      remove_dentry_and_maybe_inode(parent_ino, name, ino)
    end

    # Delete a file (deprecated alias for unlink)
    alias delete_file unlink

    # Get file/directory statistics
    # @param path [String] Path to the file or directory
    # @return [Stats]
    # @example
    #   stats = fs.stat('/data/config.json')
    #   puts "Size: #{stats.size} bytes"
    #   puts "Is file: #{stats.file?}"
    def stat(path)
      normalized, ino = resolve_path_or_throw(path, Syscalls::STAT)

      row = @db.get_first_row(<<~SQL, [ino])
        SELECT ino, mode, nlink, uid, gid, size, atime, mtime, ctime
        FROM fs_inode
        WHERE ino = ?
      SQL

      raise ErrnoException.new(
        code: ErrorCodes::ENOENT,
        syscall: Syscalls::STAT,
        path: normalized,
        message: "no such file or directory"
      ) unless row

      Stats.new(
        ino: row[0],
        mode: row[1],
        nlink: row[2],
        uid: row[3],
        gid: row[4],
        size: row[5],
        atime: row[6],
        mtime: row[7],
        ctime: row[8]
      )
    end

    # Create a directory (non-recursive)
    # @param path [String] Path to the directory to create
    # @return [void]
    # @example
    #   fs.mkdir('/data/new_dir')
    def mkdir(path)
      normalized = normalize_path(path)

      existing = resolve_path(normalized)
      if existing
        raise ErrnoException.new(
          code: ErrorCodes::EEXIST,
          syscall: Syscalls::MKDIR,
          path: normalized,
          message: "file already exists"
        )
      end

      parent = resolve_parent(normalized)
      unless parent
        raise ErrnoException.new(
          code: ErrorCodes::ENOENT,
          syscall: Syscalls::MKDIR,
          path: normalized,
          message: "no such file or directory"
        )
      end

      parent_ino, name = parent
      Guards.assert_inode_is_directory(@db, parent_ino, Syscalls::MKDIR, normalized)

      dir_ino = create_inode(Constants::DEFAULT_DIR_MODE)
      begin
        create_dentry(parent_ino, name, dir_ino)
      rescue SQLite3::ConstraintException
        raise ErrnoException.new(
          code: ErrorCodes::EEXIST,
          syscall: Syscalls::MKDIR,
          path: normalized,
          message: "file already exists"
        )
      end
    end

    # Remove an empty directory
    # @param path [String] Path to the directory to remove
    # @return [void]
    # @example
    #   fs.rmdir('/data/empty_dir')
    def rmdir(path)
      normalized = normalize_path(path)
      Guards.assert_not_root(normalized, Syscalls::RMDIR)
      normalized, ino = resolve_path_or_throw(normalized, Syscalls::RMDIR)

      mode = Guards.get_inode_mode_or_throw(@db, ino, Syscalls::RMDIR, normalized)
      Guards.assert_not_symlink_mode(mode, Syscalls::RMDIR, normalized)

      unless Guards.dir_mode?(mode)
        raise ErrnoException.new(
          code: ErrorCodes::ENOTDIR,
          syscall: Syscalls::RMDIR,
          path: normalized,
          message: "not a directory"
        )
      end

      child = @db.get_first_row(<<~SQL, [ino])
        SELECT 1 as one FROM fs_dentry
        WHERE parent_ino = ?
        LIMIT 1
      SQL

      if child
        raise ErrnoException.new(
          code: ErrorCodes::ENOTEMPTY,
          syscall: Syscalls::RMDIR,
          path: normalized,
          message: "directory not empty"
        )
      end

      parent = resolve_parent(normalized)
      return unless parent

      parent_ino, name = parent
      remove_dentry_and_maybe_inode(parent_ino, name, ino)
    end

    # Remove a file or directory
    # @param path [String] Path to remove
    # @param force [Boolean] If true, ignore nonexistent files
    # @param recursive [Boolean] If true, remove directories and their contents recursively
    # @return [void]
    # @example
    #   fs.rm('/data/file.txt')
    #   fs.rm('/data/dir', recursive: true)
    def rm(path, force: false, recursive: false)
      normalized = normalize_path(path)
      opts = Guards.normalize_rm_options(force: force, recursive: recursive)
      force = opts[:force]
      recursive = opts[:recursive]
      Guards.assert_not_root(normalized, Syscalls::RM)

      ino = resolve_path(normalized)
      unless ino
        Guards.throw_enoent_unless_force(normalized, Syscalls::RM, force)
        return
      end

      mode = Guards.get_inode_mode_or_throw(@db, ino, Syscalls::RM, normalized)
      Guards.assert_not_symlink_mode(mode, Syscalls::RM, normalized)

      parent = resolve_parent(normalized)
      return unless parent

      parent_ino, name = parent

      if Guards.dir_mode?(mode)
        unless recursive
          raise ErrnoException.new(
            code: ErrorCodes::EISDIR,
            syscall: Syscalls::RM,
            path: normalized,
            message: "illegal operation on a directory"
          )
        end

        rm_dir_contents_recursive(ino)
        remove_dentry_and_maybe_inode(parent_ino, name, ino)
        return
      end

      remove_dentry_and_maybe_inode(parent_ino, name, ino)
    end

    # Rename (move) a file or directory
    # @param old_path [String] Current path
    # @param new_path [String] New path
    # @return [void]
    # @example
    #   fs.rename('/data/old.txt', '/data/new.txt')
    def rename(old_path, new_path)
      old_normalized = normalize_path(old_path)
      new_normalized = normalize_path(new_path)

      return if old_normalized == new_normalized

      Guards.assert_not_root(old_normalized, Syscalls::RENAME)
      Guards.assert_not_root(new_normalized, Syscalls::RENAME)

      old_parent = resolve_parent(old_normalized)
      raise ErrnoException.new(
        code: ErrorCodes::EPERM,
        syscall: Syscalls::RENAME,
        path: old_normalized,
        message: "operation not permitted"
      ) unless old_parent

      new_parent = resolve_parent(new_normalized)
      raise ErrnoException.new(
        code: ErrorCodes::ENOENT,
        syscall: Syscalls::RENAME,
        path: new_normalized,
        message: "no such file or directory"
      ) unless new_parent

      new_parent_ino, new_name = new_parent
      Guards.assert_inode_is_directory(@db, new_parent_ino, Syscalls::RENAME, new_normalized)

      old_normalized, old_ino = resolve_path_or_throw(old_normalized, Syscalls::RENAME)
      old_mode = Guards.get_inode_mode_or_throw(@db, old_ino, Syscalls::RENAME, old_normalized)
      Guards.assert_not_symlink_mode(old_mode, Syscalls::RENAME, old_normalized)
      old_is_dir = Guards.dir_mode?(old_mode)

      # Prevent renaming a directory into its own subtree
      if old_is_dir && new_normalized.start_with?("#{old_normalized}/")
        raise ErrnoException.new(
          code: ErrorCodes::EINVAL,
          syscall: Syscalls::RENAME,
          path: new_normalized,
          message: "invalid argument"
        )
      end

      new_ino = resolve_path(new_normalized)
      if new_ino
        new_mode = Guards.get_inode_mode_or_throw(@db, new_ino, Syscalls::RENAME, new_normalized)
        Guards.assert_not_symlink_mode(new_mode, Syscalls::RENAME, new_normalized)
        new_is_dir = Guards.dir_mode?(new_mode)

        if new_is_dir && !old_is_dir
          raise ErrnoException.new(
            code: ErrorCodes::EISDIR,
            syscall: Syscalls::RENAME,
            path: new_normalized,
            message: "illegal operation on a directory"
          )
        end
        if !new_is_dir && old_is_dir
          raise ErrnoException.new(
            code: ErrorCodes::ENOTDIR,
            syscall: Syscalls::RENAME,
            path: new_normalized,
            message: "not a directory"
          )
        end

        if new_is_dir
          child = @db.get_first_row(<<~SQL, [new_ino])
            SELECT 1 as one FROM fs_dentry
            WHERE parent_ino = ?
            LIMIT 1
          SQL
          if child
            raise ErrnoException.new(
              code: ErrorCodes::ENOTEMPTY,
              syscall: Syscalls::RENAME,
              path: new_normalized,
              message: "directory not empty"
            )
          end
        end

        remove_dentry_and_maybe_inode(new_parent_ino, new_name, new_ino)
      end

      old_parent_ino, old_name = old_parent
      @db.execute(<<~SQL, [new_parent_ino, new_name, old_parent_ino, old_name])
        UPDATE fs_dentry
        SET parent_ino = ?, name = ?
        WHERE parent_ino = ? AND name = ?
      SQL

      now = Time.now.to_i
      @db.execute("UPDATE fs_inode SET ctime = ? WHERE ino = ?", [now, old_ino])
      @db.execute("UPDATE fs_inode SET mtime = ?, ctime = ? WHERE ino = ?", [now, now, old_parent_ino])
      if new_parent_ino != old_parent_ino
        @db.execute("UPDATE fs_inode SET mtime = ?, ctime = ? WHERE ino = ?", [now, now, new_parent_ino])
      end
    end

    # Copy a file. Overwrites destination if it exists.
    # @param src [String] Source file path
    # @param dest [String] Destination file path
    # @return [void]
    # @example
    #   fs.copy_file('/data/src.txt', '/data/dest.txt')
    def copy_file(src, dest)
      src_normalized = normalize_path(src)
      dest_normalized = normalize_path(dest)

      if src_normalized == dest_normalized
        raise ErrnoException.new(
          code: ErrorCodes::EINVAL,
          syscall: Syscalls::COPYFILE,
          path: dest_normalized,
          message: "invalid argument"
        )
      end

      src_normalized, src_ino = resolve_path_or_throw(src_normalized, Syscalls::COPYFILE)
      Guards.assert_readable_existing_inode(@db, src_ino, Syscalls::COPYFILE, src_normalized)

      row = @db.get_first_row(<<~SQL, [src_ino])
        SELECT mode, uid, gid, size FROM fs_inode WHERE ino = ?
      SQL
      raise ErrnoException.new(
        code: ErrorCodes::ENOENT,
        syscall: Syscalls::COPYFILE,
        path: src_normalized,
        message: "no such file or directory"
      ) unless row

      content = read_file(src_normalized, encoding: nil)
      write_file(dest_normalized, content, encoding: nil)
    end

    # Check if a path exists
    # @param path [String]
    # @return [Boolean]
    def exist?(path)
      !resolve_path(normalize_path(path)).nil?
    end
    alias exists? exist?

    # Check if path is a directory
    # @param path [String]
    # @return [Boolean]
    def directory?(path)
      ino = resolve_path(normalize_path(path))
      return false unless ino

      mode = Guards.get_inode_mode(@db, ino)
      Guards.dir_mode?(mode)
    end

    # Check if path is a file
    # @param path [String]
    # @return [Boolean]
    def file?(path)
      ino = resolve_path(normalize_path(path))
      return false unless ino

      mode = Guards.get_inode_mode(@db, ino)
      (mode & Constants::S_IFMT) == Constants::S_IFREG
    end

    private

    # Ensure config and root directory exist, returns the chunk_size
    # @return [Integer]
    def ensure_root
      row = @db.get_first_row("SELECT value FROM fs_config WHERE key = 'chunk_size'")

      chunk_size = if row
                     row[0].to_i
                   else
                     @db.execute("INSERT INTO fs_config (key, value) VALUES ('chunk_size', ?)", [Constants::DEFAULT_CHUNK_SIZE.to_s])
                     Constants::DEFAULT_CHUNK_SIZE
                   end

      root = @db.get_first_row("SELECT ino FROM fs_inode WHERE ino = ?", [@root_ino])
      unless root
        now = Time.now.to_i
        @db.execute(<<~SQL, [@root_ino, Constants::DEFAULT_DIR_MODE, now, now, now])
          INSERT INTO fs_inode (ino, mode, nlink, uid, gid, size, atime, mtime, ctime)
          VALUES (?, ?, 1, 0, 0, 0, ?, ?, ?)
        SQL
      end

      chunk_size
    end

    # Normalize a path
    # @param path [String]
    # @return [String]
    def normalize_path(path)
      normalized = path.chomp("/")
      normalized = "/" if normalized.empty?
      normalized.start_with?("/") ? normalized : "/#{normalized}"
    end

    # Split path into components
    # @param path [String]
    # @return [Array<String>]
    def split_path(path)
      normalized = normalize_path(path)
      return [] if normalized == "/"

      normalized.split("/").reject(&:empty?)
    end

    # Resolve a path to an inode number
    # @param path [String]
    # @return [Integer, nil]
    def resolve_path(path)
      normalized = normalize_path(path)
      return @root_ino if normalized == "/"

      parts = split_path(normalized)
      current_ino = @root_ino

      parts.each do |name|
        row = @db.get_first_row(<<~SQL, [current_ino, name])
          SELECT ino FROM fs_dentry
          WHERE parent_ino = ? AND name = ?
        SQL
        return nil unless row

        current_ino = row[0]
      end

      current_ino
    end

    # Resolve path to inode or throw ENOENT
    # @param path [String]
    # @param syscall [String]
    # @return [Array<String, Integer>] [normalized_path, ino]
    # @raise [ErrnoException]
    def resolve_path_or_throw(path, syscall)
      normalized = normalize_path(path)
      ino = resolve_path(normalized)
      unless ino
        raise ErrnoException.new(
          code: ErrorCodes::ENOENT,
          syscall: syscall,
          path: normalized,
          message: "no such file or directory"
        )
      end
      [normalized, ino]
    end

    # Get parent directory inode and basename from path
    # @param path [String]
    # @return [Array(Integer, String), nil]
    def resolve_parent(path)
      normalized = normalize_path(path)
      return nil if normalized == "/"

      parts = split_path(normalized)
      name = parts.last
      parent_path = parts.length == 1 ? "/" : "/#{parts[0..-2].join('/')}"

      parent_ino = resolve_path(parent_path)
      return nil unless parent_ino

      [parent_ino, name]
    end

    # Create an inode
    # @param mode [Integer]
    # @param uid [Integer]
    # @param gid [Integer]
    # @return [Integer] The new inode number
    def create_inode(mode, uid: 0, gid: 0)
      now = Time.now.to_i
      @db.execute(<<~SQL, [mode, uid, gid, now, now, now])
        INSERT INTO fs_inode (mode, uid, gid, size, atime, mtime, ctime)
        VALUES (?, ?, ?, 0, ?, ?, ?)
      SQL
      @db.last_insert_row_id
    end

    # Create a directory entry
    # @param parent_ino [Integer]
    # @param name [String]
    # @param ino [Integer]
    def create_dentry(parent_ino, name, ino)
      @db.execute(<<~SQL, [name, parent_ino, ino])
        INSERT INTO fs_dentry (name, parent_ino, ino)
        VALUES (?, ?, ?)
      SQL
      @db.execute("UPDATE fs_inode SET nlink = nlink + 1 WHERE ino = ?", [ino])
    end

    # Update file content
    # @param ino [Integer]
    # @param content [String, bytes]
    # @param encoding [String]
    def update_file_content(ino, content, encoding)
      buffer = content.is_a?(String) && encoding ? content.encode(encoding) : content.to_s
      now = Time.now.to_i

      @db.execute("DELETE FROM fs_data WHERE ino = ?", [ino])

      if buffer.length > 0
        chunk_index = 0
        (0...buffer.length).step(@chunk_size) do |offset|
          chunk = buffer[offset, @chunk_size]
          @db.execute(<<~SQL, [ino, chunk_index, SQLite3::Blob.new(chunk)])
            INSERT INTO fs_data (ino, chunk_index, data)
            VALUES (?, ?, ?)
          SQL
          chunk_index += 1
        end
      end

      @db.execute(<<~SQL, [buffer.length, now, ino])
        UPDATE fs_inode
        SET size = ?, mtime = ?
        WHERE ino = ?
      SQL
    end

    # Ensure parent directories exist
    # @param path [String]
    def ensure_parent_dirs(path)
      parts = split_path(path)
      parts.pop # Remove the filename

      current_ino = @root_ino

      parts.each do |name|
        row = @db.get_first_row(<<~SQL, [current_ino, name])
          SELECT ino FROM fs_dentry
          WHERE parent_ino = ? AND name = ?
        SQL

        if row
          current_ino = row[0]
        else
          dir_ino = create_inode(Constants::DEFAULT_DIR_MODE)
          create_dentry(current_ino, name, dir_ino)
          current_ino = dir_ino
        end
      end
    end

    # Remove directory entry and inode if last link
    # @param parent_ino [Integer]
    # @param name [String]
    # @param ino [Integer]
    def remove_dentry_and_maybe_inode(parent_ino, name, ino)
      @db.execute(<<~SQL, [parent_ino, name])
        DELETE FROM fs_dentry
        WHERE parent_ino = ? AND name = ?
      SQL

      @db.execute("UPDATE fs_inode SET nlink = nlink - 1 WHERE ino = ?", [ino])

      link_count = @db.get_first_row("SELECT nlink FROM fs_inode WHERE ino = ?", [ino])&.first.to_i
      if link_count == 0
        @db.execute("DELETE FROM fs_inode WHERE ino = ?", [ino])
        @db.execute("DELETE FROM fs_data WHERE ino = ?", [ino])
      end
    end

    # Recursively remove directory contents
    # @param dir_ino [Integer]
    def rm_dir_contents_recursive(dir_ino)
      rows = @db.execute(<<~SQL, [dir_ino])
        SELECT name, ino FROM fs_dentry
        WHERE parent_ino = ?
        ORDER BY name ASC
      SQL

      rows.each do |name, child_ino|
        mode = Guards.get_inode_mode(@db, child_ino)
        next unless mode

        if Guards.dir_mode?(mode)
          rm_dir_contents_recursive(child_ino)
          remove_dentry_and_maybe_inode(dir_ino, name, child_ino)
        else
          Guards.assert_not_symlink_mode(mode, Syscalls::RM, "<symlink>")
          remove_dentry_and_maybe_inode(dir_ino, name, child_ino)
        end
      end
    end
  end
end
