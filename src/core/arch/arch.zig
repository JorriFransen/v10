const std = @import("std");

const arch_tag = @import("builtin").target.cpu.arch;

pub const arch = switch (arch_tag) {
    else => @compileError(std.fmt.comptimePrint("Unsupported architecture: {}", .{arch_tag})),
    .x86_64 => @import("x86_64.zig"),
};
