const std = @import("std");
const builtin = @import("builtin");

pub fn assert(cond: bool) void {
    if (@inComptime()) {
        if (!cond) {
            @trap();
        }
    } else if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        if (!cond) {
            @branchHint(.cold);
            std.debug.dumpCurrentStackTrace(.{ .first_address = @returnAddress() });
            @breakpoint();
        }
    }
}
