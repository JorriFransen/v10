const gfx = @import("gfx.zig");
const math = @import("math.zig");

const Transform = @import("transform.zig");
const ID = usize;
const GpuModel = gfx.GpuModel;
const Vec3 = math.Vec3;

var current_id: ID = 0;

id: ID = undefined,
model: ?*const GpuModel = null,
color: Vec3 = Vec3.new(1, 1, 1),
transform: Transform = .{},

pub fn new() @This() {
    const result = @This(){
        .id = current_id,
    };

    return result;
}
