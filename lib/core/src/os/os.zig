const os_tag = @import("builtin").target.os.tag;

pub const linux = @import("linux/linux.zig");
pub const win32 = @import("win32/win32.zig");

pub const current = switch (os_tag) {
    else => @compileError("Unsupported os: " ++ @tagName(os_tag.os.tag)),
    .linux => linux,
    .windows => win32,
};
