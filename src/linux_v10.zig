const std = @import("std");
const log = std.log.scoped(.linux_v10);

const assert = std.debug.assert;

var running = false;

pub fn main() !void {
    log.debug("Herro!", .{});
}

fn LinuxUpdateWindow() void {
    unreachable;
}
