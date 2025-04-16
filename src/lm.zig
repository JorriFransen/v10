const std = @import("std");

// https://stackoverflow.com/questions/49346732/vulkan-right-handed-coordinate-system-become-left-handed

pub const FORCE_DEPTH_ZERO_TO_ONE = true;
pub const FLOAT_EPSILON = 0.00001;

pub const degrees = std.math.radiansToDegrees;
pub const radians = std.math.degreesToRadians;

pub const Vec2f32 = Vec(2, f32);
pub const Vec3f32 = Vec(3, f32);
pub const Vec4f32 = Vec(4, f32);
pub const Mat4f32 = Mat(4, 4, f32);

pub fn Vec(comptime N: usize, comptime T: type) type {
    const V = @Vector(N, T);

    switch (N) {
        else => @compileError("N must be between 2 and 4"),

        2 => return extern struct {
            x: T,
            y: T,
            pub fn new(x: T, y: T) @This() {
                return @bitCast(V{ x, y });
            }
            pub usingnamespace VecFunctionsMixin(N, T, @This());
        },

        3 => return extern struct {
            x: T,
            y: T,
            z: T,
            pub fn new(x: T, y: T, z: T) @This() {
                return @bitCast(V{ x, y, z });
            }
            pub usingnamespace VecFunctionsMixin(N, T, @This());
        },

        4 => return extern struct {
            x: T,
            y: T,
            z: T,
            w: T,
            pub fn new(x: T, y: T, z: T, w: T) @This() {
                return @bitCast(V{ x, y, z, w });
            }
            pub usingnamespace VecFunctionsMixin(N, T, @This());
        },
    }
}

pub fn VecFunctionsMixin(comptime N: usize, comptime T: type, comptime Base: type) type {
    const V = @Vector(N, T);
    return extern struct {
        pub inline fn fromVector(v: V) Base {
            return @bitCast(v);
        }
        pub inline fn toVector(base: Base) V {
            return @bitCast(base);
        }
        pub inline fn scalar(s: T) Base {
            return @bitCast(@as(V, @splat(s)));
        }
    };
}

pub fn Mat(comptime c: usize, comptime r: usize, comptime T: type) type {
    return extern struct {
        data: [C * R]T,

        pub const C = c;
        pub const R = r;
    };
}
