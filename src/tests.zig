const std = @import("std");

comptime {
    _ = @import("lm.zig");
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
