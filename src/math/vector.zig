pub const Vec2f32 = Vec(2, f32);
pub const Vec3f32 = Vec(3, f32);
pub const Vec4f32 = Vec(4, f32);

pub fn Vec(comptime N: usize, comptime ET: type) type {
    const V = @Vector(N, ET);

    switch (N) {
        else => @compileError("N must be between 2 and 4"),

        2 => return extern struct {
            pub const T = ET;
            x: T,
            y: T,
            pub fn new(x: T, y: T) @This() {
                return @bitCast(V{ x, y });
            }
            pub usingnamespace VecFunctionsMixin(N, T, @This());
        },

        3 => return extern struct {
            pub const T = ET;
            x: T,
            y: T,
            z: T,
            pub fn new(x: T, y: T, z: T) @This() {
                return @bitCast(V{ x, y, z });
            }
            pub usingnamespace VecFunctionsMixin(N, T, @This());
        },

        4 => return extern struct {
            pub const T = ET;
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
        pub inline fn v(vec: V) Base {
            return @bitCast(vec);
        }
        pub inline fn scalar(s: T) Base {
            return @bitCast(@as(V, @splat(s)));
        }
    };
}
