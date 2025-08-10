const std = @import("std");
const math = @import("../math.zig");
const root = @import("root");

const log = std.log.scoped(.sprite);

const Sprite = @This();
const Texture = @import("texture.zig");
const Vec2 = math.Vec2;
const Rect = math.Rect;

texture: *const Texture,
uv_rect: Rect,
ppu: f32,

pub const Options = struct {
    yflip: bool = false,
    uv_rect: Rect = .{ .size = Vec2.scalar(1) },

    ppu: ?f32 = null,
};

// TODO: Should this return a pointer
pub fn init(texture: *const Texture, options: Options) Sprite {
    var uv_rect = options.uv_rect;
    if (options.yflip) {
        uv_rect.pos.y = uv_rect.pos.y + uv_rect.size.y;
        uv_rect.size.y = -uv_rect.size.y;
    }

    return .{
        .texture = texture,
        .uv_rect = uv_rect,

        .ppu = if (options.ppu) |ppu| ppu else root.config.ppu,
    };
}
