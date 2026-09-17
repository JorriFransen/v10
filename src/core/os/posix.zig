const std = @import("std");
const builtin = @import("builtin");

const os = @import("os.zig");
const win32 = os.win32;

const Os = os.current;
const AT = Os.AT;
const O = Os.O;
const mode_t = Os.mode_t;
const openat = Os.openat;
const unlink = Os.unlink;

pub const fd_t = system.fd_t;
pub const PATH_MAX = system.PATH_MAX;

const system = switch (builtin.os.tag) {
    else => @compileError("Unsupported os: {s}" ++ @tagName(builtin.os.tag)),
    .linux => Os,
    .windows => struct {
        pub const fd_t = win32.HANDLE;
        pub const PATH_MAX = win32.MAX_PATH_WIDE;
    },
};

// =============================================================================
// mman.h
// =============================================================================

inline fn getShmPath(name: [:0]const u8) error{NoSpaceLeft}![:0]const u8 {
    var name_buf: [PATH_MAX]u8 = undefined;
    const path_fmt = std.fs.path.fmtJoin(&.{ "/dev/shm/", name });
    return try std.fmt.bufPrintSentinel(&name_buf, "{f}", .{path_fmt}, 0);
}

pub const ShmopenError = Os.OpenatError || error{
    NoSpaceLeft,
    UnexpectedErrno,
};

pub fn shm_open(name: [:0]const u8, oflag: O, mode: mode_t) ShmopenError!c_int {
    const path = try getShmPath(name);

    const fd = try openat(AT.FDCWD, path, oflag, mode);
    return fd;
}

pub const ShmunlinkError = Os.UnlinkError || error{
    NoSpaceLeft,
    UnexpectedErrno,
};

pub fn shm_unlink(name: [:0]const u8) ShmunlinkError!void {
    const path = try getShmPath(name);
    try unlink(path);
}
