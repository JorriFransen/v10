const std = @import("std");
const log = std.log.scoped(.cpu_texture);
const math = @import("../math.zig");
const mem = @import("memory");
const res = @import("../resource.zig");

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

pub const LoadError = res.LoadError;

pub fn load(allocator: Allocator, name: []const u8, options: LoadCpuTextureOptions) LoadError!CpuTexture {
    var tmp = mem.get_scratch(@ptrCast(@alignCast(allocator.ptr)));

    const resource = try res.load(tmp.allocator(), name);
    _ = resource;
    _ = options;
    unreachable;
}
