const t = @import("std").testing;

pub const memory = @import("memory.zig");
pub const math = @import("math.zig");
pub const obj_parser = @import("obj_parser.zig");

comptime {
    t.refAllDeclsRecursive(@This());
}
