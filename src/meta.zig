const std = @import("std");

pub inline fn matchTypeIds(x: anytype, comptime type_ids: []const std.lang.TypeId) bool {
    return matchType(@TypeOf(x), type_ids);
}

pub inline fn matchType(comptime T: type, comptime type_ids: []const std.lang.TypeId) bool {
    comptime {
        const tag = std.meta.activeTag(@typeInfo(T));
        const result = std.mem.findScalar(std.lang.TypeId, type_ids, tag) != null;
        return result;
    }
}

pub inline fn matchPtrType(comptime T: type) bool {
    return matchType(T, &.{.pointer});
}

pub inline fn matchFloatType(comptime T: type) bool {
    return matchType(T, &.{ .float, .comptime_float });
}

pub inline fn matchIntType(comptime T: type) bool {
    return matchType(T, &.{ .int, .comptime_int });
}

pub inline fn matchSigned(x: anytype) bool {
    const T = @TypeOf(x);
    const info = @typeInfo(T);

    const signed: bool = if (info == .int)
        info.int.signedness == .signed
    else if (info == .comptime_int)
        true
    else
        false;

    return signed;
}

pub inline fn matchUnsigned(x: anytype) bool {
    const T = @TypeOf(x);
    const info = @typeInfo(T);

    const unsigned: bool = if (info == .int)
        info.int.signedness == .unsigned
    else if (info == .comptime_int)
        x >= 0
    else
        false;

    return unsigned;
}

pub inline fn expectTypeIds(x: anytype, comptime type_ids: []const std.lang.TypeId) void {
    if (!matchTypeIds(x, type_ids))
        @compileError(std.fmt.comptimePrint("Expected one of: '{any}', got: '{}'", .{ type_ids, std.meta.activeTag(@typeInfo(@TypeOf(x))) }));
}

pub inline fn expectPtr(x: anytype) void {
    if (!matchPtrType(@TypeOf(x)))
        @compileError("Expected pointer type");
}

pub inline fn expectPtrType(comptime T: type) void {
    if (!matchPtrType(T))
        @compileError("Expected pointer type");
}

pub inline fn expectFloat(x: anytype) void {
    if (!matchFloatType(@TypeOf(x)))
        @compileError("Expected float type");
}

pub inline fn expectInt(x: anytype) void {
    if (!matchIntType(@TypeOf(x)))
        @compileError("Expected integer type");
}

pub inline fn expectIntType(comptime T: type) void {
    if (!matchIntType(T))
        @compileError("Expected integer type");
}

pub inline fn expectSigned(x: anytype) void {
    if (!matchSigned(x))
        @compileError("Expected signed integer type");
}

pub inline fn expectUnsigned(x: anytype) void {
    if (!matchUnsigned(x))
        @compileError("Expected signed integer type");
}
