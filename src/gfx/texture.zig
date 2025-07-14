const std = @import("std");
const vk = @import("vulkan");
const gfx = @import("../gfx.zig");
const stb = @import("../stb/stb.zig");
const mem = @import("memory");
const resource = @import("../resource.zig");

const Texture = @This();
const Device = gfx.Device;

const assert = std.debug.assert;

pub fn load(device: *Device, name: []const u8) !Texture {
    _ = device;
    var ta = mem.get_temp();
    defer ta.release();

    const texture_file = try resource.load(ta.allocator(), name);
    assert(texture_file == .texture_file);

    // TODO: Test this by passing identifier instead of file
    const cpu_texture = try resource.loadCpuTexture(ta.allocator(), .{ .from_resource = texture_file });
    _ = cpu_texture;

    // std.log.debug("cpu_tex: {}", .{cpu_texture});

    return .{};
}

pub fn destroy(_: *@This()) void {}
