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
    // pub fn mat4Slow(this: @This()) Mat4 {
    //     var transform = Mat4.translation(this.translation);
    //
    //     transform = transform.rotate(this.rotation.y, Vec3.new(0, 1, 0));
    //     transform = transform.rotate(this.rotation.x, Vec3.new(1, 0, 0));
    //     transform = transform.rotate(this.rotation.z, Vec3.new(0, 0, 1));
    //
    //     return transform.scale(this.scale);
    // }

    const c3 = @cos(this.rotation.z);
    const s3 = @sin(this.rotation.z);
    const c2 = @cos(this.rotation.x);
    const s2 = @sin(this.rotation.x);
    const c1 = @cos(this.rotation.y);
    const s1 = @sin(this.rotation.y);

    return Mat4{ .data = .{
        this.scale.x * (c1 * c3 + s1 * s2 * s3),
        this.scale.x * (c2 * s3),
        this.scale.x * (c1 * s2 * s3 - c3 * s1),
        0,

        this.scale.y * (c3 * s1 * s2 - c1 * s3),
        this.scale.y * (c2 * c3),
        this.scale.y * (c1 * c3 * s2 + s1 * s3),
        0,

        this.scale.z * (c2 * s1),
        this.scale.z * (-s2),
        this.scale.z * (c1 * c2),
        0,

        this.translation.x,
        this.translation.y,
        this.translation.z,
        1,
    } };
}
