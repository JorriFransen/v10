const std = @import("std");
const gfx = @import("../gfx.zig");
const resource = @import("../resource.zig");
const mem = @import("memory");
const math = @import("../math.zig");

const Font = @This();
const Texture = gfx.Texture;
const Device = gfx.Device;
const Allocator = std.mem.Allocator;
const Rect = math.Rect;

const GlyphMap = std.HashMap(u32, Glyph, Glyph.MapContext, std.hash_map.default_max_load_percentage);

const assert = std.debug.assert;
const log = std.log.scoped(.font);

// TODO: Pointer?
texture: Texture,
glyphs: GlyphMap,
invalid_glyph: ?Glyph = null,

line_height: u32,
base_height: u32,

pub const Glyph = struct {
    pixel_width: u32,
    pixel_height: u32,

    uv_rect: Rect,

    /// offset from the cursor
    x_offset: i32,

    /// offset from the top of the cell to the top ot the uvrect
    y_offset: i32,

    /// advance after drawing this glyph
    x_advance: i32,

    pub const MapContext = struct {
        pub inline fn hash(_: MapContext, codepoint: u32) u64 {
            return std.hash.Wyhash.hash(0, &@as([@sizeOf(u32) / @sizeOf(u8)]u8, @bitCast(codepoint)));
        }
        pub inline fn eql(_: MapContext, a: u32, b: u32) bool {
            return a == b;
        }
    };
};

pub const LoadFontError = error{
    UnsupportedFontType,
    UnsupportedAngelcodeFNTFeature,
} ||
    AngelcodeFNTParseError ||
    Texture.TextureLoadError;

pub fn load(device: *Device, name: []const u8) LoadFontError!Font {
    var fnt_file_arena = mem.get_temp();

    const fnt_file = try resource.load(fnt_file_arena.allocator(), name);
    if (fnt_file != .angelfont_file) {
        log.err("Unsupported font type: '{s}", .{name});
        return error.UnsupportedFontType;
    }

    var fnt_info_arena = mem.get_scratch(fnt_file_arena.arena);
    defer fnt_info_arena.release();

    const font_info = try parseAngelcodeFNT(fnt_info_arena.allocator(), fnt_file.angelfont_file.data, fnt_file.angelfont_file.name);
    fnt_file_arena.release();

    if (!font_info.unicode) {
        log.err("Only unicode BMFonts are supported", .{});
        return error.UnsupportedAngelcodeFNTFeature;
    }

    if (font_info.pages.len != 1) {
        log.err("Only 1-page BMFonts are supported", .{});
        return error.UnsupportedAngelcodeFNTFeature;
    }

    if (font_info.@"packed") {
        log.err("Only 1-channel BMFonts are supported", .{});
        return error.UnsupportedAngelcodeFNTFeature;
    }

    if (!(font_info.alpha_channel == .glyph and
        font_info.red_channel == .zero and
        font_info.green_channel == .zero and
        font_info.blue_channel == .zero))
    {
        log.err("Only 1-channel BMFonts are supported", .{});
        return error.UnsupportedAngelcodeFNTFeature;
    }

    assert(font_info.pages.len == 1);
    const texture = try Texture.load(device, font_info.pages[0], .{ .format = .u8_u_r, .filter = .nearest });

    // TODO: Allocator!
    var glyphs = GlyphMap.init(mem.common_arena.allocator());
    try glyphs.ensureTotalCapacity(@intCast(font_info.chars.len));

    for (font_info.chars) |char| {
        assert(char.page == 0); // TODO: Handle pages
        try glyphs.putNoClobber(char.id, char.toGlyph(&texture));
    }

    const invalid_glyph = if (font_info.invalid_char) |ic| ic.toGlyph(&texture) else null;

    return init(texture, glyphs, invalid_glyph, font_info.line_height, font_info.base);
}

// TODO: Return error
pub fn init(texture: Texture, glyphs: GlyphMap, invalid_glyph: ?Glyph, line_height: u32, base_height: u32) !Font {
    return .{
        .texture = texture,
        .glyphs = glyphs,
        .line_height = line_height,
        .base_height = base_height,
        .invalid_glyph = invalid_glyph,
    };
}

pub fn deinit(this: *Font, device: *Device) void {
    this.texture.deinit(device);
}

const AngelcodeFNTInfo = struct {
    // info tag
    face: []const u8,
    size: i16 = 0,
    bold: bool = false,
    italic: bool = false,
    charset: []const u8,
    unicode: bool = false,
    stretch_h: u16 = 0,
    smooth: bool = false,
    aa: bool = false,
    pad_up: u8 = 0,
    pad_right: u8 = 0,
    pad_down: u8 = 0,
    pad_left: u8 = 0,
    space_h: u8 = 0,
    space_v: u8 = 0,
    outline: u8 = 0,

    // common tag
    line_height: u16 = 0,
    base: u16 = 0,
    scale_w: i16 = 0,
    scale_h: i16 = 0,
    @"packed": bool = false,
    alpha_channel: ChannelType = .zero,
    red_channel: ChannelType = .zero,
    green_channel: ChannelType = .zero,
    blue_channel: ChannelType = .zero,

    pages: []const []const u8 = &.{},
    chars: []const Char = &.{},
    invalid_char: ?Char = null,

    pub const ChannelType = enum(u3) {
        glyph = 0,
        outline = 1,
        glyph_and_outline = 2,
        zero = 3,
        one = 4,
    };

    pub const Char = struct {
        id: u32,
        x: u16,
        y: u16,
        width: u16,
        height: u16,
        x_offset: i16,
        y_offset: i16,
        xadvance: u16,
        page: u8,
        channel: CharChannel,

        pub fn toGlyph(this: Char, texture: *const Texture) Glyph {
            assert(this.page == 0);
            const page_size = texture.getSize();
            return .{
                .pixel_width = this.width,
                .pixel_height = this.height,
                .uv_rect = Rect{
                    .pos = .{
                        .x = @as(f32, @floatFromInt(this.x)) / page_size.x,
                        .y = @as(f32, @floatFromInt(this.y)) / page_size.y,
                    },
                    .size = .{
                        .x = @as(f32, @floatFromInt(this.width)) / page_size.x,
                        .y = @as(f32, @floatFromInt(this.height)) / page_size.y,
                    },
                },
                .x_offset = this.x_offset,
                .y_offset = this.y_offset,
                .x_advance = this.xadvance,
            };
        }
    };

    pub const CharChannel = packed struct(u4) {
        blue: bool,
        geen: bool,
        red: bool,
        alpha: bool,

        const all: @This() = .{ .blue = true, .green = true, .red = true, .alpha = true };
    };

    pub fn free(this: *AngelcodeFNTInfo, allocator: *Allocator) void {
        allocator.free(this.face);
        allocator.free(this.charset);

        for (this.faces) |face| allocator.free(face);
        allocator.free(this.faces);
    }
};

pub const AngelcodeFNTParseError = error{
    InvalidTag,
    InvalidKey,
    InvalidPageId,
    MissingPageId,
    InvalidPagePath,
    InvalidToken,
} ||
    ParseStringError ||
    ParseChannelTypeError ||
    Allocator.Error ||
    std.fmt.ParseIntError;

fn parseAngelcodeFNT(allocator: Allocator, text: []const u8, filename: []const u8) AngelcodeFNTParseError!AngelcodeFNTInfo {
    var result = AngelcodeFNTInfo{
        .face = "",
        .charset = "",
    };

    var tmp = mem.get_scratch(@ptrCast(@alignCast(allocator.ptr)));
    defer tmp.release();

    var page_count: i16 = 0;
    var char_count: u32 = 0;
    var pages = try std.ArrayListUnmanaged([]const u8).initCapacity(tmp.allocator(), 1);
    var chars = try std.ArrayListUnmanaged(AngelcodeFNTInfo.Char).initCapacity(tmp.allocator(), 256);

    var line_it = std.mem.tokenizeAny(u8, text, "\r\n");
    while (line_it.next()) |initial_line| {
        var line = initial_line;

        if (eat(&line, "info")) {
            while (line.len > 0) {
                if (eat(&line, "face=")) {
                    result.face = try parseString(&line);
                } else if (eat(&line, "size=")) {
                    result.size = try parseInt(i16, &line);
                } else if (eat(&line, "bold=")) {
                    result.bold = try parseBool(&line);
                } else if (eat(&line, "italic=")) {
                    result.italic = try parseBool(&line);
                } else if (eat(&line, "charset=")) {
                    result.charset = try parseString(&line);
                } else if (eat(&line, "unicode=")) {
                    result.unicode = try parseBool(&line);
                } else if (eat(&line, "stretchH=")) {
                    result.stretch_h = try parseInt(u16, &line);
                } else if (eat(&line, "smooth=")) {
                    result.smooth = try parseBool(&line);
                } else if (eat(&line, "aa=")) {
                    result.aa = try parseBool(&line);
                } else if (eat(&line, "padding=")) {
                    result.pad_up = try parseInt(u8, &line);
                    try expect(&line, ",");
                    result.pad_right = try parseInt(u8, &line);
                    try expect(&line, ",");
                    result.pad_down = try parseInt(u8, &line);
                    try expect(&line, ",");
                    result.pad_left = try parseInt(u8, &line);
                } else if (eat(&line, "spacing=")) {
                    result.space_h = try parseInt(u8, &line);
                    try expect(&line, ",");
                    result.space_v = try parseInt(u8, &line);
                } else if (eat(&line, "outline=")) {
                    result.outline = try parseInt(u8, &line);
                } else {
                    log.err("Invalid key in BMFont; file: '{s}', key: '{s}'", .{ filename, line });
                    return error.InvalidKey;
                }
            }
        } else if (eat(&line, "common")) {
            while (line.len > 0) {
                if (eat(&line, "lineHeight=")) {
                    result.line_height = try parseInt(u16, &line);
                } else if (eat(&line, "base=")) {
                    result.base = try parseInt(u16, &line);
                } else if (eat(&line, "scaleW=")) {
                    result.scale_w = try parseInt(i16, &line);
                } else if (eat(&line, "scaleH=")) {
                    result.scale_h = try parseInt(i16, &line);
                } else if (eat(&line, "pages=")) {
                    page_count = try parseInt(i16, &line);
                } else if (eat(&line, "packed=")) {
                    result.@"packed" = try parseBool(&line);
                } else if (eat(&line, "alphaChnl=")) {
                    result.alpha_channel = try parseChannelType(&line);
                } else if (eat(&line, "redChnl=")) {
                    result.red_channel = try parseChannelType(&line);
                } else if (eat(&line, "greenChnl=")) {
                    result.green_channel = try parseChannelType(&line);
                } else if (eat(&line, "blueChnl=")) {
                    result.blue_channel = try parseChannelType(&line);
                } else {
                    log.err("Invalid key in BMFont; file: '{s}', key: '{s}'", .{ filename, line });
                    return error.InvalidKey;
                }
            }
        } else if (eat(&line, "page")) {
            var id_opt: ?u32 = null;
            var page_file_name: []const u8 = "";

            while (line.len > 0) {
                if (eat(&line, "id=")) {
                    id_opt = try parseInt(u32, &line);
                } else if (eat(&line, "file=")) {
                    page_file_name = try parseString(&line);
                } else {
                    log.err("Invalid key in BMFont; file: '{s}', key: '{s}'", .{ filename, line });
                    return error.InvalidKey;
                }
            }

            if (id_opt) |id| {
                if (id != pages.items.len) {
                    log.err("Non consecutive page id in BMFont; file: '{s}', id: '{}'", .{ filename, id });
                    return error.InvalidPageId;
                }

                const dir_name = std.fs.path.dirname(filename) orelse ".";
                const page_file_path = try std.fs.path.join(allocator, &.{ dir_name, page_file_name });

                // TODO: Move this to load after we parsed
                if (!resource.exists(page_file_path)) {
                    log.err("Invalid page path in BMFont; file: '{s}', path: '{s}'", .{ filename, page_file_path });
                    return error.InvalidPagePath;
                }

                try pages.append(tmp.allocator(), page_file_path);
            } else {
                log.err("Missing page id in BMFont; file: '{s}'", .{filename});
                return error.MissingPageId;
            }
        } else if (eat(&line, "chars")) {
            while (line.len > 0) {
                if (eat(&line, "count=")) {
                    char_count = try parseInt(u32, &line);
                } else {
                    log.err("Invalid key in BMFont; file: '{s}', key: '{s}'", .{ filename, line });
                    return error.InvalidKey;
                }
            }
        } else if (eat(&line, "char")) {
            var signed_id: i64 = -1;
            var x: u16 = undefined;
            var y: u16 = undefined;
            var width: u16 = undefined;
            var height: u16 = undefined;
            var x_offset: i16 = undefined;
            var y_offset: i16 = undefined;
            var xadvance: u16 = undefined;
            var page: u8 = undefined;
            var channel: AngelcodeFNTInfo.CharChannel = undefined;

            while (line.len > 0) {
                if (eat(&line, "id=")) {
                    signed_id = try parseInt(i64, &line);
                } else if (eat(&line, "x=")) {
                    x = try parseInt(u16, &line);
                } else if (eat(&line, "y=")) {
                    y = try parseInt(u16, &line);
                } else if (eat(&line, "width=")) {
                    width = try parseInt(u16, &line);
                } else if (eat(&line, "height=")) {
                    height = try parseInt(u16, &line);
                } else if (eat(&line, "xoffset=")) {
                    x_offset = try parseInt(i16, &line);
                } else if (eat(&line, "yoffset=")) {
                    y_offset = try parseInt(i16, &line);
                } else if (eat(&line, "xadvance=")) {
                    xadvance = try parseInt(u16, &line);
                } else if (eat(&line, "page=")) {
                    page = try parseInt(u8, &line);
                } else if (eat(&line, "chnl=")) {
                    const channel_int = try parseInt(u4, &line);
                    channel = @bitCast(channel_int);
                } else {
                    log.err("Invalid key in BMFont; file: '{s}', key: '{s}'", .{ filename, line });
                    return error.InvalidKey;
                }
            }

            var char = AngelcodeFNTInfo.Char{
                .id = 0,
                .x = x,
                .y = y,
                .width = width,
                .height = height,
                .x_offset = x_offset,
                .y_offset = y_offset,
                .xadvance = xadvance,
                .page = page,
                .channel = channel,
            };

            if (signed_id >= 0) {
                char.id = @intCast(signed_id);
                try chars.append(tmp.allocator(), char);
            } else {
                result.invalid_char = char;
            }
        } else {
            log.err("Invalid tag in BMFont; file: '{s}', tag: '{s}'", .{ filename, line });
            return error.InvalidTag;
        }
    }

    result.face = try copyString(allocator, result.face);
    result.charset = try copyString(allocator, result.charset);

    assert(page_count == pages.items.len);
    result.pages = try copySlice([]const u8, allocator, pages.items);

    assert(char_count == if (result.invalid_char == null) chars.items.len else chars.items.len + 1);
    result.chars = try copySlice(AngelcodeFNTInfo.Char, allocator, chars.items);

    return result;
}

fn copySlice(comptime T: type, allocator: Allocator, slice: []const T) ![]const T {
    const result = try allocator.alloc(T, slice.len);
    @memcpy(result, slice);
    return result;
}

fn copyString(allocator: Allocator, str: []const u8) ![]const u8 {
    if (str.len == 0) return "";
    const result = try allocator.alloc(u8, str.len);
    @memcpy(result, str);
    return result;
}

fn parseInt(comptime T: type, str: *[]const u8) std.fmt.ParseIntError!T {
    var len: usize = 0;
    if (str.*.len > 1 and str.*[0] == '-') {
        len += 1;
    }
    while (len < str.*.len and std.ascii.isDigit(str.*[len])) {
        len += 1;
    }

    const sub = str.*[0..len];
    const result = try std.fmt.parseInt(T, sub, 10);
    str.* = stripLeft(str.*[sub.len..]);
    return result;
}

fn parseBool(str: *[]const u8) std.fmt.ParseIntError!bool {
    const int = try parseInt(i32, str);
    return int != 0;
}

pub const ParseChannelTypeError = error{
    InvalidChannelValue,
} || std.fmt.ParseIntError;

fn parseChannelType(str: *[]const u8) ParseChannelTypeError!AngelcodeFNTInfo.ChannelType {
    const int = try parseInt(i16, str);
    if (std.enums.fromInt(AngelcodeFNTInfo.ChannelType, int)) |e| return e;
    return error.InvalidChannelValue;
}

pub const ParseStringError = error{
    InvalidString,
};

fn parseString(str: *[]const u8) ParseStringError![]const u8 {
    const initial_str = str.*;
    const close_quote = eatNoStrip(str, "\"");

    var len: usize = 0;
    if (close_quote) {
        while (len < str.*.len and str.*[len] != '"') {
            len += 1;
        }
    } else {
        while (len < str.*.len and !std.ascii.isWhitespace(str.*[len])) {
            len += 1;
        }
    }

    const result = str.*[0..len];

    if (close_quote) {
        if (len >= str.*.len or str.*[len] != '"') {
            log.err("Missing closing '\"' in BMFont file (while parsing string: '{s}')", .{initial_str});
            return error.InvalidString;
        }

        len += 1;
    }
    str.* = stripLeft(str.*[len..]);

    return result;
}

fn eat(str: *[]const u8, start: []const u8) bool {
    if (std.mem.startsWith(u8, str.*, start)) {
        str.* = stripLeft(str.*[start.len..]);
        return true;
    }
    return false;
}

fn eatNoStrip(str: *[]const u8, start: []const u8) bool {
    if (std.mem.startsWith(u8, str.*, start)) {
        str.* = str.*[start.len..];
        return true;
    }
    return false;
}

fn expect(str: *[]const u8, start: []const u8) error{InvalidToken}!void {
    if (!eat(str, start)) {
        log.err("Invalid token in BMFont file; expected: '{s}', actual: '{s}'", .{ start, str.* });
        return error.InvalidToken;
    }
}

fn stripLeft(str: []const u8) []const u8 {
    for (str, 0..) |char, i| {
        if (!std.ascii.isWhitespace(char)) return str[i..];
    }
    return "";
}
