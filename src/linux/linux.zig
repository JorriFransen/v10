const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;

pub const input = @import("input.zig");
pub const ioctl = @import("ioctl.zig");

pub const alsa = @import("alsa.zig");
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
pub const Stat = linux.Stat;

pub const errno = posix.errno;
pub const ftruncate = posix.ftruncate;
pub const mmap = posix.mmap;
pub const mprotect = posix.mprotect;
pub const munmap = posix.munmap;
pub const poll = posix.poll;
pub const read = posix.read;
pub const write = posix.write;
pub const open = posix.open;
pub const openZ = posix.openZ;
pub const close = posix.close;
pub const fstat = posix.fstat;
