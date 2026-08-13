// !NOTE: x86_64 only currently

const std = @import("std");
const builtin = @import("builtin");

pub const abi = switch (builtin.cpu.arch) {
    else => @compileError(std.fmt.comptimePrint("Unsupported abi architecture: {}", .{builtin.cpu.arch})),

    .x86_64 => @import("x86_64.zig"),
};
