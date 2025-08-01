const math = @import("../math.zig");

const Vec = math.Vec;

pub const Rectf32 = RectT(f32);

pub fn RectT(comptime T: type) type {
    return struct {
        pos: Vec(2, T) = .{},
        size: Vec(2, T) = .{},
    };
}
