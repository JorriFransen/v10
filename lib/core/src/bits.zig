const meta = @import("meta.zig");

pub inline fn @"or"(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    const Int = backing(a);
    return @bitCast(@as(Int, @bitCast(a)) | @as(Int, @bitCast(b)));
}

pub inline fn @"and"(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    const Int = backing(a);
    return @bitCast(@as(Int, @bitCast(a)) & @as(Int, @bitCast(b)));
}

pub inline fn contains(a: anytype, b: @TypeOf(a)) bool {
    return @"and"(a, b) == b;
}

pub inline fn complement(x: anytype) @TypeOf(x) {
    return @bitCast(~@as(backing(x), @bitCast(x)));
}

pub inline fn without(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return @"and"(a, complement(b));
}

pub inline fn backing(a: anytype) type {
    const T = @TypeOf(a);
    meta.expectPackedStructType(T);
    return @typeInfo(T).@"struct".backing_integer.?;
}
