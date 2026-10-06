const meta = @import("meta.zig");

pub inline fn unionOf(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    const Int = backing(a);
    return @bitCast(@as(Int, @bitCast(a)) | @as(Int, @bitCast(b)));
}

pub inline fn unionAll(comptime T: type, values: []const T) T {
    const Int = backingOf(T);
    var acc: Int = 0;
    for (values) |v| acc |= @as(Int, @bitCast(v));
    return @bitCast(acc);
}

pub inline fn intersectionOf(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    const Int = backing(a);
    return @bitCast(@as(Int, @bitCast(a)) & @as(Int, @bitCast(b)));
}

pub inline fn contains(a: anytype, b: @TypeOf(a)) bool {
    return intersectionOf(a, b) == b;
}

pub inline fn complement(x: anytype) @TypeOf(x) {
    return @bitCast(~@as(backing(x), @bitCast(x)));
}

pub inline fn without(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return intersectionOf(a, complement(b));
}

pub inline fn backing(x: anytype) type {
    return backingOf(@TypeOf(x));
}

pub inline fn backingOf(comptime T: type) type {
    meta.expectPackedStructType(T);
    return @typeInfo(T).@"struct".backing_integer.?;
}
