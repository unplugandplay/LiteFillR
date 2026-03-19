# frozen_string_literal: true

module LiteFillR
  # Filesystem constants for mode field
  module Constants
    # File type mask
    S_IFMT  = 0o170000
    # Regular file
    S_IFREG = 0o100000
    # Directory
    S_IFDIR = 0o040000
    # Symbolic link
    S_IFLNK = 0o120000

    # Default permissions
    # Regular file, rw-r--r--
    DEFAULT_FILE_MODE = S_IFREG | 0o644
    # Directory, rwxr-xr-x
    DEFAULT_DIR_MODE  = S_IFDIR | 0o755

    # Default chunk size for file storage (4KB)
    DEFAULT_CHUNK_SIZE = 4096
  end
end
