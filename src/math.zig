const std = @import("std");

pub const pi = std.math.pi;
pub const tau = std.math.tau;

pub const maxInt = std.math.maxInt;
pub const minInt = std.math.minInt;
pub const atan2 = std.math.atan2;
pub const log2 = std.math.log2;
pub const isPowerOfTwo = std.math.isPowerOfTwo;
pub const shl = std.math.shl;
pub const shr = std.math.shr;

pub const Log2Int = std.math.Log2Int;

pub inline fn square(x: f32) f32 {
    return x * x;
}

pub inline fn sqrt(x: f32) f32 {
    return @sqrt(x);
}

pub inline fn divCeil(numerator: anytype, denominator: @TypeOf(numerator)) @TypeOf(numerator) {
    const T = @TypeOf(numerator);
    comptime {
        const t_info = @typeInfo(T);
        switch (t_info) {
            .comptime_float, .float, .comptime_int, .int => {},
            else => {
                @compileError("Unsupported type for divCeil");
            },
        }
    }

    return std.math.divCeil(T, numerator, denominator) catch unreachable;
}

pub const V2 = extern struct {
    x: f32 = 0,
    y: f32 = 0,

    pub const zero = scalar(0);
    pub const one = scalar(1);

    pub const V = @Vector(2, f32);

    pub inline fn init(x: f32, y: f32) V2 {
        return .{ .x = x, .y = y };
    }

    pub inline fn initSigned(x: i32, y: i32) V2 {
        const result: V2 = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
        return result;
    }

    pub inline fn initUnsigned(x: u32, y: u32) V2 {
        const result: V2 = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
        return result;
    }

    pub inline fn scalar(s: f32) V2 {
        const result: V2 = @bitCast(@as(V, @splat(s)));
        return result;
    }

    pub inline fn v(this: V2) V {
        const result: V = @bitCast(this);
        return result;
    }

    pub inline fn add(a: V2, b: V2) V2 {
        const result: V2 = @bitCast(a.v() + b.v());
        return result;
    }

    pub inline fn addAll(vecs: []const V2) V2 {
        var result: V = std.mem.zeroes(V);
        for (vecs) |vec| result += vec.v();
        return @bitCast(result);
    }

    pub inline fn sub(a: V2, b: V2) V2 {
        const result: V2 = @bitCast(a.v() - b.v());
        return result;
    }

    pub inline fn neg(this: V2) V2 {
        const result: V2 = @bitCast(-this.v());
        return result;
    }

    pub inline fn mul(this: V2, s: f32) V2 {
        const result: V2 = @bitCast(this.v() * @as(V, @splat(s)));
        return result;
    }

    pub inline fn div(this: V2, s: f32) V2 {
        const result: V2 = @bitCast(this.v() / @as(V, @splat(s)));
        return result;
    }

    pub inline fn inner(a: V2, b: V2) f32 {
        const result: f32 = @reduce(.Add, a.v() * b.v());
        return result;
    }

    pub inline fn length(this: V2) f32 {
        const result: f32 = sqrt(this.lengthSquared());
        return result;
    }

    pub inline fn lengthSquared(this: V2) f32 {
        const result: f32 = this.inner(this);
        return result;
    }

    pub fn format(this: V2, writer: anytype) !void {
        try writer.print("[{}, {}]", .{ this.x, this.y });
    }
};

pub const V3 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub const zero = scalar(0);
    pub const one = scalar(1);

    pub const V = @Vector(3, f32);

    pub inline fn init(x: f32, y: f32, z: f32) V3 {
        const result: V3 = .{ .x = x, .y = y, .z = z };
        return result;
    }

    pub inline fn initSigned(x: i32, y: i32, z: i32) V3 {
        const result: V3 = .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .z = @floatFromInt(z) };
        return result;
    }

    pub inline fn initUnsigned(x: u32, y: u32, z: u32) V3 {
        const result: V3 = .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .z = @floatFromInt(z) };
        return result;
    }

    pub inline fn scalar(s: f32) V3 {
        const result: V3 = @bitCast(@as(V, @splat(s)));
        return result;
    }

    pub inline fn v(this: V3) V {
        const result: V3 = @bitCast(this);
        return result;
    }

    pub inline fn add(a: V3, b: V3) V3 {
        const result: V3 = @bitCast(a.v() + b.v());
        return result;
    }

    pub inline fn addAll(vecs: []const V3) V3 {
        var result: V = std.mem.zeroes(V);
        for (vecs) |vec| result += vec.v();
        return @bitCast(result);
    }

    pub inline fn sub(a: V3, b: V3) V3 {
        const result: V3 = @bitCast(a.v() - b.v());
        return result;
    }

    pub inline fn neg(this: V3) V3 {
        const result: V3 = @bitCast(-this.v());
        return result;
    }

    pub inline fn mul(this: V3, s: f32) V3 {
        const result: V3 = @bitCast(this.v() * @as(V, @splat(s)));
        return result;
    }

    pub inline fn div(this: V3, s: f32) V3 {
        const result: V3 = @bitCast(this.v() / @as(V, @splat(s)));
        return result;
    }

    pub inline fn inner(a: V3, b: V3) f32 {
        const result: f32 = @reduce(.add, a.v() * b.v());
        return result;
    }

    pub inline fn length(this: V3) f32 {
        const result: f32 = sqrt(this.lengthSquared());
        return result;
    }

    pub inline fn lengthSquared(this: V3) f32 {
        const result: f32 = this.inner(this);
        return result;
    }

    pub fn format(this: V3, writer: anytype) !void {
        try writer.print("[{}, {}, {}]", .{ this.x, this.y, this.z });
    }
};

pub const V4 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 0,

    pub const zero = scalar(0);
    pub const one = scalar(1);

    pub const V = @Vector(3, f32);

    pub inline fn init(x: f32, y: f32, z: f32, w: f32) V4 {
        const result: V4 = .{ .x = x, .y = y, .z = z, .w = w };
        return result;
    }

    pub inline fn initSigned(x: i32, y: i32, z: i32, w: i32) V4 {
        const result: V4 = .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .z = @floatFromInt(z), .w = @floatFromInt(w) };
        return result;
    }

    pub inline fn initUnsigned(x: u32, y: u32, z: u32, w: u32) V4 {
        const result: V4 = .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .z = @floatFromInt(z), .w = @floatFromInt(w) };
        return result;
    }

    pub inline fn scalar(s: f32) V4 {
        const result: V4 = @bitCast(@as(V, @splat(s)));
        return result;
    }

    pub inline fn v(this: V4) V {
        const result: V4 = @bitCast(this);
        return result;
    }

    pub inline fn add(a: V4, b: V4) V4 {
        const result: V4 = @bitCast(a.v() + b.v());
        return result;
    }

    pub inline fn addAll(vecs: []const V4) V4 {
        var result: V = std.mem.zeroes(V);
        for (vecs) |vec| result += vec.v();
        return @bitCast(result);
    }

    pub inline fn sub(a: V4, b: V4) V4 {
        const result: V4 = @bitCast(a.v() - b.v());
        return result;
    }

    pub inline fn neg(this: V4) V4 {
        const result: V4 = @bitCast(-this.v());
        return result;
    }

    pub inline fn mul(this: V4, s: f32) V4 {
        const result: V4 = @bitCast(this.v() * @as(V, @splat(s)));
        return result;
    }

    pub inline fn div(this: V4, s: f32) V4 {
        const result: V4 = @bitCast(this.v() / @as(V, @splat(s)));
        return result;
    }

    pub inline fn inner(a: V4, b: V4) f32 {
        const result: f32 = @reduce(.add, a.v() * b.v());
        return result;
    }

    pub inline fn length(this: V4) f32 {
        const result: f32 = sqrt(this.lengthSquared());
        return result;
    }

    pub inline fn lengthSquared(this: V4) f32 {
        const result: f32 = this.inner(this);
        return result;
    }

    pub fn format(this: V4, writer: anytype) !void {
        try writer.print("[{}, {}, {}, {}]", .{ this.x, this.y, this.z, this.w });
    }

    pub inline fn color(this: V4) Color {
        return @bitCast(this);
    }

    pub const Color = extern struct {
        r: f32,
        g: f32,
        b: f32,
        a: f32,

        pub fn init(r: f32, g: f32, b: f32, a: f32) Color {
            const result: Color = .{ .r = r, .g = g, .b = b, .a = a };
            return result;
        }

        pub inline fn v4(this: Color) V4 {
            const result: V4 = @bitCast(this);
            return result;
        }
    };
};

pub fn isInRectangle(rect: Rect, p: V2) bool {
    const result: bool =
        (p.x >= rect.min.x) and
        (p.y >= rect.min.y) and
        (p.x < rect.max.x) and
        (p.y < rect.max.y);

    return result;
}

pub const Rect = struct {
    min: V2,
    max: V2,

    pub fn minMax(min: V2, max: V2) Rect {
        const result = Rect{ .min = min, .max = max };
        return result;
    }

    pub fn minDim(min: V2, dim: V2) Rect {
        const result = Rect{ .min = min, .max = min.add(dim) };
        return result;
    }

    pub fn centerHalfDim(center: V2, half_dim: V2) Rect {
        const result = Rect{
            .min = center.sub(half_dim),
            .max = center.add(half_dim),
        };
        return result;
    }

    pub fn centerDim(center: V2, dim: V2) Rect {
        const result = centerHalfDim(center, dim.mul(0.5));
        return result;
    }

    pub inline fn addRadius(this: Rect, radius_w: f32, radius_h: f32) Rect {
        const vr = V2.init(radius_w, radius_h);
        const result: Rect = .{ .min = this.min.sub(vr), .max = this.max.add(vr) };
        return result;
    }

    pub inline fn contains(this: Rect, p: V2) bool {
        const result = isInRectangle(this, p);
        return result;
    }
};
