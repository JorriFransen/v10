const std = @import("std");

pub const pi = std.math.pi;
pub const tau = std.math.tau;

pub const maxInt = std.math.maxInt;
pub const minInt = std.math.minInt;
pub const maxFloat = std.math.floatMax;
pub const minFloat = std.math.floatMin;
pub const atan2 = std.math.atan2;
pub const log2 = std.math.log2;
pub const isPowerOfTwo = std.math.isPowerOfTwo;
pub const shl = std.math.shl;
pub const shr = std.math.shr;

const math = @This();

pub const Log2Int = std.math.Log2Int;

pub inline fn square(x: f32) f32 {
    return x * x;
}

pub inline fn sqrt(x: f32) f32 {
    return @sqrt(x);
}

pub inline fn lerp(a: f32, t: f32, b: f32) f32 {
    const result = ((1 - t) * a) + (t * b);
    return result;
}

pub inline fn clamp(min: f32, value: f32, max: f32) f32 {
    const result = @min(max, @max(min, value));
    return result;
}

pub inline fn clamp01(value: f32) f32 {
    const result = clamp(0, value, 1);
    return result;
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

pub inline fn safeRatioN(numerator: f32, divisor: f32, n: f32) f32 {
    var result: f32 = n;

    if (divisor != 0) {
        result = numerator / divisor;
    }

    return result;
}

pub inline fn safeRatio0(numerator: f32, divisor: f32) f32 {
    const result = safeRatioN(numerator, divisor, 0);
    return result;
}

pub inline fn safeRatio1(numerator: f32, divisor: f32) f32 {
    const result = safeRatioN(numerator, divisor, 1);
    return result;
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

    pub const i = initSigned;
    pub inline fn initSigned(x: i32, y: i32) V2 {
        const result: V2 = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
        return result;
    }

    pub const u = initUnsigned;
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

    pub inline fn hadamard(a: V2, b: V2) V2 {
        const result: V2 = @bitCast(a.v() * b.v());
        return result;
    }

    pub const dot = inner;
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

    pub inline fn clamp01(this: V2) V2 {
        const min: V = @splat(0);
        const max: V = @splat(1);

        const result: V2 = @bitCast(@min(max, @max(min, this.v())));

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

    pub const i = initSigned;
    pub inline fn initSigned(x: i32, y: i32, z: i32) V3 {
        const result: V3 = .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .z = @floatFromInt(z) };
        return result;
    }

    pub const u = initUnsigned;
    pub inline fn initUnsigned(x: u32, y: u32, z: u32) V3 {
        const result: V3 = .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .z = @floatFromInt(z) };
        return result;
    }

    pub const v2z = initV2Z;
    pub inline fn initV2Z(v2: V2, z: f32) V3 {
        const result: V3 = .{ .x = v2.x, .y = v2.y, .z = z };
        return result;
    }

    pub inline fn scalar(s: f32) V3 {
        const result: V3 = @bitCast(@as(V, @splat(s)));
        return result;
    }

    pub inline fn v(this: V3) V {
        const result: V = @bitCast(this);
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

    pub inline fn hadamard(a: V3, b: V3) V3 {
        const result: V3 = @bitCast(a.v() * b.v());
        return result;
    }

    pub const dot = inner;
    pub inline fn inner(a: V3, b: V3) f32 {
        const result: f32 = @reduce(.Add, a.v() * b.v());
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

    pub inline fn xy(this: V3) V2 {
        const result: V2 = .{ .x = this.x, .y = this.y };
        return result;
    }

    pub inline fn clamp01(this: V3) V3 {
        const min: V = @splat(0);
        const max: V = @splat(1);

        const result: V3 = @bitCast(@min(max, @max(min, this.v())));

        return result;
    }

    pub fn format(this: V3, writer: anytype) !void {
        try writer.print("[{}, {}, {}]", .{ this.x, this.y, this.z });
    }

    pub inline fn color(this: V3) Color {
        return @bitCast(this);
    }

    pub const Color = extern struct {
        r: f32,
        g: f32,
        b: f32,

        pub fn init(r: f32, g: f32, b: f32) Color {
            const result: Color = .{ .r = r, .g = g, .b = b };
            return result;
        }

        pub inline fn v3(this: Color) V3 {
            const result: V3 = @bitCast(this);
            return result;
        }
    };
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

    pub const i = initSigned;
    pub inline fn initSigned(x: i32, y: i32, z: i32, w: i32) V4 {
        const result: V4 = .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .z = @floatFromInt(z), .w = @floatFromInt(w) };
        return result;
    }

    pub const u = initUnsigned;
    pub inline fn initUnsigned(x: u32, y: u32, z: u32, w: u32) V4 {
        const result: V4 = .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .z = @floatFromInt(z), .w = @floatFromInt(w) };
        return result;
    }

    pub inline fn scalar(s: f32) V4 {
        const result: V4 = @bitCast(@as(V, @splat(s)));
        return result;
    }

    pub inline fn v(this: V4) V {
        const result: V = @bitCast(this);
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

    pub inline fn hadamard(a: V4, b: V4) V4 {
        const result: V4 = @bitCast(a.v() * b.v());
        return result;
    }

    pub const dot = inner;
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

    pub inline fn clamp01(this: V4) V4 {
        const min: V = @splat(0);
        const max: V = @splat(1);

        const result: V3 = @bitCast(@min(max, @max(min, this.v())));

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

pub inline fn isInRectangle(rect: Rect, p: V2) bool {
    const result: bool =
        (p.x >= rect.min.x) and
        (p.y >= rect.min.y) and
        (p.x < rect.max.x) and
        (p.y < rect.max.y);

    return result;
}

pub inline fn rectanglesIntersect(a: Rect, b: Rect) bool {
    const result =
        (a.max.x >= b.min.x and a.min.x <= b.max.x) and
        (a.max.y >= b.min.y and a.min.y <= b.max.y);
    return result;
}

pub inline fn getBarycentric(a: Rect, p: V2) V2 {
    const result: V2 = .{
        .x = safeRatio0(p.x - a.min.x, a.max.x - a.min.x),
        .y = safeRatio0(p.y - a.min.y, a.max.y - a.min.y),
    };

    return result;
}

pub const Rect = struct {
    min: V2,
    max: V2,

    pub inline fn minMax(min: V2, max: V2) Rect {
        const result = Rect{ .min = min, .max = max };
        return result;
    }

    pub inline fn minDim(min: V2, dim: V2) Rect {
        const result = Rect{ .min = min, .max = min.add(dim) };
        return result;
    }

    pub inline fn centerHalfDim(center: V2, half_dim: V2) Rect {
        const result = Rect{
            .min = center.sub(half_dim),
            .max = center.add(half_dim),
        };
        return result;
    }

    pub inline fn centerDim(center: V2, dim: V2) Rect {
        const result = centerHalfDim(center, dim.mul(0.5));
        return result;
    }

    pub inline fn addRadius(this: Rect, radius: V2) Rect {
        const result: Rect = .{
            .min = this.min.sub(radius),
            .max = this.max.add(radius),
        };
        return result;
    }

    pub inline fn offset(this: Rect, d: V2) Rect {
        const result: Rect = .{
            .min = this.min.add(d),
            .max = this.max.add(d),
        };
        return result;
    }

    pub inline fn contains(this: Rect, p: V2) bool {
        const result = isInRectangle(this, p);
        return result;
    }

    pub inline fn intersects(this: Rect, rect: Rect) bool {
        return rectanglesIntersect(this, rect);
    }

    pub inline fn barycentric(this: Rect, p: V2) V2 {
        const result = getBarycentric(this, p);
        return result;
    }
};

pub inline fn isInRectangle3(rect: Rect3, p: V3) bool {
    const result: bool =
        (p.x >= rect.min.x) and
        (p.y >= rect.min.y) and
        (p.z >= rect.min.z) and
        (p.x < rect.max.x) and
        (p.y < rect.max.y) and
        (p.z < rect.max.z);

    return result;
}

pub inline fn rectangles3Intersect(a: Rect3, b: Rect3) bool {
    const result =
        !((a.max.x <= b.min.x or a.min.x >= b.max.x) or
            (a.max.y <= b.min.y or a.min.y >= b.max.y) or
            (a.max.z <= b.min.z or a.min.z >= b.max.z));
    return result;
}

pub inline fn getBarycentric3(a: Rect3, p: V3) V3 {
    const result: V3 = .{
        .x = safeRatio0(p.x - a.min.x, a.max.x - a.min.x),
        .y = safeRatio0(p.y - a.min.y, a.max.y - a.min.y),
        .z = safeRatio0(p.z - a.min.z, a.max.z - a.min.z),
    };

    return result;
}

pub const Rect3 = struct {
    min: V3,
    max: V3,

    pub inline fn minMax(min: V3, max: V3) Rect3 {
        const result = Rect3{ .min = min, .max = max };
        return result;
    }

    pub inline fn minDim(min: V3, dim: V3) Rect3 {
        const result = Rect3{ .min = min, .max = min.add(dim) };
        return result;
    }

    pub inline fn centerHalfDim(center: V3, half_dim: V3) Rect3 {
        const result = Rect3{
            .min = center.sub(half_dim),
            .max = center.add(half_dim),
        };
        return result;
    }

    pub inline fn centerDim(center: V3, dim: V3) Rect3 {
        const result = centerHalfDim(center, dim.mul(0.5));
        return result;
    }

    pub inline fn addRadius(this: Rect3, radius: V3) Rect3 {
        const result: Rect3 = .{
            .min = this.min.sub(radius),
            .max = this.max.add(radius),
        };
        return result;
    }

    pub inline fn offset(this: Rect3, d: V3) Rect3 {
        const result: Rect3 = .{
            .min = this.min.add(d),
            .max = this.max.add(d),
        };
        return result;
    }

    pub inline fn contains(this: Rect3, p: V3) bool {
        const result = isInRectangle3(this, p);
        return result;
    }

    pub inline fn intersects(this: Rect3, rect: Rect3) bool {
        return rectangles3Intersect(this, rect);
    }

    pub inline fn barycentric(this: Rect3, p: V3) V3 {
        const result = getBarycentric3(this, p);
        return result;
    }
};
