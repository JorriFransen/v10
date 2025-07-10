const std = @import("std");

pub const GeometricEpsilon = 1e-6;

pub inline fn eps(comptime T: type, e: T, a: T) T {
    return @max(
        std.math.floatEps(T) * 4,
        std.math.floatEpsAt(T, e),
        std.math.floatEpsAt(T, a),
    );
}

pub const vector = @import("math/vector.zig");
pub const matrix = @import("math/matrix.zig");

pub const Vec = vector.Vec;
pub const Mat = matrix.Mat;

pub const degrees = std.math.radiansToDegrees;
pub const radians = std.math.degreesToRadians;

pub const Vec2 = vector.Vec2f32;
pub const Vec3 = vector.Vec3f32;
pub const Vec4 = vector.Vec4f32;
pub const Mat2 = matrix.Mat2f32;
pub const Mat3 = matrix.Mat3f32;
pub const Mat4 = matrix.Mat4f32;
