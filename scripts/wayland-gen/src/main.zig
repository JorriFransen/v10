const std = @import("std");
const log = std.log.scoped(.@"wayland-gen");

const Parser = @import("parser.zig");
const Generator = @import("generator.zig");

const assert = std.debug.assert;

pub fn main() !void {
    const xml_path = "wayland.xml";

    var gpa = std.heap.DebugAllocator(.{}).init;
    // For some reason using this causes a spurious error in zig-xml. I've seen multiple weird (seemingly memory related) errors from zig-xml...
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    var parser = try Parser.init(gpa.allocator(), xml_path);
    defer parser.deinit();

    var wayland_protocol = try parser.parse();

    Generator.generate(&wayland_protocol);
}
