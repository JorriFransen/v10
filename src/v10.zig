const std = @import("std");
const log = std.log.scoped(.v10);

const assert = std.debug.assert;

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
        is_analog: bool = false,

        start_x: f32 = 0,
        start_y: f32 = 0,
        min_x: f32 = 0,
        min_y: f32 = 0,
        max_x: f32 = 0,
        max_y: f32 = 0,
        end_x: f32 = 0,
        end_y: f32 = 0,

        up: ButtonState = .{},
        down: ButtonState = .{},
        left: ButtonState = .{},
        right: ButtonState = .{},
        dpad_up: ButtonState = .{},
        dpad_down: ButtonState = .{},
        dpad_left: ButtonState = .{},
        dpad_right: ButtonState = .{},
        left_shoulder: ButtonState = .{},
        right_shoulder: ButtonState = .{},
    };

    pub const Input = struct {
        controllers: [4]ControllerInput = .{ControllerInput{}} ** 4,
    };

    pub const GameState = struct {
        blue_offset: i32 = 0,
        green_offset: i32 = 0,
        tone_hz: i32 = 256,
        t_sine: f32 = 0,
    };

    pub const Memory = struct {
        initialized: bool = false,
        permanent: []u8,
        transient: []u8,
    };

    pub fn updateAndRender(memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer, sound_buffer: *AudioBuffer) void {
        assert(@sizeOf(GameState) <= memory.permanent.len);

        const game_state: *GameState = @ptrCast(@alignCast(memory.permanent.ptr));
        if (!memory.initialized) {
            game_state.blue_offset = 0;
            game_state.green_offset = 0;
            game_state.tone_hz = 256;
            game_state.t_sine = 0;

            memory.initialized = true;
        }

        const input_0 = &input.controllers[0];

        if (input_0.is_analog) {
            game_state.blue_offset += @intFromFloat(4 * input_0.end_x);
            game_state.tone_hz = @intFromFloat(256 + (128 * input_0.end_y));
        }

        if (input_0.down.ended_down) {
            game_state.green_offset += 1;
        }

        if (input_0.dpad_up.ended_down) {
            game_state.green_offset -= 1;
        } else if (input_0.dpad_down.ended_down) {
            game_state.green_offset += 1;
        }

        if (input_0.dpad_right.ended_down) {
            game_state.blue_offset += 1;
        } else if (input_0.dpad_left.ended_down) {
            game_state.blue_offset -= 1;
        }

        outputSound(game_state, sound_buffer);
        renderWeirdGradient(offscreen_buffer, game_state.blue_offset, game_state.green_offset);
    }

    pub fn outputSound(game_state: *GameState, buffer: *AudioBuffer) void {
        const tone_volume = 3000;
        const wave_period = @divTrunc(buffer.frames_per_second, game_state.tone_hz);

        var sample_out: [*]i16 = buffer.samples;
        for (0..@intCast(buffer.frame_count)) |_| {
            const sine_value: f32 = @sin(game_state.t_sine);
            const sample_value: i16 = @intFromFloat(@as(f32, @floatFromInt(tone_volume)) * sine_value);
            sample_out[0] = sample_value;
            sample_out += 1;

            sample_out[0] = sample_value;
            sample_out += 1;

            game_state.t_sine += std.math.tau / @as(f32, @floatFromInt(wave_period));
            if (game_state.t_sine > std.math.tau) game_state.t_sine -= std.math.tau;
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
