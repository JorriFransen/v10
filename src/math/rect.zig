const math = @import("../math.zig");

const Vec = math.Vec;

pub const Rectf32 = RectT(f32);

pub fn RectT(comptime T: type) type {
    const Vec2 = Vec(2, T);

    return struct {
        const Rect = @This();

        pos: Vec2 = .{},
        size: Vec2 = .{},

        pub inline fn new(pos: Vec2, size: Vec2) Rect {
            return .{
                .pos = pos,
                .size = size,
            };
        }

        pub inline fn move(this: Rect, offset: Vec2) Rect {
            return .{ .pos = this.pos.add(offset), .size = this.size };
        }

        pub inline fn tl(this: Rect) Vec2 {
            return this.pos.add(.{ .y = this.size.y });
        }

        pub inline fn tr(this: Rect) Vec2 {
            return this.pos.add(this.size);
        }

        pub inline fn bl(this: Rect) Vec2 {
            return this.pos;
        }

        pub inline fn br(this: Rect) Vec2 {
            return this.pos.add(.{ .x = this.size.x });
        }
    };
}
