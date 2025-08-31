const std = @import("std");
const log = std.log.scoped(.@"wayland-gen");
const mem = @import("mem");

const parser = @import("parser.zig");
const generator = @import("generator.zig");

const assert = std.debug.assert;

pub fn main() !void {
    try mem.init();

    const xml_path = "wayland.xml";

    var parse_arena = try mem.Arena.init(.{ .virtual = .{} });
    var gen_arena = try mem.Arena.init(.{ .virtual = .{} });

    var wayland_protocol = try parser.parse(parse_arena.allocator(), xml_path);

    const result = generator.generate(gen_arena.allocator(), &wayland_protocol);
    parse_arena.reset();

    log.debug("result:\n{s}", .{result});
}
