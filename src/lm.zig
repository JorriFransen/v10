const std = @import("std");

// Matrices are column major
// https://stackoverflow.com/questions/49346732/vulkan-right-handed-coordinate-system-become-left-handed

pub const FORCE_DEPTH_ZERO_TO_ONE = true;
pub const FLOAT_EPSILON = 0.00001;

pub const degrees = std.math.radiansToDegrees;
pub const radians = std.math.degreesToRadians;

pub const Vec2f32 = Vec(2, f32);
pub const Vec3f32 = Vec(3, f32);
pub const Vec4f32 = Vec(4, f32);
pub const Mat2f32 = Mat(2, 2, f32);
pub const Mat3f32 = Mat(3, 3, f32);
pub const Mat4f32 = Mat(4, 4, f32);

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

pub fn Mat(comptime c: usize, comptime r: usize, comptime T: type) type {
    return extern struct {
        /// data: elements in column-major order
        data: [C * R]T,

        pub const C = c;
        pub const R = r;
        pub const V = @Vector(c * r, T);

        /// e: elements in row-major order
        pub inline fn new(e: V) @This() {
            return (@This(){ .data = e }).transpose();
        }

        pub const identity: @This() = blk: {
            var result = std.mem.zeroes(@This());
            for (0..c) |ci| {
                for (0..r) |ri| {
                    if (ci == ri) {
                        const i = ci + (r * ri);
                        result.data[i] = 1;
                    }
                }
            }
            break :blk result;
        };

        pub inline fn transpose(_m: @This()) @This() {
            std.debug.assert(C == R);
            const D = C;

            const m: V = @bitCast(_m);
            var result: V = undefined;

            inline for (0..D) |ci| {
                inline for (0..D) |ri| {
                    result[ri + (D * ci)] = m[ci + (D * ri)];
                }
            }

            return @bitCast(result);
        }

        pub inline fn mul(_a: @This(), _b: @This()) @This() {
            std.debug.assert(C == R);
            const D = C;

            const a: V = @bitCast(_a);
            const b: V = @bitCast(_b);
            var result: V = undefined;

            inline for (0..D) |i| {
                inline for (0..D) |j| {
                    var sum: f32 = 0;
                    inline for (0..D) |k| {
                        sum += a[i + (D * k)] * b[k + (D * j)];
                    }
                    result[i + (D * j)] = sum;
                }
            }

            return @bitCast(result);
        }
    };
}

test "Matrix2 transpose" {
    const M = Mat(2, 2, f32);

    const expected = M{ .data = .{
        1, 3,
        2, 4,
    } };

    const result = (M{ .data = .{
        1, 2,
        3, 4,
    } }).transpose();

    try expectApproxEqualMatrix(M, expected, result);
}

test "Matrix2 new" {
    const M = Mat(2, 2, f32);

    const expected = M{ .data = .{
        1, 3,
        2, 4,
    } };

    const result = M.new(.{
        1, 2,
        3, 4,
    });

    try expectApproxEqualMatrix(M, expected, result);
}

test "Matrix2 identity" {
    const M = Mat(2, 2, f32);
    const expected = M.new(.{
        1, 0,
        0, 1,
    });

    const result = M.identity;

    try expectApproxEqualMatrix(M, expected, result);
}

test "Matrix2 mul" {
    const M = Mat(2, 2, f32);

    const expected = M.new(.{
        1, -1,
        1, 0,
    });

    const rot = M.new(.{
        0, -1,
        1, 0,
    });

    const shear = M.new(.{
        1, 1,
        0, 1,
    });

    const result = shear.mul(rot);
    try expectApproxEqualMatrix(M, expected, result);
}

fn expectApproxEqualMatrix(M: type, expected: M, actual: M) !void {
    const ve: M.V = @bitCast(expected);
    const va: M.V = @bitCast(actual);

    var match = true;
    var diff_index: usize = 0;

    const diff = ve - va;
    for (0..@typeInfo(M.V).vector.len) |i| {
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

    var differ = MatrixDiffer(M){
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

fn MatrixDiffer(M: type) type {
    return struct {
        expected: M,
        actual: M,
        ttyconf: std.io.tty.Config,

        pub fn write(self: @This(), writer: anytype) !void {
            try writer.print("\n", .{});
            for (self.expected.data, 0..) |evalue, i| {
                const end = i % M.C;
                const start = end == 0;
                if (start) try writer.print("[ ", .{});

                const avalue = self.actual.data[i];
                const diff = @abs(evalue - avalue) >= FLOAT_EPSILON;

                if (diff) try self.ttyconf.setColor(writer, .red);
                try writer.print("{d: >14.6}", .{evalue});
                if (diff) try self.ttyconf.setColor(writer, .reset);

                if (end == M.C - 1) {
                    try writer.print(" ]\n", .{});
                } else {
                    try writer.print(", ", .{});
                }
            }
            try writer.print("\n", .{});
        }
    };
}

fn testprint(comptime fmt: []const u8, args: anytype) void {
    if (@inComptime()) {
        @compileError(std.fmt.comptimePrint(fmt, args));
    } else if (std.testing.backend_can_print) {
        std.debug.print(fmt, args);
    }
}
