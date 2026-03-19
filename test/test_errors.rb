# frozen_string_literal: true

require_relative "test_helper"

class TestErrnoException < LiteFillRTest
  def test_stores_error_code_syscall_and_path
    err = LiteFillR::ErrnoException.new(
      code: LiteFillR::ErrorCodes::ENOENT,
      syscall: LiteFillR::Syscalls::OPEN,
      path: "/test.txt"
    )

    assert_equal "ENOENT", err.code
    assert_equal "open", err.syscall
    assert_equal "/test.txt", err.path
  end

  def test_generates_readable_message
    err = LiteFillR::ErrnoException.new(
      code: LiteFillR::ErrorCodes::ENOENT,
      syscall: LiteFillR::Syscalls::OPEN,
      path: "/test.txt"
    )

    assert_equal "ENOENT: ENOENT, open '/test.txt'", err.message
  end

  def test_uses_custom_message_when_provided
    err = LiteFillR::ErrnoException.new(
      code: LiteFillR::ErrorCodes::ENOENT,
      syscall: LiteFillR::Syscalls::OPEN,
      path: "/test.txt",
      message: "custom message"
    )

    assert_equal "ENOENT: custom message, open '/test.txt'", err.message
  end

  def test_handles_nil_path
    err = LiteFillR::ErrnoException.new(
      code: LiteFillR::ErrorCodes::EINVAL,
      syscall: LiteFillR::Syscalls::MKDIR
    )

    assert_equal "EINVAL: EINVAL, mkdir", err.message
    assert_nil err.path
  end
end

class TestErrorCodes < LiteFillRTest
  def test_all_posix_error_codes
    assert_equal "ENOENT", LiteFillR::ErrorCodes::ENOENT
    assert_equal "EEXIST", LiteFillR::ErrorCodes::EEXIST
    assert_equal "EISDIR", LiteFillR::ErrorCodes::EISDIR
    assert_equal "ENOTDIR", LiteFillR::ErrorCodes::ENOTDIR
    assert_equal "ENOTEMPTY", LiteFillR::ErrorCodes::ENOTEMPTY
    assert_equal "EPERM", LiteFillR::ErrorCodes::EPERM
    assert_equal "EINVAL", LiteFillR::ErrorCodes::EINVAL
    assert_equal "ENOSYS", LiteFillR::ErrorCodes::ENOSYS
  end
end

class TestSyscalls < LiteFillRTest
  def test_all_syscall_names
    assert_equal "open", LiteFillR::Syscalls::OPEN
    assert_equal "stat", LiteFillR::Syscalls::STAT
    assert_equal "mkdir", LiteFillR::Syscalls::MKDIR
    assert_equal "rmdir", LiteFillR::Syscalls::RMDIR
    assert_equal "rm", LiteFillR::Syscalls::RM
    assert_equal "unlink", LiteFillR::Syscalls::UNLINK
    assert_equal "rename", LiteFillR::Syscalls::RENAME
    assert_equal "scandir", LiteFillR::Syscalls::SCANDIR
    assert_equal "copyfile", LiteFillR::Syscalls::COPYFILE
    assert_equal "access", LiteFillR::Syscalls::ACCESS
  end
end
