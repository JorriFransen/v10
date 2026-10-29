const os_tag = @import("builtin").target.os.tag;

const posix = @import("os/posix.zig");
const win32 = @import("os/win32/win32.zig");

pub const Handle = posix.fd_t;

pub const max_path_bytes = switch (os_tag) {
    else => @compileError("Unsupported os: " ++ @tagName(os_tag)),
    .linux => posix.PATH_MAX,
    .windows => win32.PATH_MAX_WIDE,
};
