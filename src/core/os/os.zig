pub const linux = @import("linux/linux.zig");
pub const win32 = @import("win32/win32.zig");

const builtin = @import("builtin");

pub const os = switch (builtin.os.tag) {
    else => @compileError("Unsupported os"),
    .linux => linux,
    .windows => win32,
};
