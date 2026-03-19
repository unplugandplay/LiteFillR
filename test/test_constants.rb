# frozen_string_literal: true

require_relative "test_helper"

class TestConstants < LiteFillRTest
  def test_file_type_masks
    assert_equal 0o170000, LiteFillR::Constants::S_IFMT
    assert_equal 0o100000, LiteFillR::Constants::S_IFREG
    assert_equal 0o040000, LiteFillR::Constants::S_IFDIR
    assert_equal 0o120000, LiteFillR::Constants::S_IFLNK
  end

  def test_default_permissions
    assert_equal 0o100644, LiteFillR::Constants::DEFAULT_FILE_MODE
    assert_equal 0o040755, LiteFillR::Constants::DEFAULT_DIR_MODE
  end

  def test_default_chunk_size
    assert_equal 4096, LiteFillR::Constants::DEFAULT_CHUNK_SIZE
  end

  def test_file_type_identification
    file_mode = LiteFillR::Constants::S_IFREG | 0o644
    dir_mode = LiteFillR::Constants::S_IFDIR | 0o755
    symlink_mode = LiteFillR::Constants::S_IFLNK | 0o777

    assert_equal LiteFillR::Constants::S_IFREG, file_mode & LiteFillR::Constants::S_IFMT
    assert_equal LiteFillR::Constants::S_IFDIR, dir_mode & LiteFillR::Constants::S_IFMT
    assert_equal LiteFillR::Constants::S_IFLNK, symlink_mode & LiteFillR::Constants::S_IFMT
  end
end
