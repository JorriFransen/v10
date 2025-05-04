const std = @import("std");
const math = @import("math");

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat2 = math.Mat2;
const Mat3 = math.Mat3;
const Mat4 = math.Mat4;

translation: Vec3 = Vec3.scalar(0),
scale: Vec3 = Vec3.scalar(1),
rotation: Vec3 = Vec3.scalar(0),

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
    const transform = math.translate(Mat4.identity, this.translation);

    // transform = math.rotate(transform, this.rotation.y, Vec3.new(0, 1, 0));
    // transform = math.rotate(transform, this.rotation.x, Vec3.new(1, 0, 0));
    // transform = math.rotate(transform, this.rotation.z, Vec3.new(0, 0, 1));
    //
    // transform = math.scale(transform, this.scale);

    return transform;
}
