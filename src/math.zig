const std = @import("std");

pub const GeometricEpsilon = 1e-6;

pub const degrees = std.math.radiansToDegrees;
pub const radians = std.math.degreesToRadians;

pub const vector = @import("math/vector.zig");
pub const matrix = @import("math/matrix.zig");
pub const rect = @import("math/rect.zig");

pub const Vec = vector.Vec;
pub const Mat = matrix.Mat;
pub const RectT = rect.RectT;

pub const Vec2 = vector.Vec2f32;
pub const Vec3 = vector.Vec3f32;
pub const Vec4 = vector.Vec4f32;
pub const Mat2 = matrix.Mat2f32;
pub const Mat3 = matrix.Mat3f32;
pub const Mat4 = matrix.Mat4f32;
pub const Rect = rect.Rectf32;

pub inline fn epsWith(comptime T: type, e: T, a: T) T {
    return @max(
        std.math.floatEps(T) * 4,
        std.math.floatEpsAt(T, e),
        std.math.floatEpsAt(T, a),
    );
}

pub inline fn eqlEps(comptime T: type, a: T, b: T) bool {
    const abs_diff = @abs(a - b);
    const eps = epsWith(T, a, b);
    return abs_diff <= eps;
}

pub inline fn intToIntVec(comptime IvIn: type, comptime IvOut: type, iv: IvIn) IvOut {
    return IvOut.v(@intCast(iv.vector()));
}

pub inline fn floatToFloatVec(comptime FvIn: type, comptime FvOut: type, fv: FvIn) FvOut {
    return FvOut.v(@floatCast(fv.vector()));
}

pub inline fn intToFloatVec(comptime IV: type, comptime FV: type, iv: IV) FV {
    return FV.v(@floatFromInt(iv.vector()));
}
