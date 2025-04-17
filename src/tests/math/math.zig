const std = @import("std");

comptime {
    _ = @import("matrix.zig");
    std.testing.refAllDeclsRecursive(@This());
}
