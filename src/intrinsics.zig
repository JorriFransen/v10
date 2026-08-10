const math = @import("math");
const meta = @import("meta");
const builtin = @import("builtin");

pub fn BitScanResult(comptime T: type) type {
    meta.expectIntType(T);

    const IndexType = @Int(.unsigned, math.log2(@bitSizeOf(T)));
    return struct {
        found: bool = false,
        index: IndexType = 0,
    };
}

pub inline fn findLSBSet(x: anytype) BitScanResult(@TypeOf(x)) {
    meta.expectInt(x);

    return if (x != 0)
        // The type of @ctz here is one bit larger than the type of index, but the x!=0 guard makes this safe.
        .{ .found = true, .index = @intCast(@ctz(x)) }
    else
        .{ .found = false };
}

pub inline fn rotateLeft(
    v: anytype,
    n: @Int(.signed, math.log2(@bitSizeOf(@TypeOf(v))) + 2),
) @TypeOf(v) {
    const VT = @TypeOf(v);
    const vt_bits = @bitSizeOf(VT);

    meta.expectUnsigned(v);

    // TODO: Replace with @rotl when added
    // NOTE: Integer only version of std.math.rotl
    if (VT == u0) return 0;
    if (comptime math.isPowerOfTwo(vt_bits)) {
        const an: math.Log2Int(VT) = @intCast(@mod(n, vt_bits));
        return v << an | v >> 1 +% ~an;
    } else {
        const an = @mod(n, vt_bits);
        return math.shl(VT, v, an) | math.shr(VT, v, (vt_bits - an));
    }
}

pub inline fn signOf(v: anytype) @TypeOf(v) {
    meta.expectSigned(v);

    return if (v >= 0) 1 else -1;
}

pub inline fn roundReal32ToInt32(r: f32) i32 {
    @setRuntimeSafety(false);
    const rounded: f32 = @round(r);
    const result: i32 = @intFromFloat(rounded);
    return result;
}

pub inline fn roundReal32ToUInt32(r: f32) u32 {
    @setRuntimeSafety(false);
    const rounded: f32 = @round(r);
    const result: u32 = @intFromFloat(rounded);
    return result;
}

pub inline fn ptrOffset(ptr: anytype, offset: isize) @TypeOf(ptr) {
    const result = ptrOffsetT(@TypeOf(ptr), ptr, offset);
    return result;
}

pub inline fn ptrOffsetT(comptime T: type, ptr: *anyopaque, offset: isize) T {
    meta.expectPtrType(T);

    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        var result: [*]u8 = @ptrCast(@alignCast(ptr));

        if (offset >= 0) {
            result += @intCast(offset);
        } else {
            result -= @as(usize, @intCast(-offset));
        }

        return @ptrCast(@alignCast(result));
    } else {
        var result: [*]u8 = @ptrCast(@alignCast(ptr));
        result += @as(usize, @bitCast(offset));

        return @as(T, @ptrCast(@alignCast(result)));
    }
}
