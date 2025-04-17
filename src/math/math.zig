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
