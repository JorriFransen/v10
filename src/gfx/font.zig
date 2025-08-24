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

texture: *Texture,
glyphs: GlyphMap,
invalid_glyph: ?Glyph = null,
kern_info: KernMap,

/// Distance of the baseline from the top of the line
base_height: f32,
line_height: f32,
line_gap: f32,

/// Used for the glyph and kerning tables, make sure they never free any memory
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
    var tmp = mem.get_temp();
    defer tmp.release();

    const resource = try res.load(tmp.allocator(), name);
    switch (resource.type) {
        .ttf => {}, // ok
        else => {
            log.err("Invalid resource type for font: '{s}' ({s})", .{ name, @tagName(resource.type) });
            return error.UnsupportedType;
        },
    }

    return try initTtf(device, resource.data, size);
}

pub const TtfInitError =
    stb.truetype.Error ||
    Texture.InitError ||
    mem.Arena.Error ||
    error{OutOfMemory};

pub fn initTtf(device: *Device, ttf_data: []const u8, size: f32) TtfInitError!*Font {

    // TODO: Calculate or iterate on bitmap size
    const bitmap_size = Vec2u32.new(1024, 1024);
    var bitmap: [bitmap_size.x * bitmap_size.y]u8 = undefined;

    const first_char: u32 = ' ';
    const last_char: u32 = '~';
    const char_count = (last_char - first_char) + 1;

    const font_info = try stb.truetype.initFont(ttf_data, 0);

    const scale = stb.truetype.scaleForMappingEmToPixels(&font_info, size);

    const vmetrics = stb.truetype.getFontVMetrics(&font_info);
    const ascent = @as(f32, @floatFromInt(vmetrics.ascent)) * scale;
    const descent = @as(f32, @floatFromInt(vmetrics.descent)) * scale;
    const linegap = @as(f32, @floatFromInt(vmetrics.linegap)) * scale;
    const base = ascent;
    const line_height = ascent + -descent;

    var char_data: [char_count]stb.truetype.PackedChar = undefined;
    var context: stb.truetype.PackContext = undefined;
    try stb.truetype.packBegin(&context, &bitmap, bitmap_size.x, bitmap_size.y, 0, 1);
    try stb.truetype.packFontRange(&context, ttf_data, 0, stb.truetype.POINT_SIZE(size), first_char, &char_data);
    stb.truetype.packEnd(&context);

    const texture = try Texture.init(device, .{
        .format = .u8_u_r,
        .size = bitmap_size,
        .data = &bitmap,
    }, .{ .filter = .nearest });

    // This must be large enough to store the glyph and kerning tables, or we need to move to a different (chunked?) allocator.
    var arena = try mem.Arena.init(.{ .virtual = .{} });

    var glyphs = GlyphMap.init(arena.allocator());
    try glyphs.ensureTotalCapacity(@intCast(char_data.len));

    for (char_data, 0..char_count) |char_info, char_i| {
        const codepoint: u32 = first_char + @as(u32, @intCast(char_i));

        const pixel_width = char_info.x1 - char_info.x0;
        const pixel_height = char_info.y1 - char_info.y0;

        try glyphs.putNoClobber(@as(u32, @intCast(codepoint)), .{
            .pixel_width = pixel_width,
            .pixel_height = pixel_height,
            .uv_rect = .{
                .pos = .{
                    .x = @as(f32, @floatFromInt(char_info.x0)) / bitmap_size.x,
                    .y = @as(f32, @floatFromInt(char_info.y0)) / bitmap_size.y,
                },
                .size = .{
                    .x = @as(f32, @floatFromInt(pixel_width)) / bitmap_size.x,
                    .y = @as(f32, @floatFromInt(pixel_height)) / bitmap_size.y,
                },
            },
            .offset = .{
                .x = char_info.xoff,
                .y = char_info.yoff + ascent,
            },
            .x_advance = char_info.xadvance,
        });
    }

    // This only works for old school kern tables
    const kern_count = stb.truetype.getKerningTableLength(&font_info);

    var kern_info = KernMap.init(arena.allocator());
    if (kern_count != 0) try kern_info.ensureTotalCapacity(kern_count);

    // TODO: make this work with more complex glyph ranges
    for (first_char..last_char + 1) |_a| {
        const a: u32 = @intCast(_a);
        for (first_char..last_char + 1) |_b| {
            const b: u32 = @intCast(_b);
            if (a == b) continue;

            const kern_advance = stb.truetype.getGLyphKernAdvance(&font_info, a, b);
            if (kern_advance != 0) {
                try kern_info.put(.{ .a = a, .b = b }, @as(f32, @floatFromInt(kern_advance)) * scale);
            }
        }
    }

    const result = try mem.font_arena.allocator().create(Font);
    result.* = .{
        .texture = texture,
        .glyphs = glyphs,
        .invalid_glyph = null,
        .kern_info = kern_info,
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
