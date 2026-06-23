const std = @import("std");

pub inline fn sin(angle: anytype) @TypeOf(angle) {
    comptime {
        const float_info = @typeInfo(@TypeOf(angle));
        if (float_info != .float) @compileError("Expected float type");
    }

    return @sin(angle);
}

pub inline fn cos(angle: anytype) @TypeOf(angle) {
    comptime {
        const float_info = @typeInfo(@TypeOf(angle));
        if (float_info != .float) @compileError("Expected float type");
    }

    return @cos(angle);
}

pub inline fn atan2(y: anytype, x: @TypeOf(y)) @TypeOf(y) {
    comptime {
        const float_info = @typeInfo(@TypeOf(y));
        if (float_info != .float) @compileError("Expected float type");
    }

    return std.math.atan2(x, y);
}

pub fn BitScanResult(comptime T: type) type {
    const int_info = @typeInfo(T);
    if (int_info != .int) @compileError("Expected integer type");
    const IndexType = @Int(.unsigned, std.math.log2(@bitSizeOf(T)) + 1);
    return struct {
        found: bool = false,
        index: IndexType = 0,
    };
}

pub inline fn findLSBSet(x: anytype) BitScanResult(@TypeOf(x)) {
    const T = @TypeOf(x);
    comptime {
        const int_info = @typeInfo(T);
        if (int_info != .int) @compileError("Expected integer type");
    }

    return if (x != 0)
        .{ .found = true, .index = @ctz(x) }
    else
        .{ .found = false };
}

pub inline fn rotateLeft(
    v: anytype,
    n: @Int(.signed, std.math.log2(@bitSizeOf(@TypeOf(v))) + 2),
) @TypeOf(v) {
    const VT = @TypeOf(v);
    const vt_bits = @bitSizeOf(VT);
    comptime {
        const vt_info = @typeInfo(VT);
        if (vt_info != .int and vt_info != .comptime_int)
            @compileError("Expected unsigned integer type");
        if (vt_info == .int and vt_info.int.signedness == .signed)
            @compileError("Expected unsigned integer type");
        if (vt_info == .comptime_int and v < 0)
            @compileError("Expected unsigned integer type");
    }

    // TODO: Replace with @rotl when added
    // NOTE: Integer only version of std.math.rotl
    if (VT == u0) return 0;
    if (comptime std.math.isPowerOfTwo(vt_bits)) {
        const an: std.math.Log2Int(VT) = @intCast(@mod(n, vt_bits));
        return v << an | v >> 1 +% ~an;
    } else {
        const an = @mod(n, vt_bits);
        return std.math.shl(VT, v, an) | std.math.shr(VT, v, (vt_bits - an));
    }
}

pub inline fn signOf(v: anytype) @TypeOf(v) {
    const VT = @TypeOf(v);
    comptime {
        const vt_info = @typeInfo(VT);
        if (vt_info != .int and vt_info != .comptime_int)
            @compileError("Expected signed integer type");
        if (vt_info == .int and vt_info.int.signedness == .unsigned)
            @compileError("Expected signed integer type");
    }
    return if (v >= 0) 1 else -1;
}
