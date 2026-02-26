const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;

pub const input = @import("input.zig");
pub const ioctl = @import("ioctl.zig");

pub const pulse = @import("pulse.zig");
pub const libudev = @import("libudev.zig");
pub const libdecor = @import("libdecor.zig");

pub const MAP = linux.MAP;
pub const O = linux.O;
pub const POLL = linux.POLL;
pub const PROT = linux.PROT;
pub const S = linux.S;
pub const fd_t = linux.fd_t;
pub const mode_t = linux.mode_t;
pub const pollfd = linux.pollfd;
pub const timeval = linux.timeval;
pub const timespec = linux.timespec;

pub const errno = posix.errno;
pub const ftruncate = linux.ftruncate;
pub const mmap = posix.mmap;
pub const mprotect = linux.mprotect;
pub const munmap = posix.munmap;
pub const poll = posix.poll;
pub const read = posix.read;
pub const write = linux.write;
pub const open = linux.open;
pub const close = linux.close;

pub const Stat = extern struct {
    const __dev_t = c_ulong;
    const __ino_t = c_ulong;
    const __nlink_t = c_ulong;
    const __mode_t = c_uint;
    const __uid_t = c_uint;
    const __gid_t = c_uint;
    const __off_t = c_long;
    const __blksize_t = c_long;
    const __blkcnt_t = c_long;
    const __syscall_slong_t = c_long;

    st_dev: __dev_t = 0,
    st_ino: __ino_t = 0,
    st_nlink: __nlink_t = 0,
    st_mode: __mode_t = 0,
    st_uid: __uid_t = 0,
    st_gid: __gid_t = 0,
    __pad0: c_int = 0,
    st_rdev: __dev_t = 0,
    st_size: __off_t = 0,
    st_blksize: __blksize_t = 0,
    st_blocks: __blkcnt_t = 0,
    st_atim: timespec = @import("std").mem.zeroes(timespec),
    st_mtim: timespec = @import("std").mem.zeroes(timespec),
    st_ctim: timespec = @import("std").mem.zeroes(timespec),
    __glibc_reserved: [3]__syscall_slong_t = @import("std").mem.zeroes([3]__syscall_slong_t),
};

pub extern fn stat(noalias __file: [*c]const u8, noalias __buf: [*c]Stat) c_int;

const c = @cImport({
    @cInclude("sys/stat.h");
});
