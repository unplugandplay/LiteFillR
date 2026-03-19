# frozen_string_literal: true

module LiteFillR
  # POSIX-style error codes for filesystem operations
  module ErrorCodes
    ENOENT    = "ENOENT"    # No such file or directory
    EEXIST    = "EEXIST"    # File already exists
    EISDIR    = "EISDIR"    # Is a directory (when file expected)
    ENOTDIR   = "ENOTDIR"   # Not a directory (when directory expected)
    ENOTEMPTY = "ENOTEMPTY" # Directory not empty
    EPERM     = "EPERM"     # Operation not permitted
    EINVAL    = "EINVAL"    # Invalid argument
    ENOSYS    = "ENOSYS"    # Function not implemented (use for symlinks)
  end

  # Filesystem syscall names for error reporting
  # rm, scandir and copyfile are not actual syscalls but used for convenience
  module Syscalls
    OPEN     = "open"
    STAT     = "stat"
    MKDIR    = "mkdir"
    RMDIR    = "rmdir"
    RM       = "rm"
    UNLINK   = "unlink"
    RENAME   = "rename"
    SCANDIR  = "scandir"
    COPYFILE = "copyfile"
    ACCESS   = "access"
  end

  # Exception with errno-style attributes
  class ErrnoException < StandardError
    attr_reader :code, :syscall, :path

    # @param code [String] POSIX error code (e.g., 'ENOENT')
    # @param syscall [String] System call name (e.g., 'open')
    # @param path [String, nil] Optional path involved in the error
    # @param message [String, nil] Optional custom message (defaults to code)
    def initialize(code:, syscall:, path: nil, message: nil)
      @code = code
      @syscall = syscall
      @path = path

      base = message || code
      suffix = path ? " '#{path}'" : ""
      super("#{code}: #{base}, #{syscall}#{suffix}")
    end
  end
end
