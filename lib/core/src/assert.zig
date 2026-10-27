const std = @import("std");
const builtin = @import("builtin");

pub fn assert(cond: bool) void {
    if (@inComptime()) {
        if (!cond) {
            @trap();
        }
    } else if (builtin.mode == .debug or builtin.mode == .safe) {
        if (!cond) {
            @branchHint(.cold);
            @disableInstrumentation();
            std.debug.dumpCurrentStackTrace(.{ .first_address = @returnAddress() });
            @breakpoint();
            unreachable;
        }
    }
}
