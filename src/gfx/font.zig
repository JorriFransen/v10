const std = @import("std");
const gfx = @import("../gfx.zig");
const res = @import("../resource.zig");
const mem = @import("memory");
const math = @import("../math.zig");
const stb = @import("../stb/stb.zig");

const Font = @This();
const Texture = gfx.Texture;
const Allocator = std.mem.Allocator;
const Rect = math.Rect;
const Vec2 = math.Vec2;
const Vec2u32 = math.Vec(2, u32);

const GlyphMap = std.HashMap(u32, Glyph, Glyph.MapContext, std.hash_map.default_max_load_percentage);

const assert = std.debug.assert;
const log = std.log.scoped(.font);

pub const default_ranges = [_]GlyphRange{
    .init(' ', '~'), // Basic Latin (ascii)
    .init(0x80, 0xff), // Latin-1 Supplement
};

size: f32,
scale: f32,

/// Distance of the baseline from the top of the line
base_height: f32,
line_height: f32,
line_gap: f32,

ttf_data: []const u8,
info: stb.tt.FontInfo,

ranges: []GlyphRange,
glyphs: GlyphMap,
invalid_glyph_codepoint: u32,
texture: *Texture,

/// Used for storing ranges, and the glyph hash table. When adding ranges, the glyph hash table is recreated.
arena: mem.Arena,

name: []const u8,

pub const Glyph = struct {
    pixel_width: u32,
    pixel_height: u32,

    uv_rect: Rect,

    /// x offset from the cursor, y offset from the top of the cell to the top of the uvrect
    offset: Vec2,

    /// advance after drawing this glyph
    x_advance: f32,

    stb_index: u32,

    pub const MapContext = struct {
        pub inline fn hash(_: MapContext, codepoint: u32) u64 {
            return std.hash.Wyhash.hash(0, &@as([@sizeOf(u32) / @sizeOf(u8)]u8, @bitCast(codepoint)));
        }
        pub inline fn eql(_: MapContext, a: u32, b: u32) bool {
            return a == b;
        }
    };
};

pub const GlyphRange = struct {
    first: u32,
    count: u32,

    pub fn init(first: u32, last: u32) GlyphRange {
        assert(first <= last);
        return .{ .first = first, .count = last - first + 1 };
    }
};

pub const GlyphRangesIterator = struct {
    ranges: []const GlyphRange,
    range_index: u32 = 0,
    index_in_range: u32 = 0,

    pub fn init(ranges: []const GlyphRange) GlyphRangesIterator {
        return .{
            .ranges = ranges,
        };
    }

    pub fn next(it: *GlyphRangesIterator) ?u32 {
        if (it.range_index >= it.ranges.len) return null;

        if (it.index_in_range >= it.ranges[it.range_index].count) {
            if (it.range_index + 1 >= it.ranges.len) return null;

            it.range_index += 1;
            it.index_in_range = 0;
        }

        const result = it.ranges[it.range_index].first + it.index_in_range;
        assert(result < it.ranges[it.range_index].first + it.ranges[it.range_index].count);
        it.index_in_range += 1;
        return result;
    }
};

pub const LoadOptions = struct {
    size: f32,
    ranges: []const GlyphRange = &default_ranges,
};

pub const LoadError =
    res.LoadError ||
    TtfInitError;

pub fn load(name: []const u8, options: LoadOptions) LoadError!*Font {
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

    const result = try initTtf(resource.data, .{ .name = name, .size = options.size, .ranges = options.ranges });
    try res.cache.put(name, result);
    return result;
}

pub const InitOptions = struct {
    size: f32,
    ranges: []const GlyphRange = &default_ranges,
    name: []const u8,
};

pub const TtfInitError =
    stb.tt.Error ||
    Texture.InitError ||
    mem.Arena.Error ||
    error{OutOfMemory};

pub fn initTtf(ttf_data: []const u8, options: InitOptions) TtfInitError!*Font {
    // This must be large enough to store the glyph table, and noting else can be allocated from it!
    const arena = try mem.Arena.init(.{ .virtual = .{} });

    var font_info = try stb.tt.initFont(ttf_data, 0);
    const scale = stb.tt.scaleForMappingEmToPixels(&font_info, options.size);
    const vmetrics = stb.tt.getFontVMetrics(&font_info);
    const ascent = @as(f32, @floatFromInt(vmetrics.ascent)) * scale;
    const descent = @as(f32, @floatFromInt(vmetrics.descent)) * scale;
    const line_gap = @as(f32, @floatFromInt(vmetrics.linegap)) * scale;
    const base = ascent;

    const result = try mem.font_arena.allocator().create(Font);
    result.name = options.name;
    result.arena = arena;
    result.ttf_data = ttf_data;
    result.info = font_info;
    result.size = options.size;
    result.scale = scale;
    result.base_height = base;
    result.line_height = ascent - descent;
    result.line_gap = line_gap;
    result.arena = arena;
    result.base_height = base;
    result.ranges = &.{};

    try result.packRanges(options.ranges);
    return result;
}

pub fn deinit(this: *Font) void {
    this.texture.deinit();
    this.arena.deinit();
}

pub fn packRanges(this: *Font, ranges: []const GlyphRange) !void {
    const bitmap_size = 1024;
    var bitmap: [bitmap_size * bitmap_size]u8 = undefined;
    @memset(bitmap[0..], 0);

    if (this.ranges.len > 0) {
        this.texture.deinit();
    }
    this.arena.used = 0;

    this.ranges = try this.arena.allocator().alloc(GlyphRange, ranges.len);
    @memcpy(this.ranges, ranges);
    var total_glyph_count: u32 = 0;
    for (this.ranges) |r| total_glyph_count += r.count;

    this.glyphs = GlyphMap.init(this.arena.allocator());
    try this.glyphs.ensureTotalCapacity(total_glyph_count);

    var tmp = mem.get_temp();
    defer tmp.release();

    var pack_context: stb.c.stbrp_context = undefined;
    var pack_nodes: [bitmap_size]stb.c.stbrp_node = undefined;
    stb.c.stbrp_init_target(&pack_context, bitmap_size, bitmap_size, &pack_nodes, bitmap_size);
    const rects = try tmp.allocator().alloc(stb.c.stbrp_rect, total_glyph_count + 1); // + 1 for invalid glyph
    const codepoints = try tmp.allocator().alloc(u32, total_glyph_count + 1);

    // Invalid glyph
    const invalid_glyph_codepoint = 0;
    rects[0] = makeGlyphPackRect(this, invalid_glyph_codepoint);
    assert(rects[0].id >= 0);
    codepoints[0] = invalid_glyph_codepoint;

    var range_it = GlyphRangesIterator.init(ranges);
    var used_glyph_count: usize = 1;
    while (range_it.next()) |codepoint| {
        const glyph_rect = makeGlyphPackRect(this, codepoint);
        if (glyph_rect.id != 0) {
            rects[used_glyph_count] = glyph_rect;
            codepoints[used_glyph_count] = codepoint;
            used_glyph_count += 1;
        }
    }

    // TODO: Check result
    _ = stb.c.stbrp_pack_rects(&pack_context, rects.ptr, @intCast(used_glyph_count));

    for (rects[0..used_glyph_count], codepoints[0..used_glyph_count]) |rect, codepoint| {
        assert(rect.was_packed != 0);
        try this.renderPackedGlyph(rect, codepoint, &bitmap, bitmap_size);
    }

    const texture = try Texture.init(.{
        .format = .u8_u_r,
        .size = Vec2u32.scalar(bitmap_size),
        .data = &bitmap,
    }, .{ .filter = .nearest, .debug_name = this.name });

    this.texture = texture;
    this.invalid_glyph_codepoint = invalid_glyph_codepoint;
}

pub fn getGlyph(this: *Font, codepoint: u32) *const Glyph {
    if (this.glyphs.getPtr(codepoint)) |g| return g;
    return this.glyphs.getPtr(this.invalid_glyph_codepoint) orelse @panic("Missing invalid glyph");
}

pub fn kernAdvance(this: *Font, glyph1: *const Glyph, glyph2: *const Glyph) ?f32 {
    const i_kern = stb.tt.getGlyphKernAdvance(&this.info, glyph1.stb_index, glyph2.stb_index);
    if (i_kern == 0) return null;
    return @as(f32, @floatFromInt(i_kern)) * this.scale;
}

fn makeGlyphPackRect(font: *const Font, codepoint: u32) stb.c.stbrp_rect {
    const glyph_index = stb.tt.findGlyphIndex(&font.info, codepoint);
    const box = stb.tt.getGlyphBitmapBox(&font.info, glyph_index, font.scale, font.scale);
    return .{ .id = @intCast(glyph_index), .w = (box.x1 - box.x0) + 1, .h = (box.y1 - box.y0) + 1 };
}

/// This also adds it to the glyph hash map
fn renderPackedGlyph(this: *Font, rect: stb.c.stbrp_rect, codepoint: u32, bitmap: []u8, stride: c_int) !void {
    const glyph_index: u32 = @intCast(rect.id);

    const bitmap_offset: usize = @intCast((stride * rect.y) + rect.x);
    stb.tt.makeGlyphBitmap(&this.info, bitmap[bitmap_offset..].ptr, rect.w, rect.h, stride, this.scale, this.scale, glyph_index);

    const hmetrics = stb.tt.getGlyphHMetrics(&this.info, glyph_index);
    const x_advance = this.scale * @as(f32, @floatFromInt(hmetrics.x_advance));

    const box = stb.tt.getGlyphBitmapBox(&this.info, glyph_index, this.scale, this.scale);

    const pixel_width = rect.w - 1;
    const pixel_height = rect.h - 1;
    const fstride: f32 = @floatFromInt(stride);
    const glyph = Glyph{
        .pixel_width = @intCast(pixel_width),
        .pixel_height = @intCast(pixel_height),
        .uv_rect = .{
            .pos = .{
                .x = @as(f32, @floatFromInt(rect.x)) / fstride,
                .y = @as(f32, @floatFromInt(rect.y)) / fstride,
            },
            .size = .{
                .x = @as(f32, @floatFromInt(pixel_width)) / fstride,
                .y = @as(f32, @floatFromInt(pixel_height)) / fstride,
            },
        },
        .offset = .{
            .x = @floatFromInt(box.x0),
            .y = @as(f32, @floatFromInt(box.y0)) + this.base_height,
        },
        .x_advance = x_advance,
        .stb_index = glyph_index,
    };

    try this.glyphs.putNoClobber(codepoint, glyph);
}
