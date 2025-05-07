const std = @import("std");

pub const vector = @import("vector.zig");
pub const matrix = @import("matrix.zig");

pub const Vec = vector.Vec;
pub const Mat = matrix.Mat;

pub const FORCE_DEPTH_ZERO_TO_ONE = true;
pub const FLOAT_EPSILON = 0.00001;

pub const degrees = std.math.radiansToDegrees;
pub const radians = std.math.degreesToRadians;

pub const Vec2 = vector.Vec2f32;
pub const Vec3 = vector.Vec3f32;
pub const Vec4 = vector.Vec4f32;
pub const Mat2 = matrix.Mat2f32;
pub const Mat3 = matrix.Mat3f32;
pub const Mat4 = matrix.Mat4f32;

pub inline fn translate(mat: Mat4, translation: Vec3) Mat4 {
    var r = mat;

    r.data[12] += r.data[0] * translation.x + r.data[4] * translation.y + r.data[8] * translation.z;
    r.data[13] += r.data[1] * translation.x + r.data[5] * translation.y + r.data[9] * translation.z;
    r.data[14] += r.data[2] * translation.x + r.data[6] * translation.y + r.data[10] * translation.z;

    return r;
}

pub inline fn scale(mat: Mat4, scalev: Vec3) Mat4 {
    var r = mat;

    r.data[0] *= scalev.x;
    r.data[1] *= scalev.x;
    r.data[2] *= scalev.x;

    r.data[4] *= scalev.y;
    r.data[5] *= scalev.y;
    r.data[6] *= scalev.y;

    r.data[8] *= scalev.z;
    r.data[9] *= scalev.z;
    r.data[10] *= scalev.z;

    return r;
}

pub inline fn rotate(mat: Mat4, angle: Vec3.T, axis: Vec3) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);

    const axis_n = axis.normalized();
    const temp = axis_n.mul_scalar(1 - c);

    const rot = Mat4{ .data = .{
        c + temp.x * axis_n.x,
        temp.x * axis_n.y + s * axis_n.z,
        temp.x * axis_n.z - s * axis_n.y,
        0,

        temp.y * axis_n.x - s * axis_n.z,
        c + temp.y * axis_n.y,
        temp.y * axis_n.z + s * axis_n.x,
        0,

        temp.z * axis_n.x + s * axis_n.y,
        temp.z * axis_n.y - s * axis_n.x,
        c + temp.z * axis_n.z,
        0,

        0,
        0,
        0,
        0,
    } };

    const c0 = mat.col(0);
    const c1 = mat.col(1);
    const c2 = mat.col(2);

    const rc0 = c0.mul_scalar(rot.data[0]).add(c1.mul_scalar(rot.data[1])).add(c2.mul_scalar(rot.data[2]));
    const rc1 = c0.mul_scalar(rot.data[4]).add(c1.mul_scalar(rot.data[5])).add(c2.mul_scalar(rot.data[6]));
    const rc2 = c0.mul_scalar(rot.data[8]).add(c1.mul_scalar(rot.data[9])).add(c2.mul_scalar(rot.data[10]));
    const rc3 = mat.col(3);

    return Mat4{ .data = .{
        rc0.x, rc0.y, rc0.z, rc0.w,
        rc1.x, rc1.y, rc1.z, rc1.w,
        rc2.x, rc2.y, rc2.z, rc2.w,
        rc3.x, rc3.y, rc3.z, rc3.w,
    } };
}
