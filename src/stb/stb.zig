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

pub var current_temp: ?mem.TempArena = null;

pub const image = struct {
    pub const Format = enum(c_int) {
        default = 0,
        grey = 1,
        grey_alpha = 2,
        rgb = 3,
        rgb_alpha = 4,
    };

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
        defer {
            current_temp.?.release();
            current_temp = null;
        }

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
        defer {
            current_temp.?.release();
            current_temp = null;
        }

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

pub const truetype = struct {
    const Buf = extern struct {
        data: ?[*]u8 = null,
        cursor: c_int = 0,
        size: c_int = 0,
    };
    pub const FontInfo = extern struct {
        userdata: ?*anyopaque = null,
        data: ?[*]u8 = null,
        fontstart: c_int = 0,
        numGlyphs: c_int = 0,
        loca: c_int = 0,
        head: c_int = 0,
        glyf: c_int = 0,
        hhea: c_int = 0,
        hmtx: c_int = 0,
        kern: c_int = 0,
        gpos: c_int = 0,
        svg: c_int = 0,
        index_map: c_int = 0,
        indexToLocFormat: c_int = 0,
        cff: Buf = .{},
        charstrings: Buf = .{},
        gsubrs: Buf = .{},
        subrs: Buf = .{},
        fontdicts: Buf = .{},
        fdselect: Buf = .{},
    };

    pub const PackedChar = extern struct {
        x0: c_ushort = 0,
        y0: c_ushort = 0,
        x1: c_ushort = 0,
        y1: c_ushort = 0,
        xoff: f32 = 0,
        yoff: f32 = 0,
        xadvance: f32 = 0,
        xoff2: f32 = 0,
        yoff2: f32 = 0,
    };

    pub const PackContext = extern struct {
        user_allocator_context: ?*anyopaque = null,
        pack_info: ?*anyopaque = null,
        width: c_int = 0,
        height: c_int = 0,
        stride_in_bytes: c_int = 0,
        padding: c_int = 0,
        skip_missing: c_int = 0,
        h_oversample: c_uint = 0,
        v_oversample: c_uint = 0,
        pixels: [*c]u8 = null,
        nodes: ?*anyopaque = null,
    };

    pub const VMetrics = struct {
        ascent: c_int,
        descent: c_int,
        linegap: c_int,
    };

    pub const Error = error{
        InitFontFailed,
        PackBeginFailed,
        PackFontRangeFailed,
    };

    pub inline fn initFont(ttf_data: []const u8, offset: c_int) Error!FontInfo {
        var result: FontInfo = .{};
        if (stbtt_InitFont(@ptrCast(&result), ttf_data.ptr, offset) == 0) {
            return error.InitFontFailed;
        }
        return result;
    }

    pub inline fn scaleForMappingEmToPixels(font_info: *const FontInfo, size: f32) f32 {
        return stbtt_ScaleForMappingEmToPixels(@ptrCast(font_info), size);
    }

    pub inline fn getFontVMetrics(font_info: *const FontInfo) VMetrics {
        var result: VMetrics = undefined;
        stbtt_GetFontVMetrics(@ptrCast(font_info), &result.ascent, &result.descent, &result.linegap);
        return result;
    }

    pub inline fn getKerningTableLength(font_info: *const FontInfo) u32 {
        const result = stbtt_GetKerningTableLength(@ptrCast(font_info));
        return @intCast(result);
    }

    pub inline fn getGLyphKernAdvance(font_info: *const FontInfo, glyph1: u32, glyph2: u32) i32 {
        const result = stbtt_GetGlyphKernAdvance(@ptrCast(font_info), @intCast(glyph1), @intCast(glyph2));
        return @intCast(result);
    }

    pub fn packBegin(context: *PackContext, pixels: []u8, width: u32, height: u32, stride_in_bytes: u32, padding: u32) Error!void {
        assert(current_temp == null);
        const tmp = mem.TempArena.init(&mem.stb_arena);
        current_temp = tmp;

        assert(pixels.len == width * height);

        if (stbtt_PackBegin(
            @ptrCast(context),
            pixels.ptr,
            @intCast(width),
            @intCast(height),
            @intCast(stride_in_bytes),
            @intCast(padding),
            tmp.arena,
        ) == 0) {
            return error.PackBeginFailed;
        }
    }

    pub inline fn packFontRange(context: *PackContext, ttf_data: []const u8, font_index: u32, font_size: f32, first_unicode_char_in_range: u32, chardata_for_range: []PackedChar) Error!void {
        if (stbtt_PackFontRange(@ptrCast(context), ttf_data.ptr, @intCast(font_index), font_size, @intCast(first_unicode_char_in_range), @intCast(chardata_for_range.len), @ptrCast(chardata_for_range.ptr)) == 0) {
            return error.PackFontRangeFailed;
        }
    }

    pub fn packEnd(context: *PackContext) void {
        stbtt_PackEnd(@ptrCast(context));

        assert(current_temp != null);
        current_temp.?.release();
        current_temp = null;
    }

    pub inline fn POINT_SIZE(x: anytype) @TypeOf(-x) {
        _ = &x;
        return -x;
    }
};

const stbi_load = f("stbi_load", fn (path: [*:0]const u8, x: *c_int, y: *c_int, c: *c_int, desired_c: c_int) callconv(.c) ?[*]const u8);
const stbi_load_from_memory = f("stbi_load_from_memory", fn (buffer: [*]const u8, len: c_int, x: *c_int, y: *c_int, c: *c_int, desired_c: c_int) callconv(.c) ?[*]const u8);
const stbi_image_free = f("stbi_image_free", fn (data: [*]const u8) callconv(.c) void);

const stbtt_InitFont = f("stbtt_InitFont", fn (info: *truetype.FontInfo, data: [*]const u8, offset: c_int) callconv(.c) c_int);
const stbtt_ScaleForMappingEmToPixels = f("stbtt_ScaleForMappingEmToPixels", fn (info: *const truetype.FontInfo, pixels: f32) callconv(.c) f32);
const stbtt_GetFontVMetrics = f("stbtt_GetFontVMetrics", fn (info: *const truetype.FontInfo, ascent: *c_int, descent: *c_int, line_gap: *c_int) callconv(.c) void);
const stbtt_GetKerningTableLength = f("stbtt_GetKerningTableLength", fn (info: *const truetype.FontInfo) callconv(.c) c_int);
const stbtt_GetGlyphKernAdvance = f("stbtt_GetGlyphKernAdvance", fn (info: *const truetype.FontInfo, glyph1: c_int, glyph2: c_int) callconv(.c) c_int);
const stbtt_PackBegin = f("stbtt_PackBegin", fn (spc: *truetype.PackContext, pixels: [*]u8, width: c_int, height: c_int, stride_in_bytes: c_int, padding: c_int, alloc_context: ?*anyopaque) callconv(.c) c_int);
const stbtt_PackFontRange = f("stbtt_PackFontRange", fn (spc: *truetype.PackContext, fontdata: [*]const u8, font_index: c_int, font_size: f32, first_unicode_char_in_range: c_int, num_chars_in_range: c_int, chardata_for_range: [*]truetype.PackedChar) callconv(.c) c_int);
const stbtt_PackEnd = f("stbtt_PackEnd", fn (spc: *truetype.PackContext) callconv(.c) void);

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
    return arenaAlloc(current_temp.?.arena, size);
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

    const tmp = current_temp.?;

    if (tmp.arena.rawResize(old_slice, default_align, new_total_size)) {
        old_header_ptr.* = new_size;
        return p;
    } else {
        const new_ptr_opt = tmp.arena.rawRemap(old_slice, default_align, new_total_size);
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
    arenaFree(current_temp.?.arena, ptr);
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
