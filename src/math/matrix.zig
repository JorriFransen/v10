const std = @import("std");

const math = @import("math.zig");

pub const Mat2f32 = Mat(2, 2, f32);
pub const Mat3f32 = Mat(3, 3, f32);
pub const Mat4f32 = Mat(4, 4, f32);

// Matrices are column major
// https://stackoverflow.com/questions/49346732/vulkan-right-handed-coordinate-system-become-left-handed
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
