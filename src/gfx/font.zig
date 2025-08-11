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

texture: *Texture,

pub const LoadFontError = error{
    UnsupportedFontType,
} ||
    AngelcodeFNTParseError ||
    resource.LoadResourceError;

pub fn load(device: *Device, name: []const u8) LoadFontError!Font {
    _ = device;

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

    unreachable;
}

// TODO: Return error
pub fn init(texture: *const Texture) !Font {
    return .{
        .texture = texture,
    };
}

pub fn deinit(device: *const Device, this: *Font) void {
    this.texture.deinit(device);
}

const AngelcodeFNTInfo = struct {
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

    pub fn free(this: *AngelcodeFNTInfo, allocator: *Allocator) void {
        allocator.free(this.face);
        allocator.free(this.charset);
    }
};

pub const AngelcodeFNTParseError = error{
    InvalidKey,
    InvalidToken,
} ||
    ParseStringError ||
    Allocator.Error ||
    std.fmt.ParseIntError;

fn parseAngelcodeFNT(allocator: Allocator, text: []const u8, filename: []const u8) AngelcodeFNTParseError!AngelcodeFNTInfo {
    var result = AngelcodeFNTInfo{
        .face = "",
        .charset = "",
    };

    var line_it = std.mem.tokenizeAny(u8, text, "\r\n");
    while (line_it.next()) |initial_line| {
        var line = initial_line;

        if (eat(&line, "info")) {
            line = stripLeft(line);

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

                line = stripLeft(line);
            }
        }
    }

    result.face = try copyString(allocator, result.face);
    result.charset = try copyString(allocator, result.charset);

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
    while (len < str.*.len and std.ascii.isDigit(str.*[len])) {
        len += 1;
    }

    const sub = str.*[0..len];
    const result = std.fmt.parseInt(T, sub, 10);
    str.* = str.*[sub.len..];
    return result;
}

fn parseBool(str: *[]const u8) std.fmt.ParseIntError!bool {
    const int = try parseInt(i32, str);
    return int != 0;
}

pub const ParseStringError = error{
    InvalidString,
};

fn parseString(str: *[]const u8) ParseStringError![]const u8 {
    const initial_str = str.*;
    const close_quote = eat(str, "\"");

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
    str.* = str.*[len..];

    return result;
}

fn eat(str: *[]const u8, start: []const u8) bool {
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
