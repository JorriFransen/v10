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

pub inline fn mat4(this: @This()) Mat4 {
    return Mat4.transform(this.translation, this.scale, this.rotation);
}
