const std = @import("std");

const math = @import("../math.zig");

const assert = std.debug.assert;

pub const Vec2f32 = Vec(2, f32);
pub const Vec3f32 = Vec(3, f32);
pub const Vec4f32 = Vec(4, f32);
pub const Mat4f32 = math.matrix.Mat4f32;

pub fn Vec(comptime EN: usize, comptime ET: type) type {
    switch (EN) {
        else => @compileError("N must be between 2 and 4"),

        2 => return extern struct {
            pub const V = @Vector(EN, ET);
            pub const T = ET;
            pub const N = EN;
            const F = VecFunctionsMixin(EN, T, @This());
            x: T = 0,
            y: T = 0,
            pub inline fn new(x: T, y: T) @This() {
                return @bitCast(V{ x, y });
            }

            pub inline fn newI(x: anytype, y: anytype) @This() {
                comptime assert(@TypeOf(x) == @TypeOf(y));
                switch (@typeInfo(T)) {
                    else => @compileError("Unsupported type"),
                    .float => return new(@floatFromInt(x), @floatFromInt(y)),
                    .int => return new(@intCast(x), @intCast(x)),
                }
            }

            pub inline fn v(vec: V) @This() {
                return F.v(vec);
            }
            pub inline fn vector(vec: @This()) V {
                return F.vector(vec);
            }
            pub inline fn scalar(s: T) @This() {
                return F.scalar(s);
            }
            pub inline fn length(vec: @This()) T {
                return F.length(vec);
            }
            pub inline fn normalized(vec: @This()) @This() {
                return F.normalized(vec);
            }
            pub inline fn negate(vec: @This()) @This() {
                return F.negate(vec);
            }
            pub inline fn add(a: @This(), b: @This()) @This() {
                return F.add(a, b);
            }
            pub inline fn sub(a: @This(), b: @This()) @This() {
                return F.sub(a, b);
            }
            pub inline fn mul(a: @This(), b: @This()) @This() {
                return F.mul(a, b);
            }
            pub inline fn div(a: @This(), b: @This()) @This() {
                return F.div(a, b);
            }
            pub inline fn addScalar(vec: @This(), s: T) @This() {
                return F.addScalar(vec, s);
            }
            pub inline fn subScalar(vec: @This(), s: T) @This() {
                return F.subScalar(vec, s);
            }
            pub inline fn mulScalar(vec: @This(), s: T) @This() {
                return F.mulScalar(vec, s);
            }
            pub inline fn divScalar(vec: @This(), s: T) @This() {
                return F.divScalar(vec, s);
            }
            pub inline fn cross(a: @This(), b: @This()) @This() {
                return F.cross(a, b);
            }
            pub inline fn dot(a: @This(), b: @This()) T {
                return F.dot(a, b);
            }
            pub inline fn eql(a: @This(), b: @This()) bool {
                return F.eql(a, b);
            }
            pub inline fn eqlEps(a: @This(), b: @This()) bool {
                return F.eqlEps(a, b);
            }
            pub inline fn toVector3(vec: @This(), z: T) Vec(3, T) {
                return Vec(3, T){ .x = vec.x, .y = vec.y, .z = z };
            }
        },

        3 => return extern struct {
            pub const V = @Vector(EN, ET);
            pub const T = ET;
            pub const N = EN;
            const Vec3 = @This();
            const F = VecFunctionsMixin(EN, T, Vec3);

            x: T = 0,
            y: T = 0,
            z: T = 0,

            pub fn new(x: T, y: T, z: T) Vec3 {
                return @bitCast(V{ x, y, z });
            }
            pub inline fn v(vec: V) Vec3 {
                return F.v(vec);
            }
            pub inline fn vector(vec: Vec3) V {
                return F.vector(vec);
            }
            pub inline fn scalar(s: T) Vec3 {
                return F.scalar(s);
            }
            pub inline fn length(vec: Vec3) T {
                return F.length(vec);
            }
            pub inline fn normalized(vec: Vec3) Vec3 {
                return F.normalized(vec);
            }
            pub inline fn negate(vec: Vec3) Vec3 {
                return F.negate(vec);
            }
            pub inline fn add(a: Vec3, b: Vec3) Vec3 {
                return F.add(a, b);
            }
            pub inline fn sub(a: Vec3, b: Vec3) Vec3 {
                return F.sub(a, b);
            }
            pub inline fn mul(a: Vec3, b: Vec3) Vec3 {
                return F.mul(a, b);
            }
            pub inline fn div(a: Vec3, b: Vec3) Vec3 {
                return F.div(a, b);
            }
            pub inline fn addScalar(vec: @This(), s: T) @This() {
                return F.addScalar(vec, s);
            }
            pub inline fn subScalar(vec: @This(), s: T) @This() {
                return F.subScalar(vec, s);
            }
            pub inline fn mulScalar(vec: Vec3, s: T) Vec3 {
                return F.mulScalar(vec, s);
            }
            pub inline fn divScalar(vec: Vec3, s: T) Vec3 {
                return F.divScalar(vec, s);
            }
            pub inline fn cross(a: Vec3, b: Vec3) Vec3 {
                return F.cross(a, b);
            }
            pub inline fn dot(a: Vec3, b: Vec3) T {
                return F.dot(a, b);
            }
            pub inline fn eql(a: @This(), b: @This()) bool {
                return F.eql(a, b);
            }
            pub inline fn eqlEps(a: Vec3, b: Vec3) bool {
                return F.eqlEps(a, b);
            }
            pub fn toPoint4(this: Vec3) Vec(4, T) {
                return .{ .x = this.x, .y = this.y, .z = this.z, .w = 1 };
            }
            pub fn toVector4(this: Vec3) Vec(4, T) {
                return .{ .x = this.x, .y = this.y, .z = this.z, .w = 0 };
            }

            pub inline fn directionFromEuler(euler: Vec3) Vec3 {
                // const rot = Mat4f32.rotation(euler.y, .{ .y = 1 }) // yaw
                //     .rotate(euler.x, .{ .x = 1 }) // pitch
                //     .rotate(euler.z, .{ .z = 1 }); // roll
                // // mul_vec(.{.z=1}) // this vector is forward
                // return rot.mul_vec(.{ .z = 1 }).xyz().normalized();

                const cx = @cos(euler.x); // pitch
                const sx = @sin(euler.x);
                const cy = @cos(euler.y); // yaw
                const sy = @sin(euler.y);

                return Vec3.new(
                    cx * sy, // X component of forward
                    -sx, // Y component of forward
                    cx * cy, // Z component of forward
                ).normalized();
            }
        },

        4 => return extern struct {
            pub const V = @Vector(EN, ET);
            pub const T = ET;
            pub const N = EN;
            const F = VecFunctionsMixin(EN, T, @This());
            x: T = 0,
            y: T = 0,
            z: T = 0,
            w: T = 0,
            pub fn new(x: T, y: T, z: T, w: T) @This() {
                return @bitCast(V{ x, y, z, w });
            }
            pub fn xyz(this: @This()) Vec(3, T) {
                return .{ .x = this.x, .y = this.y, .z = this.z };
            }
            pub inline fn v(vec: V) @This() {
                return F.v(vec);
            }
            pub inline fn vector(vec: @This()) V {
                return F.vector(vec);
            }
            pub inline fn scalar(s: T) @This() {
                return F.scalar(s);
            }
            pub inline fn length(vec: @This()) T {
                return F.length(vec);
            }
            pub inline fn normalized(vec: @This()) @This() {
                return F.normalized(vec);
            }
            pub inline fn negate(vec: @This()) @This() {
                return F.negate(vec);
            }
            pub inline fn add(a: @This(), b: @This()) @This() {
                return F.add(a, b);
            }
            pub inline fn sub(a: @This(), b: @This()) @This() {
                return F.sub(a, b);
            }
            pub inline fn mul(a: @This(), b: @This()) @This() {
                return F.mul(a, b);
            }
            pub inline fn div(a: @This(), b: @This()) @This() {
                return F.div(a, b);
            }
            pub inline fn addScalar(vec: @This(), s: T) @This() {
                return F.addScalar(vec, s);
            }
            pub inline fn subScalar(vec: @This(), s: T) @This() {
                return F.subScalar(vec, s);
            }
            pub inline fn mulScalar(vec: @This(), s: T) @This() {
                return F.mulScalar(vec, s);
            }
            pub inline fn divScalar(vec: @This(), s: T) @This() {
                return F.divScalar(vec, s);
            }
            pub inline fn cross(a: @This(), b: @This()) @This() {
                return F.cross(a, b);
            }
            pub inline fn dot(a: @This(), b: @This()) T {
                return F.dot(a, b);
            }
            pub inline fn eql(a: @This(), b: @This()) bool {
                return F.eql(a, b);
            }
            pub inline fn eqlEps(a: @This(), b: @This()) bool {
                return F.eqlEps(a, b);
            }
        },
    }
}

pub fn VecFunctionsMixin(comptime N: usize, comptime T: type, comptime Base: type) type {
    const V = @Vector(N, T);
    return extern struct {
        pub inline fn v(vec: V) Base {
            return @bitCast(vec);
        }
        pub inline fn vector(vec: Base) V {
            return @bitCast(vec);
        }
        pub inline fn scalar(s: T) Base {
            return @bitCast(@as(V, @splat(s)));
        }
        pub inline fn length(vec: Base) T {
            const v_ = vec.vector();
            return @sqrt(@reduce(.Add, v_ * v_));
        }
        pub inline fn normalized(vec: Base) Base {
            const v_ = vec.vector();
            const one_over_len = 1.0 / @sqrt(@reduce(.Add, v_ * v_));
            return @bitCast(v_ * @as(V, @splat(one_over_len)));
        }
        pub inline fn negate(vec: Base) Base {
            return @bitCast(-vec.vector());
        }
        pub inline fn add(a: Base, b: Base) Base {
            return @bitCast(a.vector() + b.vector());
        }
        pub inline fn sub(a: Base, b: Base) Base {
            return @bitCast(a.vector() - b.vector());
        }
        pub inline fn mul(a: Base, b: Base) Base {
            return @bitCast(a.vector() * b.vector());
        }
        pub inline fn div(a: Base, b: Base) Base {
            return @bitCast(a.vector() / b.vector());
        }
        pub inline fn addScalar(vec: Base, s: T) Base {
            return @bitCast(vec.vector() + @as(V, @splat(s)));
        }
        pub inline fn subScalar(vec: Base, s: T) Base {
            return @bitCast(vec.vector() - @as(V, @splat(s)));
        }
        pub inline fn mulScalar(vec: Base, s: T) Base {
            return @bitCast(vec.vector() * @as(V, @splat(s)));
        }
        pub inline fn divScalar(vec: Base, s: T) Base {
            return @bitCast(vec.vector() / @as(V, @splat(s)));
        }
        pub inline fn cross(a: Base, b: Base) Base {
            if (!(N == 3 or N == 4)) @compileError("Invalid vector length");

            const av = a.vector();
            const bv = b.vector();

            const M = @Vector(N, i32);
            const m1 = switch (N) {
                else => unreachable,
                3 => M{ 1, 2, 0 },
                4 => M{ 1, 2, 0, 3 },
            };
            const m2 = switch (N) {
                else => unreachable,
                3 => M{ 2, 0, 1 },
                4 => M{ 2, 0, 1, 3 },
            };

            const v1 = @shuffle(T, av, undefined, m1);
            const v2 = @shuffle(T, bv, undefined, m2);
            const v3 = @shuffle(T, av, undefined, m2);
            const v4 = @shuffle(T, bv, undefined, m1);

            return @bitCast((v1 * v2) - (v3 * v4));
        }
        pub inline fn dot(a: Base, b: Base) T {
            return @reduce(.Add, a.vector() * b.vector());
        }

        pub inline fn eql(a: Base, b: Base) bool {
            const va = vector(a);
            const vb = vector(b);
            return @reduce(.And, va == vb);
        }

        pub inline fn eqlEps(a: Base, b: Base) bool {
            const va = vector(a);
            const vb = vector(b);
            const abs_diff = @abs(va - vb);
            const eps = epsV(V, va, vb);
            const lte_mask = abs_diff <= eps;
            return @reduce(.And, lte_mask);
        }
    };
}

pub inline fn epsV(comptime V: type, e: V, a: V) V {
    const T = @typeInfo(V).vector.child;

    const abs_eps: V = @splat(std.math.floatEps(T) * 4);
    const e_eps = epsAtV(V, e);
    const a_eps = epsAtV(V, a);

    const max_abs_e = @select(T, abs_eps > e_eps, abs_eps, e_eps);
    return @select(T, max_abs_e > a_eps, max_abs_e, a_eps);
}

pub inline fn epsAtV(comptime V: type, v: V) V {
    const T = @typeInfo(V).vector.child;
    const N = @typeInfo(V).vector.len;
    const U_vec: type = @Vector(N, @Type(.{ .int = .{ .signedness = .unsigned, .bits = @typeInfo(T).float.bits } }));

    const u_vec: U_vec = @bitCast(v);

    const one_vec: U_vec = @splat(1);
    const u_xor_one_vec = u_vec ^ one_vec;

    const y_vec: V = @bitCast(u_xor_one_vec);
    return @abs(v - y_vec);
}

test "eqlEps function" {
    const vec1 = Vec4f32.new(1.0, 2.0, 3.0, 4.0);
    const vec2 = Vec4f32.new(1.0 + 1e-8, 2.0 - 1e-8, 3.0 + 1e-9, 4.0 - 1e-9); // Within typical f32 epsilon
    const vec3 = Vec4f32.new(1.0 + 1e-5, 2.0, 3.0, 4.0); // Larger than typical f32 epsilon

    // Should be approximately equal
    try std.testing.expect(vec1.eqlEps(vec2));

    // Should NOT be approximately equal
    try std.testing.expect(!vec1.eqlEps(vec3));

    // Testing near-zero values
    const zero_vec = Vec4f32.new(0.0, 0.0, 0.0, 0.0);
    const tiny_vec = Vec4f32.new(std.math.floatEps(f32) / 2, 0.0, 0.0, 0.0);
    const not_tiny_vec = Vec4f32.new(std.math.floatEps(f32) * 5, 0.0, 0.0, 0.0);

    try std.testing.expect(zero_vec.eqlEps(tiny_vec));
    try std.testing.expect(!zero_vec.eqlEps(not_tiny_vec));
}
