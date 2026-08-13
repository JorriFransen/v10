const std = @import("std");

const Os = @import("os.zig").current;
const AT = Os.AT;
const O = Os.O;
const mode_t = Os.mode_t;
const openat = Os.openat;
const unlink = Os.unlink;

// =============================================================================
// sys/mman.h
// =============================================================================

pub const ShmError = Os.Error || std.fmt.BufPrintError;

inline fn getShmPath(name: [:0]const u8) std.fmt.BufPrintError![:0]const u8 {
    var name_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_fmt = std.fs.path.fmtJoin(&.{ "/dev/shm/", name });
    return try std.fmt.bufPrintSentinel(&name_buf, "{f}", .{path_fmt}, 0);
}

pub fn shm_open(name: [:0]const u8, oflag: O, mode: mode_t) ShmError!c_int {
    const path = try getShmPath(name);

    const fd = try openat(AT.FDCWD, path, oflag, mode);
    return fd;
}

pub fn shm_unlink(name: [:0]const u8) ShmError!void {
    const path = try getShmPath(name);
    try unlink(path);
}
