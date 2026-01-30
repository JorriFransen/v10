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

pub const FN_init = *const @TypeOf(initStub);
pub fn initStub(memory: *Memory) callconv(.c) void {
    _ = .{memory};
}

pub const FN_updateAndRender = *const @TypeOf(updateAndRenderStub);
pub fn updateAndRenderStub(memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer) callconv(.c) bool {
    _ = .{ memory, input, offscreen_buffer };
    return true;
}

pub const FN_getAudioFrames = *const @TypeOf(getAudioFramesStub);
pub fn getAudioFramesStub(memory: *Memory, sound_buffer: *AudioBuffer) callconv(.c) void {
    _ = .{ memory, sound_buffer };
}

pub const OffscreenBuffer = struct {
    memory: []u8,
    width: i32,
    height: i32,
    pitch: i32,
    bytes_per_pixel: i32,
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
    is_connected: bool = false,
    is_analog: bool = false,

    stick_average_x: f32 = 0,
    stick_average_y: f32 = 0,

    buttons: extern union {
        array: [12]ButtonState,

        named: extern struct {
            move_up: ButtonState,
            move_down: ButtonState,
            move_left: ButtonState,
            move_right: ButtonState,

            action_up: ButtonState,
            action_down: ButtonState,
            action_left: ButtonState,
            action_right: ButtonState,

            left_shoulder: ButtonState,
            right_shoulder: ButtonState,

            back: ButtonState,
            start: ButtonState,
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

pub const Memory = struct {
    initialized: bool = false,
    permanent: []u8 = &.{},
    transient: []u8 = &.{},

    debug: DEBUG,
};

pub const DEBUG = if (options.internal_build) struct {
    pub const ReadFileResult = extern struct {
        size: usize = 0,
        content: *anyopaque = undefined,
    };

    readEntireFile: *const fn (path: [*:0]const u8) callconv(.c) ReadFileResult = undefined,
    freeFileMemory: *const fn (memory: ?*anyopaque, size: usize) callconv(.c) void = undefined,
    writeEntireFile: *const fn (path: [*:0]const u8, memory: *anyopaque, size: usize) callconv(.c) bool = undefined,
} else struct {};

pub const GameState = extern struct {
    blue_offset: i32 = 0,
    green_offset: i32 = 0,
    tone_hz: i32 = 0,
    t_sine: f32 = 0,

    player_x: i32 = 0,
    player_y: i32 = 0,
    jump_timer: f32 = 0,
};

pub export fn init(game_memory: *Memory) callconv(.c) void {
    _ = game_memory;
}

pub export fn updateAndRender(game_memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer) callconv(.c) bool {
    assert(@sizeOf(GameState) <= game_memory.permanent.len);

    var result = true;

    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent.ptr));
    if (!game_memory.initialized) {
        game_state.* = .{};
        game_state.tone_hz = 512;

        game_state.player_x = 100;
        game_state.player_y = 100;

        game_memory.initialized = true;
    }

    game_state.tone_hz = 512;

    for (input.controllers) |controller| if (controller.is_connected) {
        const buttons = &controller.buttons.named;

        if (controller.is_analog) {
            game_state.blue_offset += @intFromFloat(4 * controller.stick_average_x);
            game_state.tone_hz = @intFromFloat(512 + (128 * controller.stick_average_y));
        } else {
            if (buttons.move_left.ended_down) {
                game_state.blue_offset -= 4;
            }
            if (buttons.move_right.ended_down) {
                game_state.blue_offset += 4;
            }
        }

        // if (buttons.action_down.ended_down) {
        //     game_state.green_offset += 1;
        // }

        if (buttons.action_up.ended_down) {
            game_state.tone_hz = 512 + 256;
        } else if (buttons.action_down.ended_down) {
            game_state.tone_hz = 256;
        }

        if (buttons.start.ended_down) {
            result = false;
        }

        game_state.player_x += @intFromFloat(4 * controller.stick_average_x);
        game_state.player_y -= @intFromFloat(4 * controller.stick_average_y);
        if (game_state.jump_timer > 0) {
            game_state.player_y += @intFromFloat(@sin(0.5 * std.math.pi * game_state.jump_timer) * 10);
        }

        if (buttons.action_down.ended_down) {
            game_state.jump_timer = 4;
        }
        game_state.jump_timer -= 0.033;
    };

    renderWeirdGradient(offscreen_buffer, game_state.blue_offset, game_state.green_offset);
    renderPlayer(offscreen_buffer, game_state.player_x, game_state.player_y);

    return result;
}

pub export fn getAudioFrames(game_memory: *Memory, sound_buffer: *AudioBuffer) callconv(.c) void {
    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent.ptr));
    outputSound(game_state, sound_buffer);
}

pub fn outputSound(game_state: *GameState, buffer: *AudioBuffer) void {
    const tone_volume = 3000;
    const wave_period = @divTrunc(buffer.frames_per_second, game_state.tone_hz);

    assert(buffer.frame_count >= 0);

    var frame_out = buffer.frames;
    for (0..@intCast(buffer.frame_count)) |_| {

        // const sine_value: f32 = @sin(game_state.t_sine);
        // const sample_value: i16 = @intFromFloat(@as(f32, @floatFromInt(tone_volume)) * sine_value);
        _ = tone_volume;
        const sample_value: i16 = 0;

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
            pixel[0] = (@as(u32, g) << 16) | b;
            pixel += 1;
        }
        row += @intCast(buffer.pitch);
    }
}

fn renderPlayer(buffer: *OffscreenBuffer, player_x: i32, player_y: i32) void {
    const width = 10;
    const height = 10;
    const color = 0xffffffff;

    const px: isize = @intCast(player_x);
    const bytes_per_pixel: isize = @intCast(buffer.bytes_per_pixel);
    const pitch: isize = @intCast(buffer.pitch);

    const top: isize = @intCast(player_y);
    const bottom: isize = @intCast(player_y + height);

    const utop: usize = @max(0, top);
    const ubottom: usize = @intCast(@min(buffer.height, @max(0, bottom)));

    for (0..width) |x_offset| {
        const offset: isize = ((px + @as(isize, @intCast(x_offset))) * bytes_per_pixel) + (top * pitch);
        if (offset >= 0 and offset < buffer.memory.len) {
            var pixel: [*]u8 = @ptrCast(&buffer.memory[@intCast(offset)]);

            for (utop..ubottom) |_| {
                @as(*u32, @ptrCast(@alignCast(pixel))).* = color;
                pixel += @intCast(pitch);
            }
        }
    }
}
