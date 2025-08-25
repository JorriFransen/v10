const std = @import("std");
const gfx = @import("../gfx.zig");
const res = @import("../resource.zig");
const mem = @import("memory");
const math = @import("../math.zig");
const stb = @import("../stb/stb.zig");

const Font = @This();
const Texture = gfx.Texture;
const Device = gfx.Device;
const Allocator = std.mem.Allocator;
const Rect = math.Rect;
const Vec2 = math.Vec2;
const Vec2u32 = math.Vec(2, u32);

const GlyphMap = std.HashMap(u32, Glyph, Glyph.MapContext, std.hash_map.default_max_load_percentage);
const KernMap = std.HashMap(KernPair, f32, KernPair.MapContext, std.hash_map.default_max_load_percentage);

const assert = std.debug.assert;
const log = std.log.scoped(.font);

size: f32,
scale: f32,
texture: *Texture,
glyphs: GlyphMap,
invalid_glyph: ?Glyph = null,

/// Distance of the baseline from the top of the line
base_height: f32,
line_height: f32,
line_gap: f32,

ttf_data: []const u8,
info: stb.truetype.FontInfo,
/// Used for the glyph cache hash table. Dont'f free and don't use for anything else!
arena: mem.Arena,

pub const Glyph = struct {
    pixel_width: u32,
    pixel_height: u32,

    uv_rect: Rect,

    /// x offset from the cursor, y offset from the top of the cell to the top of the uvrect
    offset: Vec2,

    /// advance after drawing this glyph
    x_advance: f32,

    pub const MapContext = struct {
        pub inline fn hash(_: MapContext, codepoint: u32) u64 {
            return std.hash.Wyhash.hash(0, &@as([@sizeOf(u32) / @sizeOf(u8)]u8, @bitCast(codepoint)));
        }
        pub inline fn eql(_: MapContext, a: u32, b: u32) bool {
            return a == b;
        }
    };
};

pub const KernPair = packed struct(u64) {
    a: u32,
    b: u32,

    pub const MapContext = struct {
        pub inline fn hash(_: MapContext, pair: KernPair) u64 {
            return @bitCast(pair);
        }
        pub inline fn eql(_: MapContext, a: KernPair, b: KernPair) bool {
            return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
        }
    };
};

pub const LoadError =
    res.LoadError ||
    TtfInitError;

pub fn load(device: *Device, name: []const u8, size: f32) LoadError!*Font {
    // TODO: hash with size
    if (res.cache.get(name)) |ptr| {
        const font: *Font = @ptrCast(@alignCast(ptr));
        log.info("Loading cached font: '{s}' - {}", .{ name, font.size });
        return font;
    }

    const resource = try res.load(mem.font_arena.allocator(), name);
    switch (resource.type) {
        .ttf => {}, // ok
        else => {
            log.err("Invalid resource type for font: '{s}' ({s})", .{ name, @tagName(resource.type) });
            return error.UnsupportedType;
        },
    }

    const result = try initTtf(device, resource.data, size, name);
    try res.cache.put(name, result);
    return result;
}

pub const TtfInitError =
    stb.truetype.Error ||
    Texture.InitError ||
    mem.Arena.Error ||
    error{OutOfMemory};

pub fn initTtf(device: *Device, ttf_data: []const u8, size: f32, name: []const u8) TtfInitError!*Font {
    const bitmap_size = 512;
    var bitmap: [bitmap_size * bitmap_size]u8 = undefined;
    @memset(bitmap[0..], 0);

    const first_char: u32 = ' ';
    const last_char: u32 = '~';
    const char_count = (last_char - first_char) + 1;

    assert(stb.current_temp == null);
    const stb_tmp = mem.TempArena.init(&mem.stb_arena);
    stb.current_temp = stb_tmp;

    var font_info = try stb.truetype.initFont(ttf_data, 0);
    font_info.userdata = stb_tmp.arena; // used by stbtt_MakeCodepointBitmap

    const scale = stb.truetype.scaleForMappingEmToPixels(&font_info, size);

    const vmetrics = stb.truetype.getFontVMetrics(&font_info);
    const ascent = @as(f32, @floatFromInt(vmetrics.ascent)) * scale;
    const descent = @as(f32, @floatFromInt(vmetrics.descent)) * scale;
    const linegap = @as(f32, @floatFromInt(vmetrics.linegap)) * scale;
    const base = ascent;
    const line_height = ascent + -descent;

    // This must be large enough to store the glyph table, and we can't allocate anything else from it!
    var arena = try mem.Arena.init(.{ .virtual = .{} });

    var glyphs = GlyphMap.init(arena.allocator());
    try glyphs.ensureTotalCapacity(char_count);

    var tmp = mem.get_temp();
    defer tmp.release();

    var pack_context: stb.c.stbrp_context = undefined;
    var pack_nodes: [bitmap_size]stb.c.stbrp_node = undefined;
    stb.c.stbrp_init_target(&pack_context, bitmap_size, bitmap_size, &pack_nodes, bitmap_size);
    const rects = try tmp.allocator().alloc(stb.c.stbrp_rect, char_count);

    for (rects, 0..char_count) |*rect, i| {
        const codepoint: u32 = @intCast(i + first_char);
        var x0: c_int = undefined;
        var y0: c_int = undefined;
        var x1: c_int = undefined;
        var y1: c_int = undefined;
        const glyph_index = stb.c.stbtt_FindGlyphIndex(@ptrCast(&font_info), @intCast(codepoint));
        stb.c.stbtt_GetGlyphBitmapBox(@ptrCast(&font_info), glyph_index, scale, scale, &x0, &y0, &x1, &y1);

        rect.* = .{ .id = glyph_index, .w = (x1 - x0) + 1, .h = (y1 - y0) + 1 };
    }

    _ = stb.c.stbrp_pack_rects(&pack_context, rects.ptr, @intCast(rects.len));

    const stride = bitmap_size;
    for (rects, 0..) |rect, i| {
        assert(rect.was_packed != 0);

        const codepoint: u32 = @intCast(i + first_char);
        const bitmap_offset: usize = @intCast((stride * rect.y) + rect.x);
        stb.c.stbtt_MakeCodepointBitmap(@ptrCast(&font_info), &bitmap[bitmap_offset], rect.w, rect.h, stride, scale, scale, @intCast(codepoint));

        var i_x_advance: c_int = undefined;
        var i_lsb: c_int = undefined;
        stb.c.stbtt_GetCodepointHMetrics(@ptrCast(&font_info), @intCast(codepoint), &i_x_advance, &i_lsb);
        const x_advance = scale * @as(f32, @floatFromInt(i_x_advance));

        var x0: c_int = undefined;
        var y0: c_int = undefined;
        var x1: c_int = undefined;
        var y1: c_int = undefined;
        stb.c.stbtt_GetGlyphBitmapBox(@ptrCast(&font_info), rect.id, scale, scale, &x0, &y0, &x1, &y1);

        const pixel_width = rect.w - 1;
        const pixel_height = rect.h - 1;
        const glyph = Glyph{
            .pixel_width = @intCast(pixel_width),
            .pixel_height = @intCast(pixel_height),
            .uv_rect = .{
                .pos = .{
                    .x = @as(f32, @floatFromInt(rect.x)) / bitmap_size,
                    .y = @as(f32, @floatFromInt(rect.y)) / bitmap_size,
                },
                .size = .{
                    .x = @as(f32, @floatFromInt(pixel_width)) / bitmap_size,
                    .y = @as(f32, @floatFromInt(pixel_height)) / bitmap_size,
                },
            },
            .offset = .{
                .x = @floatFromInt(x0),
                .y = @as(f32, @floatFromInt(y0)) + ascent,
            },
            .x_advance = x_advance,
        };

        try glyphs.putNoClobber(codepoint, glyph);
    }

    const texture = try Texture.init(device, .{
        .format = .u8_u_r,
        .size = Vec2u32.scalar(bitmap_size),
        .data = &bitmap,
    }, .{ .filter = .nearest, .debug_name = name });

    stb.current_temp = null;

    const result = try mem.font_arena.allocator().create(Font);
    result.* = .{
        .ttf_data = ttf_data,
        .info = font_info,
        .size = size,
        .scale = scale,
        .texture = texture,
        .glyphs = glyphs,
        .invalid_glyph = null,
        .base_height = base,
        .line_height = line_height,
        .line_gap = linegap,
        .arena = arena,
    };
    return result;
}

pub fn deinit(this: *Font, device: *Device) void {
    this.texture.deinit(device);
    this.arena.deinit();
}

pub fn kernAdvance(this: *Font, codepoint_a: u32, codepoint_b: u32) ?f32 {
    const i_kern = stb.truetype.getCodepointKernAdvance(&this.info, codepoint_a, codepoint_b);
    if (i_kern == 0) return null;
    return @as(f32, @floatFromInt(i_kern)) * this.scale;
}
