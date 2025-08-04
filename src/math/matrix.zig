const std = @import("std");

const math = @import("../math.zig");

pub const Mat2f32 = Mat(2, 2, f32);
pub const Mat3f32 = Mat(3, 3, f32);
pub const Mat4f32 = Mat(4, 4, f32);
const Vec = math.Vec;
const Vec3 = math.Vec3;

// Matrices are column major
// https://stackoverflow.com/questions/49346732/vulkan-right-handed-coordinate-system-become-left-handed
pub fn Mat(comptime cols: usize, comptime rows: usize, comptime Type: type) type {
    return extern struct {
        /// data: elements in column-major order
        data: [C * R]Type,

        pub const C = cols;
        pub const R = rows;
        pub const T = Type;
        pub const V = @Vector(C * R, T);

        /// e: elements in row-major order
        pub inline fn new(e: V) @This() {
            return (@This(){ .data = e }).transpose();
        }

        pub const identity: @This() = blk: {
            var result = std.mem.zeroes(@This());
            for (0..C) |ci| {
                for (0..R) |ri| {
                    if (ci == ri) {
                        const i = ci + (R * ri);
                        result.data[i] = 1;
                    }
                }
            }
            break :blk result;
        };

        pub inline fn col(_m: @This(), n: usize) math.Vec(R, T) {
            std.debug.assert(n < C);

            const m: V = @bitCast(_m);
            const a: [C * R]T = m;
            const offset = n * R;
            const v: math.Vec(R, T).V = @bitCast(a[offset .. offset + C].*);
            return @bitCast(v);
        }

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

        pub inline fn mul_vec(m: @This(), v_: Vec(C, Type)) Vec(R, Type) {
            const matrix_data: V = @bitCast(m);

            const v = v_.vector();
            var rv: @TypeOf(v) = undefined;

            inline for (0..R) |i| {
                var sum: T = 0;

                inline for (0..C) |j| {
                    sum += matrix_data[i + j * R] * v[j];
                }
                rv[i] = sum;
            }

            return @bitCast(rv);
        }

        pub inline fn translate(this: @This(), t: Vec3) @This() {
            comptime std.debug.assert(C == 4 and R == 4);

            var res = this;

            res.data[12] += res.data[0] * t.x + res.data[4] * t.y + res.data[8] * t.z;
            res.data[13] += res.data[1] * t.x + res.data[5] * t.y + res.data[9] * t.z;
            res.data[14] += res.data[2] * t.x + res.data[6] * t.y + res.data[10] * t.z;

            return res;
        }

        pub inline fn translation(t: Vec3) @This() {
            comptime std.debug.assert(C == 4 and R == 4);

            return .{ .data = .{
                1,   0,   0,   0,
                0,   1,   0,   0,
                0,   0,   1,   0,
                t.x, t.y, t.z, 1,
            } };
        }

        pub inline fn rotate(mat: @This(), angle: Vec3.T, axis: Vec3) @This() {
            comptime std.debug.assert(C == 4 and R == 4);
            comptime std.debug.assert(Vec3.T == T);

            const c = @cos(angle);
            const s = @sin(angle);

            const axis_n = axis.normalized();
            const temp = axis_n.mul_scalar(1 - c);

            const rot_c0 = Vec3.new(
                c + temp.x * axis_n.x,
                temp.x * axis_n.y + s * axis_n.z,
                temp.x * axis_n.z - s * axis_n.y,
            );

            const rot_c1 = Vec3.new(
                temp.y * axis_n.x - s * axis_n.z,
                c + temp.y * axis_n.y,
                temp.y * axis_n.z + s * axis_n.x,
            );

            const rot_c2 = Vec3.new(
                temp.z * axis_n.x + s * axis_n.y,
                temp.z * axis_n.y - s * axis_n.x,
                c + temp.z * axis_n.z,
            );

            const c0 = mat.col(0);
            const c1 = mat.col(1);
            const c2 = mat.col(2);

            const res_c0 = c0.mul_scalar(rot_c0.x).add(c1.mul_scalar(rot_c0.y)).add(c2.mul_scalar(rot_c0.z));
            const res_c1 = c0.mul_scalar(rot_c1.x).add(c1.mul_scalar(rot_c1.y)).add(c2.mul_scalar(rot_c1.z));
            const res_c2 = c0.mul_scalar(rot_c2.x).add(c1.mul_scalar(rot_c2.y)).add(c2.mul_scalar(rot_c2.z));
            const res_c3 = mat.col(3);

            return @This(){ .data = .{
                res_c0.x, res_c0.y, res_c0.z, res_c0.w,
                res_c1.x, res_c1.y, res_c1.z, res_c1.w,
                res_c2.x, res_c2.y, res_c2.z, res_c2.w,
                res_c3.x, res_c3.y, res_c3.z, res_c3.w,
            } };
        }

        pub inline fn rotation(angle: Vec3.T, axis: Vec3) @This() {
            comptime std.debug.assert(C == 4 and R == 4);
            comptime std.debug.assert(Vec3.T == T);
            return identity.rotate(angle, axis);
        }

        pub inline fn scale(mat: @This(), scalev: Vec3) @This() {
            comptime std.debug.assert(C == 4 and R == 4);
            comptime std.debug.assert(Vec3.T == T);

            var r = mat;

            r.data[0] *= scalev.x;
            r.data[1] *= scalev.x;
            r.data[2] *= scalev.x;

            r.data[4] *= scalev.y;
            r.data[5] *= scalev.y;
            r.data[6] *= scalev.y;

            r.data[8] *= scalev.z;
            r.data[9] *= scalev.z;
            r.data[10] *= scalev.z;

            return r;
        }

        pub inline fn scaling(scalev: Vec3) @This() {
            comptime std.debug.assert(C == 4 and R == 4);
            comptime std.debug.assert(Vec3.T == T);

            return .{ .data = .{
                scalev.x, 0,        0,        0,
                0,        scalev.y, 0,        0,
                0,        0,        scalev.z, 0,
                0,        0,        0,        1,
            } };
        }

        pub inline fn transform(translation_v: Vec3, scale_v: Vec3, rotation_v: Vec3) @This() {
            comptime std.debug.assert(C == 4 and R == 4);

            // pub fn mat4Slow(this: @This()) Mat4 {
            //     var transform = Mat4.translation_v(translation_v);
            //
            //     transform = transform.rotate(rotation_v.y, Vec3.new(0, 1, 0));
            //     transform = transform.rotate(rotation_v.x, Vec3.new(1, 0, 0));
            //     transform = transform.rotate(rotation_v.z, Vec3.new(0, 0, 1));
            //
            //     return transform.scale(scale_v);
            // }

            const c3 = @cos(rotation_v.z);
            const s3 = @sin(rotation_v.z);
            const c2 = @cos(rotation_v.x);
            const s2 = @sin(rotation_v.x);
            const c1 = @cos(rotation_v.y);
            const s1 = @sin(rotation_v.y);

            return .{ .data = .{
                scale_v.x * (c1 * c3 + s1 * s2 * s3),
                scale_v.x * (c2 * s3),
                scale_v.x * (c1 * s2 * s3 - c3 * s1),
                0,

                scale_v.y * (c3 * s1 * s2 - c1 * s3),
                scale_v.y * (c2 * c3),
                scale_v.y * (c1 * c3 * s2 + s1 * s3),
                0,

                scale_v.z * (c2 * s1),
                scale_v.z * (-s2),
                scale_v.z * (c1 * c2),
                0,

                translation_v.x,
                translation_v.y,
                translation_v.z,
                1,
            } };
        }

        pub inline fn ortho(l: T, r: T, t: T, b: T, n: T, f: T) @This() {
            comptime std.debug.assert(C == 4 and R == 4);

            return .{ .data = .{
                2 / (r - l),        0,                  0,            0,
                0,                  2 / (b - t),        0,            0,
                0,                  0,                  1 / (f - n),  0,
                -(r + l) / (r - l), -(b + t) / (b - t), -n / (f - n), 1,
            } };
        }

        pub inline fn perspective(fov_y: T, aspect: T, near: T, far: T) @This() {
            comptime std.debug.assert(C == 4 and R == 4);
            std.debug.assert(@abs(aspect - (std.math.floatEps(T) * 4)) > 0.0);

            var a_nom = aspect;
            var a_denom: T = 1;
            if (aspect < 1) {
                a_nom = 1;
                a_denom = 1 / aspect;
            }

            const tan_half_fov_y = @tan(fov_y / 2);

            return .{ .data = .{
                1 / (a_nom * tan_half_fov_y), 0,                               0,                            0,
                0,                            -1 / (a_denom * tan_half_fov_y), 0,                            0,
                0,                            0,                               far / (far - near),           1,
                0,                            0,                               -(far * near) / (far - near), 0,
            } };
        }

        pub const UpDirection = extern struct { x: T = 0, y: T = -1, z: T = 0 };

        pub inline fn lookInDirection(pos: Vec3, direction: Vec3, up_: UpDirection) @This() {
            comptime std.debug.assert(C == 4 and R == 4);

            const up: Vec3 = @bitCast(up_);
            const w = direction.normalized();
            const u = w.cross(up).normalized();
            const v = w.cross(u);

            return .{ .data = .{
                u.x,         v.x,         w.x,         0,
                u.y,         v.y,         w.y,         0,
                u.z,         v.z,         w.z,         0,
                -u.dot(pos), -v.dot(pos), -w.dot(pos), 1,
            } };
        }

        pub inline fn lookAtPosition(pos: Vec3, target: Vec3, up_: UpDirection) @This() {
            comptime std.debug.assert(C == 4 and R == 4);

            const direction = target.sub(pos);

            const up: Vec3 = @bitCast(up_);
            const w = direction.normalized();
            const u = w.cross(up).normalized();
            const v = w.cross(u);

            return .{ .data = .{
                u.x,         v.x,         w.x,         0,
                u.y,         v.y,         w.y,         0,
                u.z,         v.z,         w.z,         0,
                -u.dot(pos), -v.dot(pos), -w.dot(pos), 1,
            } };
        }

        pub inline fn lookXYZEuler(pos: Vec3, euler_angles: Vec3) @This() {
            const c3 = @cos(euler_angles.z);
            const s3 = @sin(euler_angles.z);
            const c2 = @cos(euler_angles.x);
            const s2 = @sin(euler_angles.x);
            const c1 = @cos(euler_angles.y);
            const s1 = @sin(euler_angles.y);

            const u = Vec3.new(
                c1 * c3 + s1 * s2 * s3,
                c2 * s3,
                c1 * s2 * s3 - c3 * s1,
            );
            const v = Vec3.new(
                c3 * s1 * s2 - c1 * s3,
                c2 * c3,
                c1 * c3 * s2 + s1 * s3,
            );
            const w = Vec3.new(
                c2 * s1,
                -s2,
                c1 * c2,
            );

            return .{ .data = .{
                u.x,         v.x,         w.x,         0,
                u.y,         v.y,         w.y,         0,
                u.z,         v.z,         w.z,         0,
                -u.dot(pos), -v.dot(pos), -w.dot(pos), 1,
            } };
        }

        pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            for (0..R) |rr| {
                try writer.print("{{ ", .{});
                for (0..C) |cc| {
                    try writer.print("{}", .{value.data[cc * C + rr]});
                    if (cc < C - 1) try writer.print(", ", .{});
                }
                try writer.print(" }}", .{});
                if (rr < R - 1) try writer.print("\n", .{});
            }
        }
    };
}

pub inline fn padMat3f32(mat: Mat3f32) [3]math.Vec4 {
    return .{
        math.Vec4.new(mat.data[0], mat.data[1], mat.data[2], 0),
        math.Vec4.new(mat.data[3], mat.data[4], mat.data[5], 0),
        math.Vec4.new(mat.data[6], mat.data[7], mat.data[8], 0),
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

test "Matrix3 transpose" {
    const M = Mat(3, 3, f32);

    const expected = M{ .data = .{
        1, 4, 7,
        2, 5, 8,
        3, 6, 9,
    } };

    const result = (M{ .data = .{
        1, 2, 3,
        4, 5, 6,
        7, 8, 9,
    } }).transpose();

    try expectApproxEqualMatrix(M, expected, result);
}

test "Matrix3 new" {
    const M = Mat(3, 3, f32);

    const expected = M{ .data = .{
        1, 4, 7,
        2, 5, 8,
        3, 6, 9,
    } };

    const result = M.new(.{
        1, 2, 3,
        4, 5, 6,
        7, 8, 9,
    });

    try expectApproxEqualMatrix(M, expected, result);
}

test "Matrix3 identity" {
    const M = Mat(3, 3, f32);
    const expected = M.new(.{
        1, 0, 0,
        0, 1, 0,
        0, 0, 1,
    });

    const result = M.identity;

    try expectApproxEqualMatrix(M, expected, result);
}

test "Matrix3 mul" {
    const M = Mat(3, 3, f32);

    const expected = M.new(.{
        14, 32,  50,
        32, 77,  122,
        50, 122, 194,
    });

    const a = M.new(.{
        1, 2, 3,
        4, 5, 6,
        7, 8, 9,
    });

    const b = M.new(.{
        1, 4, 7,
        2, 5, 8,
        3, 6, 9,
    });

    const result = a.mul(b);
    try expectApproxEqualMatrix(M, expected, result);
}

test "Matrix4 transpose" {
    const M = Mat(4, 4, f32);

    const expected = M{ .data = .{
        1, 5, 9,  13,
        2, 6, 10, 14,
        3, 7, 11, 15,
        4, 8, 12, 16,
    } };

    const result = (M{ .data = .{
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 14, 15, 16,
    } }).transpose();

    try expectApproxEqualMatrix(M, expected, result);
}

test "Matrix4 new" {
    const M = Mat(4, 4, f32);

    const expected = M{ .data = .{
        1, 5, 9,  13,
        2, 6, 10, 14,
        3, 7, 11, 15,
        4, 8, 12, 16,
    } };

    const result = M.new(.{
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 14, 15, 16,
    });

    try expectApproxEqualMatrix(M, expected, result);
}

test "Matrix4 identity" {
    const M = Mat(4, 4, f32);
    const expected = M.new(.{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    });

    const result = M.identity;

    try expectApproxEqualMatrix(M, expected, result);
}

test "Matrix4 mul" {
    const M = Mat(4, 4, f32);

    const expected = M.new(.{
        30,  70,  110, 150,
        70,  174, 278, 382,
        110, 278, 446, 614,
        150, 382, 614, 846,
    });

    const a = M.new(.{
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 14, 15, 16,
    });

    const b = M.new(.{
        1, 5, 9,  13,
        2, 6, 10, 14,
        3, 7, 11, 15,
        4, 8, 12, 16,
    });

    const result = a.mul(b);
    try expectApproxEqualMatrix(M, expected, result);
}

fn expectApproxEqualMatrix(M: type, expected: M, actual: M) !void {
    const ve: M.V = @bitCast(expected);
    const va: M.V = @bitCast(actual);

    var match = true;
    var diff_index: usize = 0;

    const diff = ve - va;
    const eps = math.vector.epsV(M.V, ve, va);

    for (0..@typeInfo(M.V).vector.len) |i| {
        if (@abs(diff[i]) >= eps[i]) {
            match = false;
            diff_index = i;
            break;
        }
    }

    if (match) return;

    testprint("matrices differ. first difference occurs at index {d}\n", .{diff_index});

    const stderr = std.fs.File.stderr();
    var differ = MatrixDiffer(M).init(expected, actual, stderr);

    testprint("\n============ expected this output: ============= \n", .{});
    differ.write() catch {};

    differ.expected = actual;
    differ.actual = expected;

    testprint("\n============= instead found this: ============== \n", .{});
    differ.write() catch {};

    return error.TestExpectedApproxEqAbs;
}

fn MatrixDiffer(M: type) type {
    return struct {
        expected: M,
        actual: M,
        ttyconf: std.io.tty.Config,
        writer: std.fs.File.DeprecatedWriter,

        pub fn init(expected: M, actual: M, out: std.fs.File) @This() {
            return .{
                .expected = expected,
                .actual = actual,
                .ttyconf = std.io.tty.detectConfig(out),
                .writer = out.deprecatedWriter(),
            };
        }

        pub fn write(self: @This()) !void {
            var awriter = self.writer.adaptToNewApi();
            var writer = &awriter.derp_writer;
            try writer.print("\n", .{});
            for (self.expected.data, 0..) |evalue, i| {
                const end = i % M.C;
                const start = end == 0;
                if (start) try writer.print("[ ", .{});

                const avalue = self.actual.data[i];

                const diff = @abs(evalue - avalue) >= math.epsWith(M.T, evalue, avalue);

                if (diff) try self.ttyconf.setColor(&awriter.new_interface, .red);
                try writer.print("{d: >14.6}", .{evalue});
                if (diff) try self.ttyconf.setColor(&awriter.new_interface, .reset);

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
