const std = @import("std");

comptime {
    _ = @import("math.zig");
    std.testing.refAllDeclsRecursive(@This());
}
