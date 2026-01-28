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
pub const Statx = linux.Statx;

pub const errno = posix.errno;
pub const ftruncate = linux.ftruncate;
pub const mmap = posix.mmap;
pub const mprotect = linux.mprotect;
pub const munmap = posix.munmap;
pub const poll = posix.poll;
pub const read = posix.read;
pub const write = linux.write;
pub const open = linux.open;
pub const close = posix.close;
pub const statx = linux.statx;
