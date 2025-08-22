const std = @import("std");
const log = std.log.scoped(.cpu_texture);
const math = @import("../math.zig");
const mem = @import("memory");
const res = @import("../resource.zig");
const stb = @import("../stb/stb.zig");

const Allocator = std.mem.Allocator;
const Format = @import("texture.zig").Format;
const Vec2u32 = math.Vec(2, u32);
const CpuTexture = @This();

format: Format,
size: Vec2u32,
data: []const u8,

pub const LoadCpuTextureOptions = struct {
    format: Format = .u8_s_rgba,
};

pub const LoadError =
    res.LoadError ||
    stb.image.Error;

pub fn load(allocator: Allocator, name: []const u8, options: LoadCpuTextureOptions) LoadError!CpuTexture {
    var tmp = mem.get_scratch(@ptrCast(@alignCast(allocator.ptr)));
    defer tmp.release();

    const resource = try res.load(tmp.allocator(), name);
    switch (resource.type) {
        .png => {}, // ok
        else => {
            log.err("Invalid resource type for cpu texture: '{s}' ({s})", .{ name, @tagName(resource.type) });
            return error.UnsupportedType;
        },
    }

    const stb_format: stb.image.Format = switch (options.format) {
        .u8_s_rgba => .rgb_alpha,
        .u8_u_r => .grey,
    };

    const texture = try stb.image.loadFromMemory(allocator, resource.data, stb_format);

    return .{
        .format = options.format,
        .size = Vec2u32.new(texture.x, texture.y),
        .data = texture.data,
    };
}
