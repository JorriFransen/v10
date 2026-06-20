const std = @import("std");

pub inline fn roundFloatToInt(IntType: type, float: anytype) IntType {
    comptime {
        const float_info = @typeInfo(@TypeOf(float));
        if (float_info != .float) @compileError("Expected float type");

        const int_info = @typeInfo(IntType);
        if (int_info != .int) @compileError("Expected signed integer type");
        if (int_info.int.signedness != .signed) @compileError("Expected signed integer type");
    }

    return @intFromFloat(@round(float));
}

/// Note: negative inputs are clamped to 0!
pub inline fn roundFloatToUInt(UIntType: type, float: anytype) UIntType {
    comptime {
        const float_info = @typeInfo(@TypeOf(float));
        if (float_info != .float) @compileError("Expected float type");

        const int_info = @typeInfo(UIntType);
        if (int_info != .int) @compileError("Expected unsigned integer type");
        if (int_info.int.signedness != .unsigned) @compileError("Expected unsigned integer type");
    }

    return @intFromFloat(@round(@max(float, 0)));
}

pub inline fn floorFloatToInt(IntType: type, float: anytype) IntType {
    comptime {
        const float_info = @typeInfo(@TypeOf(float));
        if (float_info != .float) @compileError("Expected float type");

        const int_info = @typeInfo(IntType);
        if (int_info != .int) @compileError("Expected signed integer type");
        if (int_info.int.signedness != .signed) @compileError("Expected signed integer type");
    }

    return @intFromFloat(@floor(float));
}

/// Note: negative inputs are clamped to 0!
pub inline fn floorFloatToUInt(UIntType: type, float: anytype) UIntType {
    comptime {
        const float_info = @typeInfo(@TypeOf(float));
        if (float_info != .float) @compileError("Expected float type");

        const int_info = @typeInfo(UIntType);
        if (int_info != .int) @compileError("Expected unsigned integer type");
        if (int_info.int.signedness != .unsigned) @compileError("Expected unsigned integer type");
    }

    return @intFromFloat(@floor(@max(float, 0)));
}

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
    comptime {
        const vt_info = @typeInfo(VT);
        if (vt_info != .int and vt_info != .comptime_int)
            @compileError("Expected unsigned integer type");
        if (vt_info == .int and vt_info.int.signedness == .signed)
            @compileError("Expected unsigned integer type");
        if (vt_info == .comptime_int and v < 0)
            @compileError("Expected unsigned integer type");
    }

    // Note: std.math.rotl does @mod(n, @typeInfo(VT).int.bits). The 'bits' member
    //       is a u16, so if n has fewer than 16 bits, peer type resolution
    //       chooses u16. Because n can be negative, the peer type resulution
    //       needs to preserve the signedness. Casting to the same bit-width
    //       enforces this.
    const i16_n: i16 = @intCast(n);

    // TODO: Replace with @rotl when added
    return std.math.rotl(VT, v, i16_n);
}
