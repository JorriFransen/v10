const std = @import("std");
const builtin = @import("builtin");

pub const arch = switch (builtin.cpu.arch) {
    .x86_64 => @import("x86_64.zig"),
    else => @compileError(std.fmt.comptimePrint("Unsupported architecture: {}", .{builtin.target.cpu.arch})),
};
