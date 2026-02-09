const std = @import("std");
const log = std.log.scoped(.v10);
const options = @import("options");
const v10s = @import("v10_shared.zig");

const assert = std.debug.assert;

const os = @import("builtin").os.tag;
pub const platform = switch (os) {
    .windows => @import("win32_v10.zig"),
    .linux => @import("linux_v10.zig"),
    else => @compileError("Unsupported platform"),
};

pub const ThreadContext = struct {
    io: std.Io,
};

pub const FN_init = *const fn (thread_context: *ThreadContext, memory: *Memory) callconv(.c) void;
pub const FN_updateAndRender = *const fn (thread_context: *ThreadContext, memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer) callconv(.c) bool;
pub const FN_getAudioFrames = *const fn (thread_context: *ThreadContext, memory: *Memory, sound_buffer: *AudioBuffer) callconv(.c) void;

pub const OffscreenBuffer = struct {
    memory: []u8,
    width: i32,
    height: i32,
    pitch: i32,
    bytes_per_pixel: i32,
};

pub const AudioBuffer = struct {
    pub const Sample = i16;
    pub const Frame = struct {
        left: Sample = 0,
        right: Sample = 0,
    };

    frames: []Frame,
    frames_per_second: i32,
};

pub const ButtonState = extern struct {
    half_transition_count: i32 = 0,
    ended_down: bool = false,
};

pub const ControllerInput = struct {
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

pub const DebugMouseInput = if (options.internal_build) struct {
    buttons: extern union {
        array: [5]ButtonState,
        named: extern struct {
            left: ButtonState,
            right: ButtonState,
            middle: ButtonState,

            extra0: ButtonState,
            extra1: ButtonState,
        },

        comptime {
            const dummy: @This() = std.mem.zeroes(@This());
            assert(dummy.array.len == @typeInfo(@TypeOf(@field(dummy, "named"))).@"struct".fields.len);
        }
    } = std.mem.zeroes(@FieldType(@This(), "buttons")),

    x: i32 = 0,
    y: i32 = 0,
    z: i32 = 0,
} else void;

pub const Input = struct {
    debug_mouse: DebugMouseInput = .{},

    dt: f32 = 0,
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

    readEntireFile: *const fn (thread_context: *ThreadContext, path: [*:0]const u8, path_len: usize) callconv(.c) ReadFileResult = undefined,
    freeFileMemory: *const fn (thread_context: *ThreadContext, memory: ?*anyopaque, size: usize) callconv(.c) void = undefined,
    writeEntireFile: *const fn (thread_context: *ThreadContext, path: [*:0]const u8, path_len: usize, memory: *anyopaque, size: usize) callconv(.c) bool = undefined,
} else struct {};

pub const GameState = struct {
    player_x: f32,
    player_y: f32,
};

pub export fn init(thread_context: *ThreadContext, game_memory: *Memory) callconv(.c) void {
    _ = thread_context;
    _ = game_memory;
}

pub export fn updateAndRender(thread_context: *ThreadContext, game_memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer) callconv(.c) bool {
    _ = thread_context;

    assert(@sizeOf(GameState) <= game_memory.permanent.len);

    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent.ptr));
    if (!game_memory.initialized) {
        game_state.* = .{
            .player_x = 100,
            .player_y = 100,
        };
        game_memory.initialized = true;
    }

    var keep_running = true;

    for (input.controllers) |controller| if (controller.is_connected) {
        const buttons = &controller.buttons.named;

        var d_player_x: f32 = 0;
        var d_player_y: f32 = 0;

        if (controller.is_analog) {
            d_player_x = controller.stick_average_x;
            d_player_y = controller.stick_average_y;
        } else {
            if (buttons.move_left.ended_down) d_player_x -= 1;
            if (buttons.move_right.ended_down) d_player_x += 1;
            if (buttons.move_up.ended_down) d_player_y -= 1;
            if (buttons.move_down.ended_down) d_player_y += 1;
        }

        const player_speed = 64;

        game_state.player_x += d_player_x * input.dt * player_speed;
        game_state.player_y += d_player_y * input.dt * player_speed;

        if (buttons.start.ended_down) {
            keep_running = false;
        }
    };

    const tile_map: [9][17]u32 = .{
        .{ 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1 },
        .{ 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1 },
        .{ 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1 },
        .{ 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1 },
        .{ 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 },
        .{ 1, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1 },
        .{ 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
        .{ 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1 },
        .{ 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1 },
    };

    @memset(@as([]u32, @ptrCast(@alignCast(offscreen_buffer.memory))), 0xff00ff);
    // drawRectangle(offscreen_buffer, 0, 0, @floatFromInt(offscreen_buffer.width), @floatFromInt(offscreen_buffer.height), 1, 0, 1);

    const tile_width = 60;
    const tile_height = tile_width;
    const tilemap_x_offset = -30;
    const tilemap_y_offset = 0;

    for (&tile_map, 0..) |row, iy| {
        const y = tilemap_y_offset + @as(f32, @floatFromInt(iy)) * tile_height;
        for (row, 0..) |tile, ix| {
            const x = tilemap_x_offset + @as(f32, @floatFromInt(ix)) * tile_width;
            const grayscale: f32 = if (tile == 1) 1 else 0.5;
            drawRectangle(offscreen_buffer, x, y, x + tile_width, y + tile_height, grayscale, grayscale, grayscale);
        }
    }

    const player_width = tile_width * 0.75;
    const player_height = tile_height;
    const player_left: f32 = game_state.player_x - (player_width * 0.5);
    const player_top: f32 = game_state.player_y - player_height;
    const player_right = player_left + player_width;
    const player_bottom = player_top + player_height;
    drawRectangle(offscreen_buffer, player_left, player_top, player_right, player_bottom, 1, 1, 0);

    return keep_running;
}

pub export fn getAudioFrames(thread_context: *ThreadContext, game_memory: *Memory, sound_buffer: *AudioBuffer) callconv(.c) void {
    _ = thread_context;
    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent.ptr));
    outputSound(game_state, sound_buffer, 400);
}

pub fn outputSound(game_state: *GameState, buffer: *AudioBuffer, tone_hz: i32) void {
    _ = game_state;
    _ = tone_hz;
    // const tone_volume = 3000;
    // const wave_period = @divTrunc(buffer.frames_per_second, tone_hz);

    assert(buffer.frames.len >= 0);

    for (buffer.frames) |*frame| {
        // const sine_value: f32 = @sin(game_state.t_sine);
        // const sample_value: i16 = @intFromFloat(@as(f32, @floatFromInt(tone_volume)) * sine_value);
        const sample_value: i16 = 0;

        frame.* = .{ .left = sample_value, .right = sample_value };

        // game_state.t_sine += std.math.tau / @as(f32, @floatFromInt(wave_period));
        // if (game_state.t_sine > std.math.tau) game_state.t_sine -= std.math.tau;
    }
}

pub inline fn rgbToU32(r: f32, g: f32, b: f32) u32 {
    return 0 |
        @as(u24, @intFromFloat(r * 255)) << 16 |
        @as(u16, @intFromFloat(g * 255)) << 8 |
        @as(u8, @intFromFloat(b * 255));
}

fn drawRectangle(buffer: *OffscreenBuffer, min_x: f32, min_y: f32, max_x: f32, max_y: f32, r: f32, g: f32, b: f32) void {
    const pitch: usize = @intCast(buffer.pitch);
    const bpp: usize = @intCast(buffer.bytes_per_pixel);

    const minx_: isize = @intFromFloat(@round(min_x));
    const miny_: isize = @intFromFloat(@round(min_y));
    const maxx_: isize = @intFromFloat(@round(max_x));
    const maxy_: isize = @intFromFloat(@round(max_y));

    const minx: usize = @intCast(@min(@max(minx_, 0), buffer.width));
    const miny: usize = @intCast(@min(@max(miny_, 0), buffer.height));
    const maxx: usize = @intCast(@min(@max(maxx_, 0), buffer.width));
    const maxy: usize = @intCast(@min(@max(maxy_, 0), buffer.height));

    assert(bpp == @sizeOf(u32));

    const color = rgbToU32(r, g, b);

    var row: [*]u8 = buffer.memory.ptr + (minx * bpp) + (miny * pitch);
    var y: usize = @intCast(miny);
    while (y < maxy) : (y += 1) {
        var pixel: [*]u32 = @ptrCast(@alignCast(row));
        var x: usize = @intCast(minx);
        while (x < maxx) : (x += 1) {
            pixel[0] = color;
            pixel += 1;
        }

        row += pitch;
    }
}
