const t = @import("std").testing;

pub const memory = @import("memory.zig");
pub const math = @import("math.zig");

comptime {
    t.refAllDeclsRecursive(@This());
}
