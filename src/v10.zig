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
        frame_count: i32,
        frames_per_second: i32,
    };

    pub const ButtonState = extern struct {
        half_transition_count: i32 = 0,
        ended_down: bool = false,
    };

    pub const ControllerInput = struct {
        start_x: f32 = 0,
        start_y: f32 = 0,
        min_x: f32 = 0,
        min_y: f32 = 0,
        max_x: f32 = 0,
        max_y: f32 = 0,
        end_x: f32 = 0,
        end_y: f32 = 0,

        is_analog: bool = false,

        up: ButtonState = .{},
        down: ButtonState = .{},
        left: ButtonState = .{},
        right: ButtonState = .{},
        left_shoulder: ButtonState = .{},
        right_shoulder: ButtonState = .{},
    };

    pub const Input = struct {
        controllers: [4]ControllerInput = .{ControllerInput{}} ** 4,
    };

    var blue_offset: i32 = 0;
    var green_offset: i32 = 0;
    var tone_hz: i32 = 256;
    var t_sine: f32 = 0;

    pub fn updateAndRender(input: *const Input, offscreen_buffer: *OffscreenBuffer, sound_buffer: *AudioBuffer) void {
        const input_0 = &input.controllers[0];

        if (input_0.is_analog) {
            blue_offset += @intFromFloat(4 * input_0.end_x);
            tone_hz = @intFromFloat(256 + (128 * input_0.end_y));
        }

        if (input_0.down.ended_down) {
            green_offset += 1;
        }

        outputSound(sound_buffer);
        renderWeirdGradient(offscreen_buffer, blue_offset, green_offset);
    }

    pub fn outputSound(buffer: *AudioBuffer) void {
        const tone_volume = 3000;
        const wave_period = @divTrunc(buffer.frames_per_second, tone_hz);

        var sample_out: [*]i16 = buffer.samples;
        for (0..@intCast(buffer.frame_count)) |_| {
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
