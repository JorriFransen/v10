const std = @import("std");
const builtin = @import("builtin");

pub const linux = @import("linux/linux.zig");
pub const win32 = @import("win32/win32.zig");

const _posix = @import("posix.zig");
const os_posix = switch (builtin.os.tag) {
    else => @compileError(std.fmt.comptimePrint("Unsupported os: {s}", .{@tagName(builtin.os.tag)})),
    .linux => .{ linux, _posix },
    .windows => .{ win32, void },
};

pub const current = os_posix[0];
pub const posix = os_posix[1];
