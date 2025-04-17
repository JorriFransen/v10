const gfx = @import("gfx/gfx.zig");
const Vec2 = gfx.Vec2;
const Mat2 = gfx.Mat2;
const Mat4 = gfx.Mat4;

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

pub fn mat4(this: @This()) Mat4 {
    const translation = Mat4.new(.{
        1, 0, 0, this.translation.x,
        0, 1, 0, this.translation.y,
        0, 0, 1, 0,
        0, 0, 0, 1,
    });

    const s = @sin(this.rotation);
    const c = @cos(this.rotation);

    const rotation = Mat4.new(.{
        c, -s, 0, 0,
        s, c,  0, 0,
        0, 0,  1, 0,
        0, 0,  0, 1,
    });

    const scale = Mat4.new(.{
        this.scale.x, 0,            0, 0,
        0,            this.scale.y, 0, 0,

        0,            0,            1, 0,
        0,            0,            0, 1,
    });

    return translation.mul(rotation.mul(scale));
}
