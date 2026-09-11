const std = @import("std");

pub fn assert(cond: bool) void {
    if (@inComptime()) {
        if (!cond) {
            @trap();
        }
    } else {
        if (!cond) {
            @branchHint(.cold);
            std.debug.dumpCurrentStackTrace(.{ .first_address = @returnAddress() });
            @breakpoint();
        }
    }
}
