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

    r.data[13] = r.data[13] * translation.x;
    r.data[14] = r.data[14] * translation.y;
    r.data[15] = r.data[15] * translation.z;

    return r;
}

pub inline fn scale(mat: Mat4, scalev: Vec3) Mat4 {
    var r = mat;

    r.data[0] = r.data[0] * scalev.x;
    r.data[1] = r.data[1] * scalev.x;
    r.data[2] = r.data[2] * scalev.x;

    r.data[4] = r.data[4] * scalev.y;
    r.data[5] = r.data[5] * scalev.y;
    r.data[6] = r.data[6] * scalev.y;

    r.data[8] = r.data[8] * scalev.z;
    r.data[9] = r.data[9] * scalev.z;
    r.data[10] = r.data[10] * scalev.z;

    return r;
}

pub inline fn rotate(mat: Mat4, angle: Vec3.T, axis: Vec3) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);

    const axis_n = axis.normalized();
    const temp = axis_n.mul_scalar(1 - c);

    const rc0 = Vec3.new(
        c + temp.x * axis_n.x,
        temp.x * axis_n.y + s * axis_n.z,
        temp.x * axis_n.z - s * axis_n.x,
    );
    const rc1 = Vec3.new(
        temp.y * axis_n.x - s * axis_n.z,
        c + temp.y * axis_n.y,
        temp.y * axis_n.z + s * axis_n.x,
    );
    const rc2 = Vec3.new(
        temp.z * axis_n.x + s * axis_n.y,
        temp.z * axis_n.y - s * axis_n.x,
        c + temp.z * axis_n.z,
    );

    const col0 = mat.col(0);
    const col1 = mat.col(1);
    const col2 = mat.col(2);
    const col3 = mat.col(3);

    var c0 = col0.mul_scalar(rc0.x);
    c0 = c0.add(col1.mul_scalar(rc0.y));
    c0 = c0.add(col2.mul_scalar(rc0.z));

    var c1 = col0.mul_scalar(rc1.x);
    c1 = c1.add(col1.mul_scalar(rc1.y));
    c1 = c1.add(col2.mul_scalar(rc1.z));

    var c2 = col0.mul_scalar(rc2.x);
    c2 = c2.add(col1.mul_scalar(rc2.y));
    c2 = c2.add(col2.mul_scalar(rc2.z));

    return .{ .data = .{
        c0.x,   c0.y,   c0.z,   0,
        c1.x,   c1.y,   c1.z,   0,
        c2.x,   c2.y,   c2.z,   0,
        col3.x, col3.y, col3.z, mat.data[15],
    } };
}
