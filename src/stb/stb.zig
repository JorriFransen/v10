const std = @import("std");
const mem = @import("memory");
const log = std.log.scoped(.stb);

pub const c = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_rect_pack.h");
    @cInclude("stb_truetype.h");
});

const Allocator = std.mem.Allocator;
const Arena = mem.Arena;

const assert = std.debug.assert;

var current_temp: mem.TempArena = undefined;

pub const image = struct {
    pub const Format = enum(c_int) {
        grey = c.STBI_grey,
        grey_alpha = c.STBI_grey_alpha,
        rgb = c.STBI_rgb,
        rgb_alpha = c.STBI_rgb_alpha,
    };
    pub const rgb_alpha = c.STBI_rgb_alpha;

    pub const Texture = struct {
        x: u32,
        y: u32,
        c: u32,
        data: []const u8,
    };

    pub const Error = error{
        StbiLoadFailed,
        OutOfMemory,
    };

    pub fn load(allocator: Allocator, path: [:0]const u8, format: Format) Error!Texture {
        current_temp = mem.TempArena.init(&mem.stb_arena);
        defer current_temp.release();

        const format_int: c_int = @intFromEnum(format);

        var x: c_int = undefined;
        var y: c_int = undefined;
        var channels: c_int = undefined;
        const data_opt = stbi_load(path, &x, &y, &channels, format_int);
        const stb_data = data_opt orelse return error.StbiLoadFailed;

        assert(@intFromEnum(format) == channels); // This might be desired in some cases?

        const len = @as(usize, @intCast(x * y * format_int));
        const data = try allocator.alloc(u8, len);
        @memcpy(data, stb_data[0..len]);

        stbi_image_free(stb_data);

        return .{
            .x = @intCast(x),
            .y = @intCast(y),
            .c = @intCast(channels),
            .data = data,
        };
    }

    pub fn loadFromMemory(allocator: Allocator, buffer: []const u8, format: Format) Error!Texture {
        current_temp = mem.TempArena.init(&mem.stb_arena);
        defer current_temp.release();

        const format_int: c_int = @intFromEnum(format);

        var x: c_int = undefined;
        var y: c_int = undefined;
        var channels: c_int = undefined;
        const data_opt = stbi_load_from_memory(buffer.ptr, @intCast(buffer.len), &x, &y, &channels, format_int);
        const stb_data = data_opt orelse return error.StbiLoadFailed;

        assert(@intFromEnum(format) == channels); // This might be desired in some cases?

        const len = @as(usize, @intCast(x * y * format_int));
        const data = try allocator.alloc(u8, len);
        @memcpy(data, stb_data[0..len]);

        stbi_image_free(stb_data);

        return .{
            .x = @intCast(x),
            .y = @intCast(y),
            .c = @intCast(channels),
            .data = data,
        };
    }
};

const stbi_load = f("stbi_load", fn (path: [*:0]const u8, x: *c_int, y: *c_int, c: *c_int, desired_c: c_int) callconv(.c) ?[*]const u8);
const stbi_load_from_memory = f("stbi_load_from_memory", fn (buffer: [*]const u8, len: c_int, x: *c_int, y: *c_int, c: *c_int, desired_c: c_int) callconv(.c) ?[*]const u8);
const stbi_image_free = f("stbi_image_free", fn (data: [*]const u8) callconv(.c) void);

fn f(comptime name: []const u8, comptime T: type) *const T {
    return @extern(*const T, .{ .name = name, .library_name = "c" });
}

const default_align = std.mem.Alignment.fromByteUnits(@alignOf(usize));
const header_size: usize = @sizeOf(usize);

pub export fn stbZigAssert(condition: c_int) callconv(.c) void {
    std.debug.assert(condition != 0);
}

fn arenaAlloc(arena: *Arena, size: usize) ?*anyopaque {
    assert(size > 0);

    const total_size = size + header_size;
    const raw_ptr_opt = arena.rawAlloc(total_size, default_align);
    const raw_ptr: [*]u8 = raw_ptr_opt orelse {
        log.err("stbi arena malloc failure!", .{});
        return null;
    };

    const header_ptr = @as(*usize, @ptrCast(@alignCast(raw_ptr)));
    header_ptr.* = size;

    return @ptrCast(raw_ptr + header_size);
}

fn arenaFree(arena: *Arena, ptr: ?*anyopaque) void {
    if (ptr) |p| {
        const raw_ptr = @as([*]u8, @ptrCast(p)) - header_size;
        const header_ptr = @as(*const usize, @ptrCast(@alignCast(raw_ptr)));
        const size = header_ptr.*;
        const slice = raw_ptr[0 .. size + header_size];
        arena.rawFree(slice, default_align);
    }
}

pub export fn stbiZigMalloc(size: usize) callconv(.c) ?*anyopaque {
    return arenaAlloc(current_temp.arena, size);
}

pub export fn stbiZigRealloc(ptr: ?*anyopaque, new_size: usize) callconv(.c) ?*anyopaque {
    if (ptr == null) {
        return stbiZigMalloc(new_size);
    }

    const p = ptr.?;
    if (new_size == 0) {
        stbiZigFree(p);
        return null;
    }

    const old_raw_ptr = @as([*]u8, @ptrCast(p)) - header_size;
    const old_header_ptr = @as(*usize, @ptrCast(@alignCast(old_raw_ptr)));
    const old_user_size = old_header_ptr.*;
    const old_total_size = old_user_size + header_size;
    const old_slice = old_raw_ptr[0..old_total_size];

    const new_total_size = new_size + header_size;

    if (current_temp.arena.rawResize(old_slice, default_align, new_total_size)) {
        old_header_ptr.* = new_size;
        return p;
    } else {
        const new_ptr_opt = current_temp.arena.rawRemap(old_slice, default_align, new_total_size);
        const new_raw_ptr = new_ptr_opt orelse {
            log.err("stbi arena realloc failure!", .{});
            return null;
        };

        const new_header_ptr = @as(*usize, @ptrCast(@alignCast(new_raw_ptr)));
        new_header_ptr.* = new_size;
        return @ptrCast(new_raw_ptr + header_size);
    }
}

pub export fn stbiZigFree(ptr: ?*anyopaque) callconv(.c) void {
    arenaFree(current_temp.arena, ptr);
}

pub export fn stbttZigIFloor(x: f64) callconv(.c) c_int {
    return @intFromFloat(@floor(x));
}

pub export fn stbttZigICeil(x: f64) callconv(.c) c_int {
    return @intFromFloat(@ceil(x));
}

pub export fn stbttZigSqrt(x: f64) callconv(.c) f64 {
    return @sqrt(x);
}

pub export fn stbttZigPow(x: f64, y: f64) callconv(.c) f64 {
    return std.math.pow(f64, x, y);
}

pub export fn stbttZigFmod(x: f64, y: f64) callconv(.c) f64 {
    return @mod(x, y);
}

pub export fn stbttZigCos(x: f64) callconv(.c) f64 {
    return @cos(x);
}

pub export fn stbttZigACos(x: f64) callconv(.c) f64 {
    return std.math.acos(x);
}

pub export fn stbttZigFabs(x: f64) callconv(.c) f64 {
    return @abs(x);
}

pub export fn stbttZigMalloc(size: usize, ctx: ?*anyopaque) callconv(.c) ?*anyopaque {
    assert(ctx != null);
    const arena: *Arena = @ptrCast(@alignCast(ctx));
    return arenaAlloc(arena, size);
}

pub export fn stbttZigFree(ptr: ?*anyopaque, ctx: ?*anyopaque) callconv(.c) void {
    assert(ctx != null);
    const arena: *Arena = @ptrCast(@alignCast(ctx));
    arenaFree(arena, ptr);
}

pub export fn stbttStrlen(x: [*:0]const u8) callconv(.c) usize {
    return std.mem.span(x).len;
}

pub export fn stbttMemcpy(dst_ptr: *anyopaque, noalias src_ptr: *anyopaque, count: usize) callconv(.c) *anyopaque {
    const dst = @as([*]u8, @ptrCast(dst_ptr));
    const src = @as([*]u8, @ptrCast(src_ptr));
    @memcpy(dst[0..count], src[0..count]);
    return dst;
}

pub export fn stbttMemset(dst_ptr: *anyopaque, fill_byte: c_int, count: usize) callconv(.c) *anyopaque {
    const dst = @as([*]u8, @ptrCast(dst_ptr));
    @memset(dst[0..count], @intCast(fill_byte));
    return dst;
}
