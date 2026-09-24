const builtin = @import("builtin");

pub const linux = @import("linux/linux.zig");
pub const win32 = @import("win32/win32.zig");

pub const current = switch (builtin.os.tag) {
    else => @compileError("Unsupported os: {s}" ++ @tagName(builtin.os.tag)),
    .linux => linux,
    .windows => win32,
};
