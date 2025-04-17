const math = @import("math");

const Vec2 = math.Vec2;
const Mat2 = math.Mat2;
const Mat3 = math.Mat3;
const Mat4 = math.Mat4;

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

pub fn mat3(this: @This()) Mat3 {
    const translation = Mat3.new(.{
        1, 0, this.translation.x,
        0, 1, this.translation.y,
        0, 0, 1,
    });

    const s = @sin(this.rotation);
    const c = @cos(this.rotation);

    const rotation = Mat3.new(.{
        c, -s, 0,
        s, c,  0,
        0, 0,  1,
    });

    const scale = Mat3.new(.{
        this.scale.x, 0,            0,
        0,            this.scale.y, 0,
        0,            0,            1,
    });

    return translation.mul(rotation.mul(scale));
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
