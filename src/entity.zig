const gfx = @import("gfx/gfx.zig");
const math = @import("math");

const Transform = @import("transform2d.zig");
const ID = usize;
const Model = gfx.Model;
const Vec3 = math.Vec3;

var current_id: ID = 0;

id: ID = undefined,
model: *const Model = undefined,
color: Vec3 = Vec3.new(1, 1, 1),
transform: Transform = .{},

pub fn new() @This() {
    const result = @This(){
        .id = current_id,
    };

    return result;
}
