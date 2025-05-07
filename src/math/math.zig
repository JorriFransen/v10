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
