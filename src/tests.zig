const std = @import("std");

comptime {
    _ = @import("math/math.zig");
    std.testing.refAllDeclsRecursive(@This());
}
