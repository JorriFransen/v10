const std = @import("std");

pub inline fn square(x: f32) f32 {
    return x * x;
}

pub inline fn sqrt(x: f32) f32 {
    return @sqrt(x);
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
        return .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
    }

    pub inline fn initUnsigned(x: u32, y: u32) V2 {
        return .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
    }

    pub inline fn initv(vec: V) V2 {
        return @bitCast(vec);
    }
    pub inline fn scalar(s: f32) V2 {
        return @bitCast(@as(V, @splat(s)));
    }

    pub inline fn v(this: V2) V {
        return @bitCast(this);
    }

    pub inline fn vp(this: *V2) *V {
        return @ptrCast(@alignCast(this));
    }

    pub inline fn add(a: V2, b: V2) V2 {
        return @bitCast(a.v() + b.v());
    }

    pub inline fn addAll(vecs: []const V2) V2 {
        var result: V = std.mem.zeroes(V);
        for (vecs) |vec| result += vec.v();
        return @bitCast(result);
    }

    pub inline fn addv(a: V2, b: V) V2 {
        return @bitCast(a.v() + b);
    }

    pub inline fn sub(a: V2, b: V2) V2 {
        return @bitCast(a.v() - b.v());
    }

    pub inline fn subv(a: V2, b: V) V2 {
        return @bitCast(a.v() - b);
    }

    pub inline fn neg(this: V2) V2 {
        return @bitCast(-this.v());
    }

    pub inline fn mul(this: V2, s: f32) V2 {
        return @bitCast(this.v() * @as(V, @splat(s)));
    }

    pub inline fn div(this: V2, s: f32) V2 {
        return @bitCast(this.v() / @as(V, @splat(s)));
    }

    pub inline fn inner(a: V2, b: V2) f32 {
        const result = a.x * b.x + a.y * b.y;
        return result;
    }

    pub inline fn length(this: V2) f32 {
        return sqrt(this.lengthSquared());
    }

    pub inline fn lengthSquared(this: V2) f32 {
        return this.inner(this);
    }

    pub fn format(this: V2, writer: anytype) !void {
        try writer.print("[{}, {}]", .{ this.x, this.y });
    }
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

    pub inline fn containsPoint(this: Rect, p: V2) bool {
        const result = isInRectangle(this, p);
        return result;
    }
};
