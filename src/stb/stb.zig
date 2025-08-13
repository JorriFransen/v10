const std = @import("std");
const mem = @import("memory");
const log = std.log.scoped(.stb);
pub const c_stbi = @cImport({
    @cInclude("stb/stb_image.h");
});

const Allocator = std.mem.Allocator;

const assert = std.debug.assert;

var current_temp: mem.TempArena = undefined;

pub const image = struct {
    pub const Format = enum(c_int) {
        grey = c_stbi.STBI_grey,
        grey_alpha = c_stbi.STBI_grey_alpha,
        rgb = c_stbi.STBI_rgb,
        rgb_alpha = c_stbi.STBI_rgb_alpha,
    };
    pub const rgb_alpha = c_stbi.STBI_rgb_alpha;

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

    pub fn load(allocator: Allocator, path: []const u8, format: Format) Error!Texture {
        current_temp = mem.TempArena.init(&mem.stb_arena);
        defer current_temp.release();

        var x: c_int = undefined;
        var y: c_int = undefined;
        var c: c_int = undefined;
        const data_opt = stbi_load(path, &x, &y, &c, format);
        const stb_data = data_opt orelse return error.StbiLoadFailed;

        assert(@intFromEnum(format) == c); // This might be desired in some cases?

        const len = @as(usize, @intCast(x * y * c));
        const data = try allocator.alloc(u8, len);
        @memcpy(data, stb_data[0..len]);

        stbi_image_free(stb_data);

        return .{
            .x = @intCast(x),
            .y = @intCast(y),
            .c = @intCast(c),
            .data = data,
        };
    }

    pub fn loadFromMemory(allocator: Allocator, buffer: []const u8, format: Format) Error!Texture {
        current_temp = mem.TempArena.init(&mem.stb_arena);
        defer current_temp.release();

        const format_int: c_int = @intFromEnum(format);

        var x: c_int = undefined;
        var y: c_int = undefined;
        var c: c_int = undefined;
        const data_opt = stbi_load_from_memory(buffer.ptr, @intCast(buffer.len), &x, &y, &c, format_int);
        const stb_data = data_opt orelse return error.StbiLoadFailed;

        const len = @as(usize, @intCast(x * y * format_int));
        const data = try allocator.alloc(u8, len);
        @memcpy(data, stb_data[0..len]);

        stbi_image_free(stb_data);

        return .{
            .x = @intCast(x),
            .y = @intCast(y),
            .c = @intCast(c),
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

pub export fn stbiZigAssert(condition: c_int) callconv(.c) void {
    std.debug.assert(condition != 0);
}

pub export fn stbiZigMalloc(size: usize) callconv(.c) ?*anyopaque {
    const padded_size = size + header_size;
    const raw_ptr_opt = current_temp.arena.rawAlloc(padded_size, default_align);
    const raw_ptr: [*]u8 = raw_ptr_opt orelse {
        log.err("stbi arena malloc failure!", .{});
        return null;
    };

    const ptrs: []usize = @as([*]usize, @ptrCast(@alignCast(raw_ptr)))[0..2];
    ptrs[0] = size;
    return @ptrCast(&ptrs[1]);
}

pub export fn stbiZigRealloc(ptr: ?*anyopaque, new_size: usize) callconv(.c) ?*anyopaque {
    if (ptr) |p| {
        if (new_size == 0) {
            stbiZigFree(ptr);
            return null;
        }

        const old_raw_start: [*]u8 = @as([*]u8, @ptrCast(p)) - header_size;
        const old_ptrs: []usize = @as([*]usize, @ptrCast(@alignCast(old_raw_start)))[0..2];
        const old_total_size = old_ptrs[0] + header_size;
        const old_memory: []u8 = @as([*]u8, @ptrCast(&old_ptrs[0]))[0..old_total_size];

        assert(&old_ptrs[1] == @as(*usize, @ptrCast(@alignCast(ptr))));
        const new_total_size = new_size + header_size;

        if (current_temp.arena.rawResize(old_memory, default_align, new_total_size)) {
            old_ptrs[0] = new_size;

            return ptr;
        } else {
            const new_ptr_opt = current_temp.arena.rawRemap(old_memory, default_align, new_total_size);
            const new_raw_ptr: [*]u8 = new_ptr_opt orelse {
                log.err("stbi arena realloc failure!", .{});
                return null;
            };
            const ptrs: []usize = @as([*]usize, @ptrCast(@alignCast(new_raw_ptr)))[0..2];
            ptrs[0] = new_size;
            return &ptrs[1];
        }
    } else {
        assert(new_size > 0);
        return stbiZigMalloc(new_size);
    }
}

pub export fn stbiZigFree(ptr: ?*anyopaque) callconv(.c) void {
    if (ptr) |p| {
        const raw_ptr: [*]u8 = @as([*]u8, @ptrCast(p)) - header_size;
        const ptrs: []usize = @as([*]usize, @ptrCast(@alignCast(raw_ptr)))[0..2];
        const memory: []u8 = @as([*]u8, @ptrCast(&ptrs[0]))[0..ptrs[0]];
        assert(&ptrs[1] == @as(*usize, @ptrCast(@alignCast(ptr))));

        current_temp.arena.rawFree(memory, default_align);
    }
}
