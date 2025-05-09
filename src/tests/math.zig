const std = @import("std");

comptime {
    _ = @import("math/matrix.zig");
    std.testing.refAllDeclsRecursive(@This());
}
