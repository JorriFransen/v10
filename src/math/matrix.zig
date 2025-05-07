const std = @import("std");

const math = @import("math.zig");

pub const Mat2f32 = Mat(2, 2, f32);
pub const Mat3f32 = Mat(3, 3, f32);
pub const Mat4f32 = Mat(4, 4, f32);
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
            comptime std.debug.assert(Vec3.T == @This().T);

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
            comptime std.debug.assert(Vec3.T == @This().T);
            return identity.rotate(angle, axis);
        }

        pub inline fn scale(mat: @This(), scalev: Vec3) @This() {
            comptime std.debug.assert(C == 4 and R == 4);
            comptime std.debug.assert(Vec3.T == @This().T);

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
            comptime std.debug.assert(Vec3.T == @This().T);

            return .{ .data = .{
                scalev.x, 0,        0,        0,
                0,        scalev.y, 0,        0,
                0,        0,        scalev.z, 0,
                0,        0,        0,        1,
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
