const std = @import("std");
const gfx = @import("../gfx.zig");

const Font = @This();
const Texture = gfx.Texture;
const Device = gfx.Device;

texture: *Texture,

// TODO: Return error
pub fn init(texture: *const Texture) !Font {
    return .{
        .texture = texture,
    };
}

pub fn deinit(device: *const Device, this: *Font) void {
    this.texture.deinit(device);
}
