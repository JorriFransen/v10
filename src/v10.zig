const std = @import("std");
const log = std.log.scoped(.v10);
const options = @import("options");

const assert = std.debug.assert;

const os = @import("builtin").os.tag;
pub const platform = switch (os) {
    .windows => @import("win32_v10.zig"),
    .linux => @import("linux_v10.zig"),
    else => @compileError("Unsupported platform"),
};

pub const DEBUG = if (options.internal_build) struct {
    pub const ReadFileResult = extern struct {
        size: usize = 0,
        content: *anyopaque = undefined,
    };

    pub extern fn readEntireFile(path: [*:0]const u8) callconv(.c) ReadFileResult;
    pub extern fn freeFileMemory(memory: ?*anyopaque, size: usize) void;
    pub extern fn writeEntireFile(path: [*:0]const u8, memory: *anyopaque, size: usize) bool;
} else struct {};

pub inline fn safeTruncateU64(value: u64) u32 {
    assert(value <= std.math.maxInt(u32));
    return @intCast(value);
}

pub const OffscreenBuffer = struct {
    memory: []u8,
    width: i32,
    height: i32,
    pitch: i32,
};

pub const AudioBuffer = extern struct {
    pub const Sample = i16;
    pub const Frame = extern struct {
        left: Sample = 0,
        right: Sample = 0,
    };

    frames: [*]Frame,
    frame_count: i32,
    frames_per_second: i32,
};

pub const ButtonState = extern struct {
    half_transition_count: i32 = 0,
    ended_down: bool = false,
};

pub const ControllerInput = extern struct {
    is_analog: bool = false,

    start_x: f32 = 0,
    start_y: f32 = 0,
    min_x: f32 = 0,
    min_y: f32 = 0,
    max_x: f32 = 0,
    max_y: f32 = 0,
    end_x: f32 = 0,
    end_y: f32 = 0,

    buttons: extern union {
        array: [10]ButtonState,
        named: extern struct {
            up: ButtonState,
            down: ButtonState,
            left: ButtonState,
            right: ButtonState,
            dpad_up: ButtonState,
            dpad_down: ButtonState,
            dpad_left: ButtonState,
            dpad_right: ButtonState,
            left_shoulder: ButtonState,
            right_shoulder: ButtonState,
        },
        comptime {
            const dummy: @This() = std.mem.zeroes(@This());
            assert(dummy.array.len == @typeInfo(@TypeOf(@field(dummy, "named"))).@"struct".fields.len);
        }
    },
};

pub const Input = extern struct {
    controllers: [5]ControllerInput = .{std.mem.zeroes(ControllerInput)} ** 5,
};

pub const GameState = extern struct {
    blue_offset: i32 = 0,
    green_offset: i32 = 0,
    tone_hz: i32 = 256,
    t_sine: f32 = 0,
};

pub const Memory = struct {
    initialized: bool = false,
    permanent: []u8 = &.{},
    transient: []u8 = &.{},
};

pub fn updateAndRender(game_memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer, sound_buffer: *AudioBuffer) void {
    assert(@sizeOf(GameState) <= game_memory.permanent.len);

    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent.ptr));
    if (!game_memory.initialized) {
        game_state.tone_hz = 256;

        game_memory.initialized = true;
    }

    for (input.controllers) |controller| {
        if (controller.is_analog) {
            game_state.blue_offset += @intFromFloat(4 * controller.end_x);
            game_state.tone_hz = @intFromFloat(256 + (128 * controller.end_y));
        }

        if (controller.buttons.named.down.ended_down) {
            game_state.green_offset += 1;
        }

        if (controller.buttons.named.dpad_up.ended_down) {
            game_state.green_offset -= 1;
        }
        if (controller.buttons.named.dpad_down.ended_down) {
            game_state.green_offset += 1;
        }

        if (controller.buttons.named.dpad_right.ended_down) {
            game_state.blue_offset += 1;
        }
        if (controller.buttons.named.dpad_left.ended_down) {
            game_state.blue_offset -= 1;
        }
    }

    outputSound(game_state, sound_buffer);
    renderWeirdGradient(offscreen_buffer, game_state.blue_offset, game_state.green_offset);
}

pub fn outputSound(game_state: *GameState, buffer: *AudioBuffer) void {
    const tone_volume = 3000;
    const wave_period = @divTrunc(buffer.frames_per_second, game_state.tone_hz);

    var frame_out = buffer.frames;
    for (0..@intCast(buffer.frame_count)) |_| {
        const sine_value: f32 = @sin(game_state.t_sine);
        const sample_value: i16 = @intFromFloat(@as(f32, @floatFromInt(tone_volume)) * sine_value);

        frame_out[0] = .{ .left = sample_value, .right = sample_value };
        frame_out += 1;

        game_state.t_sine += std.math.tau / @as(f32, @floatFromInt(wave_period));
        if (game_state.t_sine > std.math.tau) game_state.t_sine -= std.math.tau;
    }
}

fn renderWeirdGradient(buffer: *OffscreenBuffer, blue_offset: i32, green_offset: i32) void {
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
