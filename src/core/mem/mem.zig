const std = @import("std");
const Allocator = std.mem.Allocator;

const assert = @import("../core.zig").assert;

pub const Arena = @import("arena.zig").Arena;
pub const TempArena = @import("temp_arena.zig");
pub const TempStringBuilder = TempArena.StringBuilder;

pub const KiB = 1024;
pub const MiB = 1024 * KiB;
pub const GiB = 1024 * MiB;
pub const TiB = 1024 * GiB;

pub threadlocal var temp_initialized = false;
threadlocal var temp_arena_a: Arena = undefined;
threadlocal var temp_arena_b: Arena = undefined;
threadlocal var temp_arena_next: *Arena = undefined;

pub fn init() void {
    initTemp();
}

pub fn deinit() void {
    deinitTemp();
}

/// Must be called on each thread using temp/scratch arenas
pub fn initTemp() void {
    assert(!temp_initialized);

    const options = Arena.InitOptions{ .virtual = .{ .reserved_capacity = 1 * GiB } };
    temp_arena_a = Arena.init(options) catch @panic("Temp arena init failed");
    temp_arena_b = Arena.init(options) catch @panic("Temp arena init failed");
    temp_arena_next = &temp_arena_a;

    temp_initialized = true;
}

pub fn deinitTemp() void {
    assert(temp_initialized);

    temp_arena_a.deinit() catch unreachable;
    temp_arena_b.deinit() catch unreachable;

    temp_arena_a = undefined;
    temp_arena_b = undefined;
    temp_arena_next = undefined;

    temp_initialized = false;
}

pub fn getTemp() TempArena {
    assert(temp_initialized);

    const use = temp_arena_next;

    if (temp_arena_next == &temp_arena_a) {
        temp_arena_next = &temp_arena_b;
    } else {
        temp_arena_next = &temp_arena_a;
    }

    return TempArena.init(use);
}

pub fn getScratch(conflict_allocator: Allocator) TempArena {
    assert(temp_initialized);

    const conflict: *const Arena = @ptrCast(@alignCast(conflict_allocator.ptr));

    var use: *Arena = temp_arena_next;

    if (conflict == &temp_arena_a) {
        use = &temp_arena_b;
        temp_arena_next = &temp_arena_a;
    } else if (conflict == &temp_arena_b) {
        use = &temp_arena_a;
        temp_arena_next = &temp_arena_b;
    } else if (temp_arena_next == &temp_arena_a) {
        temp_arena_next = &temp_arena_b;
    } else {
        assert(temp_arena_next == &temp_arena_b);
        temp_arena_next = &temp_arena_a;
    }

    return TempArena.init(use);
}

pub fn getScratchStringBuilder(conflict_allocator: Allocator) TempStringBuilder {
    const tmp = getScratch(conflict_allocator);
    const result = TempStringBuilder.init(tmp);

    return result;
}

/// Resets all temp/scratch arenas
pub fn resetTemp() void {
    assert(temp_initialized);

    temp_arena_a.reset();
    temp_arena_b.reset();
}

pub inline fn arenaAllocPrint(allocator: Allocator, comptime fmt: []const u8, args: anytype) ![]const u8 {
    var tmp = getScratch(allocator);
    defer tmp.release();

    const tmp_res = try std.fmt.allocPrint(tmp.a, fmt, args);
    const result = allocator.dupe(u8, tmp_res);

    return result;
}

/// Slices up to the sentinel, returns sentinel-terminated slice.
/// If the input is a sentinel-terminated slice, and contains no additional
///  sentinels, the original slice is returned.
/// If the input is a regular slice, and contains no sentinel, this is an invalid
///  input, causing a hard crash (assert).
pub inline fn sliceToSentinel(ptr: anytype, comptime sentinel: std.meta.Elem(@TypeOf(ptr))) SliceToSentinelRet(@TypeOf(ptr), sentinel) {
    const T = @TypeOf(ptr);
    const E = std.meta.Elem(T);

    var result: SliceToSentinelRet(T, sentinel) = undefined;

    if (std.mem.findScalar(E, ptr, sentinel)) |sentinel_idx| {
        result = ptr[0..sentinel_idx :sentinel];
    } else {
        const ti = @typeInfo(@TypeOf(ptr));
        assert(ti.pointer.sentinel_ptr != null);
        result = @ptrCast(ptr);
    }

    return result;
}

fn SliceToSentinelRet(comptime Slice: type, comptime sentinel: std.meta.Elem(Slice)) type {
    switch (@typeInfo(Slice)) {
        .pointer => |pi| {
            const E = std.meta.Elem(Slice);

            return @Pointer(.slice, .{
                .@"const" = pi.is_const,
                .@"volatile" = pi.is_volatile,
                .@"allowzero" = pi.is_allowzero and pi.size != .c,
                .@"align" = pi.alignment,
                .@"addrspace" = pi.address_space,
            }, E, sentinel);
        },

        else => @compileError("Invalid type given to sliceToSentinel: " ++ @typeName(Slice)),
    }
}

/// Copy 'path' into a (inlined) stack buffer, return null terminated slice.
pub inline fn stackPathZ(path: []const u8) [:0]const u8 {
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    assert(path.len + 1 <= buf.len);
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return buf[0..path.len :0];
}
