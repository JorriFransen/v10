const std = @import("std");

const arch = @import("builtin").target.cpu.arch;

pub const abi = switch (arch) {
    else => @compileError(std.fmt.comptimePrint("Unsupported abi architecture: {}", .{arch})),

    .x86_64 => @import("x86_64.zig"),
};
