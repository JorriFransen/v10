const std = @import("std");

pub const Vec2f32 = Vec(2, f32);
pub const Vec3f32 = Vec(3, f32);
pub const Vec4f32 = Vec(4, f32);

pub fn Vec(comptime N: usize, comptime ET: type) type {
    switch (N) {
        else => @compileError("N must be between 2 and 4"),

        2 => return extern struct {
            pub const V = @Vector(N, ET);
            pub const T = ET;
            x: T = 0,
            y: T = 0,
            pub fn new(x: T, y: T) @This() {
                return @bitCast(V{ x, y });
            }
            pub usingnamespace VecFunctionsMixin(N, T, @This());
        },

        3 => return extern struct {
            pub const V = @Vector(N, ET);
            pub const T = ET;
            x: T = 0,
            y: T = 0,
            z: T = 0,
            pub fn new(x: T, y: T, z: T) @This() {
                return @bitCast(V{ x, y, z });
            }
            pub usingnamespace VecFunctionsMixin(N, T, @This());
        },

        4 => return extern struct {
            pub const V = @Vector(N, ET);
            pub const T = ET;
            x: T = 0,
            y: T = 0,
            z: T = 0,
            w: T = 0,
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
            const p = vec.vector() * vec.vector();
            return std.math.sqrt(@reduce(.Add, p));
        }
        pub inline fn normalized(vec: Base) Base {
            return vec.div_scalar(vec.length());
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
        pub inline fn mul_scalar(vec: Base, s: T) Base {
            return v(vec.vector() * @as(V, @splat(s)));
        }
        pub inline fn div_scalar(vec: Base, s: T) Base {
            return v(vec.vector() / @as(V, @splat(s)));
        }
        pub inline fn cross(a: Base, b: Base) Base {
            std.debug.assert(N == 3 or N == 4);
            const av = a.vector();
            const bv = b.vector();

            const M = @Vector(N, i32);
            const m1 = if (N == 3) M{ 1, 2, 0 } else M{ 1, 2, 0, 3 };
            const m2 = if (N == 3) M{ 2, 0, 1 } else M{ 2, 0, 1, 3 };

            const v1 = @shuffle(T, av, undefined, m1);
            const v2 = @shuffle(T, bv, undefined, m2);
            const v3 = @shuffle(T, av, undefined, m2);
            const v4 = @shuffle(T, bv, undefined, m1);

            return v((v1 * v2) - (v3 * v4));
        }
        pub inline fn dot(a: Base, b: Base) T {
            return @reduce(.Add, a.mul(b).vector());
        }
    };
}
