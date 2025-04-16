const gfx = @import("gfx/gfx.zig");
const Vec2 = gfx.Vec2;
const Mat2 = gfx.Mat2;

translation: Vec2 = Vec2.scalar(0),
scale: Vec2 = Vec2.scalar(1),
rotation: Vec2.T = 0,

pub fn mat2(this: @This()) Mat2 {
    const s = @sin(this.rotation);
    const c = @cos(this.rotation);

    const rotation = Mat2.new(.{
        c, -s,
        s, c,
    });

    const scale = Mat2.new(.{
        this.scale.x, 0,
        0,            this.scale.y,
    });

    return rotation.mul(scale);
}
