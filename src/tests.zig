pub const std = @import("std");
const t = std.testing;

comptime {
    t.refAllDecls(@import("memory"));
    t.refAllDecls(@import("math.zig"));
    t.refAllDecls(@import("obj_parser.zig"));
}
