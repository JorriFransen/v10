const std = @import("std");
const log = std.log.scoped(.@"wayland-gen");
const mem = @import("mem");

const Parser = @import("parser.zig");
const Generator = @import("generator.zig");

const assert = std.debug.assert;

pub fn main() !void {
    try mem.init();

    const xml_path = "wayland.xml";

    var parse_arena = try mem.Arena.init(.{ .virtual = .{} });

    var parser = try Parser.init(parse_arena.allocator(), xml_path);
    defer parser.deinit();

    var wayland_protocol = try parser.parse();

    Generator.generate(&wayland_protocol);
    parse_arena.reset();
}
