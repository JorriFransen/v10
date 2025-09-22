const std = @import("std");
const log = std.log.scoped(.v10);

const os = @import("builtin").os.tag;
pub const platform = switch (os) {
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

    pub const AudioBuffer = struct {
        samples: [*]i16,
        frame_count: u32,
        frames_per_second: u32,
    };

    pub fn updateAndRender(offscreen_buffer: *OffscreenBuffer, sound_buffer: *AudioBuffer, blue_offset: i32, green_offset: i32, tone_hz: u32) void {
        outputSound(sound_buffer, tone_hz);
        renderWeirdGradient(offscreen_buffer, blue_offset, green_offset);
    }

    var t_sine: f32 = 0;
    pub fn outputSound(buffer: *AudioBuffer, tone_hz: u32) void {
        const tone_volume = 3000;
        const wave_period = buffer.frames_per_second / tone_hz;

        var sample_out: [*]i16 = buffer.samples;
        for (0..buffer.frame_count) |_| {
            const sine_value: f32 = @sin(t_sine);
            const sample_value: i16 = @intFromFloat(@as(f32, @floatFromInt(tone_volume)) * sine_value);
            sample_out[0] = sample_value;
            sample_out += 1;

            sample_out[0] = sample_value;
            sample_out += 1;

            t_sine += std.math.tau / @as(f32, @floatFromInt(wave_period));
            if (t_sine > std.math.tau) t_sine -= std.math.tau;
        }
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
