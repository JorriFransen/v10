const std = @import("std");
const log = std.log.scoped(.v10);

const os = @import("builtin").os.tag;
const platform = switch (os) {
    .windows => @import("win32_v10.zig"),
    .linux => @import("linux_v10.zig"),
    else => @compileError("Unsupported platform"),
};

// Services provided by the game
pub const game = struct {
    pub const OffscreenBuffer = struct {
        memory: []u8,
        width: i32,
        height: i32,
        pitch: i32,
    };

    pub fn updateAndRender(offscreen_buffer: *OffscreenBuffer, blue_offset: i32, green_offset: i32) void {
        renderWeirdGradient(offscreen_buffer, blue_offset, green_offset);
    }
};

fn renderWeirdGradient(buffer: *game.OffscreenBuffer, blue_offset: i32, green_offset: i32) void {
    const uwidth: usize = @intCast(buffer.width);
    const uheight: usize = @intCast(buffer.height);

    var row: [*]u8 = buffer.memory.ptr;
    for (0..uheight) |uy| {
        const y: i32 = @intCast(uy);
        var pixel: [*]u32 = @ptrCast(@alignCast(row));
        for (0..uwidth) |ux| {
            const x: i32 = @intCast(ux);

            const b: u8 = @truncate(@as(u32, @bitCast(x +% blue_offset)));
            const g: u8 = @truncate(@as(u32, @bitCast(y +% green_offset)));
            pixel[0] = (@as(u16, g) << 8) | b;
            pixel += 1;
        }
        row += @intCast(buffer.pitch);
    }
}
