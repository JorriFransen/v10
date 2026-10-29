const os_tag = @import("builtin").target.os.tag;

pub const linux = @import("linux/linux.zig");
pub const win32 = @import("win32/win32.zig");

const _posix = @import("posix.zig");
const os_posix = switch (os_tag) {
    else => @compileError("Unsupported os: {s}" ++ @tagName(os_tag)),
    .linux => .{ linux, _posix },
    .windows => .{ win32, void },
};

pub const current = os_posix[0];
pub const posix = os_posix[1];
