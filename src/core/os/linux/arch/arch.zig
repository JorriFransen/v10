const std = @import("std");
const builtin = @import("builtin");

pub const arch = switch (builtin.cpu.arch) {
    else => @compileError(std.fmt.comptimePrint("Unsupported linux architecture", .{builtin.cpu.arch})),
    .x86_64 => @import("x86_64.zig"),
};
