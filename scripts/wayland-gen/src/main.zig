const std = @import("std");
const log = std.log.scoped(.@"wayland-gen");

const Parser = @import("parser.zig");

const assert = std.debug.assert;

pub fn main() !void {
    const xml_path = "/usr/share/wayland/wayland.xml";

    var parser = try Parser.init(xml_path);
    defer parser.deinit();

    const protocol = try parser.parse();
    _ = protocol;
}
