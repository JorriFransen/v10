const std = @import("std");
const gfx = @import("../gfx.zig");
const resource = @import("../resource.zig");
const mem = @import("memory");

const Font = @This();
const Texture = gfx.Texture;
const Device = gfx.Device;
const Allocator = std.mem.Allocator;

const assert = std.debug.assert;
const log = std.log.scoped(.font);

// TODO: Pointer?
texture: Texture,

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

    log.debug("angel info: {any}", .{font_info});

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

    // TODO: Copy font/char metrics to our format
    return .{
        .texture = texture,
    };
}

// TODO: Return error
pub fn init(texture: *const Texture) !Font {
    return .{
        .texture = texture,
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
    line_height: i16 = 0,
    base: i16 = 0,
    scale_w: i16 = 0,
    scale_h: i16 = 0,
    @"packed": bool = false,
    alpha_channel: ChannelType = .zero,
    red_channel: ChannelType = .zero,
    green_channel: ChannelType = .zero,
    blue_channel: ChannelType = .zero,

    pages: []const []const u8 = &.{},
    chars: []const Char = &.{},

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
                    result.line_height = try parseInt(i16, &line);
                } else if (eat(&line, "base=")) {
                    result.base = try parseInt(i16, &line);
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
            var id: u32 = undefined;
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
                    id = try parseInt(u32, &line);
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

            try chars.append(tmp.allocator(), .{
                .id = id,
                .x = x,
                .y = y,
                .width = width,
                .height = height,
                .x_offset = x_offset,
                .y_offset = y_offset,
                .xadvance = xadvance,
                .page = page,
                .channel = channel,
            });
        } else {
            log.err("Invalid tag in BMFont; file: '{s}', tag: '{s}'", .{ filename, line });
            return error.InvalidTag;
        }
    }

    result.face = try copyString(allocator, result.face);
    result.charset = try copyString(allocator, result.charset);

    assert(page_count == pages.items.len);
    result.pages = try pages.toOwnedSlice(allocator);

    assert(char_count == chars.items.len);
    result.chars = try chars.toOwnedSlice(allocator);

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
    const result = std.fmt.parseInt(T, sub, 10);
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
