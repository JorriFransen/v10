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

pub const close = linux.close;
pub const errno = posix.errno;
pub const ftruncate = linux.ftruncate;
pub const mmap = linux.mmap;
pub const mprotect = linux.mprotect;
pub const munmap = linux.munmap;
pub const open = linux.open;
pub const poll = linux.poll;
pub const read = linux.read;
