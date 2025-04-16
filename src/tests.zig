const std = @import("std");

comptime {
    _ = @import("lm.zig");
    std.testing.refAllDeclsRecursive(@This());
}
