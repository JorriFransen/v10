const std = @import("std");

pub const FORCE_DEPTH_ZERO_TO_ONE = true;

pub const FLOAT_EPSILON = 0.00001;

pub const degrees = std.math.radiansToDegrees;
pub const radians = std.math.degreesToRadians;

pub const Vec2f32 = Vec(2, f32);
pub const Vec3f32 = Vec(3, f32);
pub const Vec4f32 = Vec(4, f32);
pub const Mat4f32 = Mat(4, 4, f32);

pub fn Vec(comptime N: usize, comptime T: type) type {
    if (N == 0 or N > 4) @compileError("N must be between 2 and 4");

    switch (N) {
        else => unreachable,

        2 => return extern struct {
            x: T,
            y: T,
            pub fn new(x: T, y: T) @This() {
                return .{ .x = x, .y = y };
            }
            pub usingnamespace VecFunctionsMixin(N, T, @This());
        },
        3 => return extern struct {
            x: T,
            y: T,
            z: T,
            pub fn new(x: T, y: T, z: T) @This() {
                return .{ .x = x, .y = y, .z = z };
            }
            pub usingnamespace VecFunctionsMixin(N, T, @This());
        },
        4 => return extern struct {
            x: T,
            y: T,
            z: T,
            w: T,
            pub fn new(x: T, y: T, z: T, w: T) @This() {
                return .{ .x = x, .y = y, .z = z, .w = w };
            }
            pub usingnamespace VecFunctionsMixin(N, T, @This());
        },
    }
}

pub fn VecFunctionsMixin(comptime N: usize, comptime T: type, comptime Base: type) type {
    const V = @Vector(N, T);
    return extern struct {
        pub inline fn vector(v: V) Base {
            return @bitCast(v);
        }
        pub inline fn scalar(v: T) Base {
            return @bitCast(@as(V, @splat(v)));
        }
        pub inline fn toVector(this: Base) V {
            return @bitCast(this);
        }
        pub inline fn add(a: Base, b: Base) Base {
            return vector(a.toVector() + b.toVector());
        }
        pub inline fn sub(a: Base, b: Base) Base {
            return vector(a.toVector() - b.toVector());
        }
        pub inline fn mul(a: Base, b: Base) Base {
            return vector(a.toVector() * b.toVector());
        }
        pub inline fn div(a: Base, b: Base) Base {
            return vector(a.toVector() / b.toVector());
        }
        pub inline fn div_scalar(v: Base, s: T) Base {
            return vector(v.toVector() / @as(V, @splat(s)));
        }
        pub inline fn length(v: Base) T {
            const p = v.toVector() * v.toVector();
            return std.math.sqrt(@reduce(.Add, p));
        }
        pub inline fn normalized(v: Base) Base {
            return v.div_scalar(v.length());
        }
        pub inline fn dot(a: Base, b: Base) T {
            return @reduce(.Add, a.mul(b).toVector());
        }
        pub inline fn cross(a: Base, b: Base) Base {
            comptime if (N == 2) @compileError("Cannot apply cross product to Vector2");

            const av = a.toVector();
            const bv = b.toVector();

            const M = @Vector(N, i32);
            const m1 = if (N == 3) M{ 1, 2, 0 } else M{ 1, 2, 0, 3 };
            const m2 = if (N == 3) M{ 2, 0, 1 } else M{ 2, 0, 1, 3 };

            const v1 = @shuffle(T, av, undefined, m1);
            const v2 = @shuffle(T, bv, undefined, m2);
            const v3 = @shuffle(T, av, undefined, m2);
            const v4 = @shuffle(T, bv, undefined, m1);

            return vector((v1 * v2) - (v3 * v4));
        }
    };
}

pub fn Mat(comptime c: usize, comptime r: usize, comptime T: type) type {
    return extern struct {
        data: [C * R]T,

        pub const C = c;
        pub const R = r;

        pub const identity: @This() = blk: {
            var result: @This() = undefined;
            for (0..c) |ci| {
                for (0..r) |ri| {
                    const i = ci + (r * ri);
                    result.data[i] = if (ci == ri) 1 else 0;
                }
            }
            break :blk result;
        };

        const Base = @This();
        pub usingnamespace MatFunctionsMixin(C, R, T, Base);
    };
}

pub fn MatFunctionsMixin(comptime C: usize, comptime R: usize, comptime T: type, comptime Base: type) type {
    if (!(C == 4 and R == 4)) {
        @compileError("TODO: unhandled matrix dimension");
    }

    return extern struct {
        pub fn new(m0: T, m1: T, m2: T, m3: T, m4: T, m5: T, m6: T, m7: T, m8: T, m9: T, m10: T, m11: T, m12: T, m13: T, m14: T, m15: T) Base {
            return .{ .data = .{
                m0,  m1,  m2,  m3,
                m4,  m5,  m6,  m7,
                m8,  m9,  m10, m11,
                m12, m13, m14, m15,
            } };
        }

        pub fn rotation_z(r: T) Base {
            return .{ .data = .{
                @cos(r),  @sin(r), 0, 0,
                -@sin(r), @cos(r), 0, 0,
                0,        0,       1, 0,
                0,        0,       0, 1,
            } };
        }

        pub fn translation(x: T, y: T, z: T) Base {
            return .{ .data = .{
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                x, y, z, 1,
            } };
        }

        pub fn scaling(x: T, y: T, z: T) Base {
            return .{ .data = .{
                x, 0, 0, 0,
                0, y, 0, 0,
                0, 0, z, 0,
                0, 0, 0, 1,
            } };
        }

        pub fn perspective(fovy: T, a: T, n: T, f: T) Base {
            const s = 1 / @tan(fovy * 0.5);

            if (FORCE_DEPTH_ZERO_TO_ONE) {
                return .{ .data = .{
                    s / a, 0, 0,                  0,
                    0,     s, 0,                  0,
                    0,     0, f / (n - f),        -1,
                    0,     0, -(f * n) / (f - n), 0,
                } };
            } else {
                return .{ .data = .{
                    s / a, 0, 0,                   0,
                    0,     s, 0,                   0,
                    0,     0, (n + f) / (n - f),   -1,
                    0,     0, 2 * f * n / (n - f), 0,
                } };
            }
        }

        pub fn ortho(l: T, r: T, b: T, t: T, n: T, f: T) Base {
            if (FORCE_DEPTH_ZERO_TO_ONE) {
                return .{ .data = .{
                    2 / (r - l),        0,                  0,            0,
                    0,                  2 / (t - b),        0,            0,
                    0,                  0,                  -1 / (f - n), 0,
                    -(r + l) / (r - l), -(t + b) / (t - b), -n / (f - n), 1,
                } };
            } else {
                return .{ .data = .{
                    2 / (r - l),        0,                  0,                  0,
                    0,                  2 / (t - b),        0,                  0,
                    0,                  0,                  -2 / (f - n),       0,
                    -(r + l) / (r - l), -(t + b) / (t - b), -(f + n) / (f - n), 1,
                } };
            }
        }

        pub fn lookAt(eye: Vec3f32, to: Vec3f32, up: Vec3f32) Base {
            const f = to.sub(eye).normalized();
            const l = f.cross(up).normalized();
            const u = l.cross(f);

            return .{ .data = .{
                l.x,         u.x,         -f.x,       0,
                l.y,         u.y,         -f.y,       0,
                l.z,         u.z,         -f.z,       0,
                -l.dot(eye), -u.dot(eye), f.dot(eye), 1,
            } };
        }

        pub fn transposed(m: *const Base) Base {
            return .{ .data = .{
                m.a[0], m.a[4], m.a[8],  m.a[12],
                m.a[1], m.a[5], m.a[9],  m.a[13],
                m.a[2], m.a[6], m.a[10], m.a[14],
                m.a[3], m.a[7], m.a[11], m.a[15],
            } };
        }

        pub fn mul(a: *const Base, b: Base) Base {
            const ad = &a.data;
            const bd = &b.data;

            return .{ .data = .{
                ad[0] * bd[0] + ad[1] * bd[4] + ad[2] * bd[8] + ad[3] * bd[12],
                ad[0] * bd[1] + ad[1] * bd[5] + ad[2] * bd[9] + ad[3] * bd[13],
                ad[0] * bd[2] + ad[1] * bd[6] + ad[2] * bd[10] + ad[3] * bd[14],
                ad[0] * bd[3] + ad[1] * bd[7] + ad[2] * bd[11] + ad[3] * bd[15],

                ad[4] * bd[0] + ad[5] * bd[4] + ad[6] * bd[8] + ad[7] * bd[12],
                ad[4] * bd[1] + ad[5] * bd[5] + ad[6] * bd[9] + ad[7] * bd[13],
                ad[4] * bd[2] + ad[5] * bd[6] + ad[6] * bd[10] + ad[7] * bd[14],
                ad[4] * bd[3] + ad[5] * bd[7] + ad[6] * bd[11] + ad[7] * bd[15],

                ad[8] * bd[0] + ad[9] * bd[4] + ad[10] * bd[8] + ad[11] * bd[12],
                ad[8] * bd[1] + ad[9] * bd[5] + ad[10] * bd[9] + ad[11] * bd[13],
                ad[8] * bd[2] + ad[9] * bd[6] + ad[10] * bd[10] + ad[11] * bd[14],
                ad[8] * bd[3] + ad[9] * bd[7] + ad[10] * bd[11] + ad[11] * bd[15],

                ad[12] * bd[0] + ad[13] * bd[4] + ad[14] * bd[8] + ad[15] * bd[12],
                ad[12] * bd[1] + ad[13] * bd[5] + ad[14] * bd[9] + ad[15] * bd[13],
                ad[12] * bd[2] + ad[13] * bd[6] + ad[14] * bd[10] + ad[15] * bd[14],
                ad[12] * bd[3] + ad[13] * bd[7] + ad[14] * bd[11] + ad[15] * bd[15],
            } };
        }
    };
}

test "Vec3 cross" {
    const a = Vec3f32.new(1, 2, 3);
    const b = Vec3f32.new(2, 3, 4);

    const expected_ab = Vec3f32.new(-1, 2, -1);
    const expected_ba = Vec3f32.new(1, -2, 1);

    const result_ab = a.cross(b);
    const result_ba = b.cross(a);

    try std.testing.expectEqual(expected_ab, result_ab);
    try std.testing.expectEqual(expected_ba, result_ba);
}

test "Mat4 mul" {
    const a = Mat4f32.new(1, 2, 3, 4, 5, 6, 7, 8, 9, 8, 7, 6, 5, 4, 3, 2);

    const b = Mat4f32{ .data = .{
        -2, 1, 2, 3,
        3,  2, 1, -1,
        4,  3, 6, 5,
        1,  2, 7, 8,
    } };

    const expected = Mat4f32{ .data = .{
        20, 22, 50,  48,
        44, 54, 114, 108,
        40, 58, 110, 102,
        16, 26, 46,  42,
    } };

    const result = a.mul(b);

    try std.testing.expectEqual(expected.data, result.data);
}

test "Mat4 look_at default" {
    const eye = Vec3f32.new(0, 0, 0);
    const to = Vec3f32.new(0, 0, -1);
    const up = Vec3f32.new(0, 1, 0);

    const tf = Mat4f32.lookAt(eye, to, up);

    try std.testing.expectEqual(Mat4f32.identity.data, tf.data);
}

test "Mat4 look_at positive z" {
    const eye = Vec3f32.new(0, 0, 0);
    const to = Vec3f32.new(0, 0, 1);
    const up = Vec3f32.new(0, 1, 0);

    const tf = Mat4f32.lookAt(eye, to, up);

    try std.testing.expectEqual(Mat4f32.scaling(-1, 1, -1).data, tf.data);
}

test "Mat4 look_at moves world" {
    const eye = Vec3f32.new(0, 0, 8);
    const to = Vec3f32.new(0, 0, 0);
    const up = Vec3f32.new(0, 1, 0);

    const tf = Mat4f32.lookAt(eye, to, up);

    try std.testing.expectEqual(Mat4f32.translation(0, 0, -8).data, tf.data);
}

test "Mat4 look_at arbitrary" {
    const eye = Vec3f32.new(1, 3, 2);
    const to = Vec3f32.new(4, -2, 8);
    const up = Vec3f32.new(1, 1, 0);

    const tf = Mat4f32.lookAt(eye, to, up);

    const expected = Mat4f32{ .data = .{
        -0.51449, 0.77892,  -0.35856, 0.00000,
        0.51449,  0.61494,  0.59761,  0.00000,
        0.68599,  0.12298,  -0.71713, 0.00000,
        2.40098,  -2.86972, -0.00000, 1.00000,
    } };

    try expectApproxEqualMatrix(expected, tf);
}

fn expectApproxEqualMatrix(expected: Mat4f32, actual: Mat4f32) !void {
    const V = @Vector(4 * 4, f32);

    const ve: V = @bitCast(expected);
    const va: V = @bitCast(actual);

    var match = true;
    var diff_index: usize = 0;

    const diff = ve - va;
    for (0..@typeInfo(V).vector.len) |i| {
        if (@abs(diff[i]) >= FLOAT_EPSILON) {
            match = false;
            diff_index = i;
            break;
        }
    }

    if (match) return;

    testprint("matrices differ. first difference occurs at index {d}\n", .{diff_index});

    const stderr = std.io.getStdErr();
    const ttyconf = std.io.tty.detectConfig(stderr);

    var differ = MatrixDiffer{
        .expected = expected,
        .actual = actual,
        .ttyconf = ttyconf,
    };

    testprint("\n============ expected this output: ============= \n", .{});
    differ.write(stderr.writer()) catch {};

    differ.expected = actual;
    differ.actual = expected;

    testprint("\n============= instead found this: ============== \n", .{});
    differ.write(stderr.writer()) catch {};

    return error.TestExpectedApproxEqAbs;
}

const MatrixDiffer = struct {
    expected: Mat4f32,
    actual: Mat4f32,
    ttyconf: std.io.tty.Config,

    pub fn write(self: MatrixDiffer, writer: anytype) !void {
        try writer.print("\n", .{});
        for (self.expected.data, 0..) |evalue, i| {
            const end = i % Mat4f32.C;
            const start = end == 0;
            if (start) try writer.print("[ ", .{});

            const avalue = self.actual.data[i];
            const diff = @abs(evalue - avalue) >= FLOAT_EPSILON;

            if (diff) try self.ttyconf.setColor(writer, .red);
            try writer.print("{d: >14.6}", .{evalue});
            if (diff) try self.ttyconf.setColor(writer, .reset);

            if (end == Mat4f32.C - 1) {
                try writer.print(" ]\n", .{});
            } else {
                try writer.print(", ", .{});
            }
        }
        try writer.print("\n", .{});
    }
};

fn testprint(comptime fmt: []const u8, args: anytype) void {
    if (@inComptime()) {
        @compileError(std.fmt.comptimePrint(fmt, args));
    } else if (std.testing.backend_can_print) {
        std.debug.print(fmt, args);
    }
}
