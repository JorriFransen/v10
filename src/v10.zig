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

    tile_map_x: usize,
    tile_map_y: usize,
};

pub export fn init(thread_context: *ThreadContext, game_memory: *Memory) callconv(.c) void {
    _ = thread_context;
    _ = game_memory;
}

pub export fn updateAndRender(thread_context: *ThreadContext, game_memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer) callconv(.c) bool {
    _ = thread_context;

    assert(@sizeOf(GameState) <= game_memory.permanent.len);

    var keep_running = true;

    const tile_size = 60;
    const tile_map_count_x = 17;
    const tile_map_count_y = 9;
    const tile_map_tiles_0_0: [tile_map_count_y * tile_map_count_x]u32 = .{
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1,
        1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1,
        1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1,
        1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1,
    };
    const tile_map_tiles_0_1: [tile_map_count_y * tile_map_count_x]u32 = .{
        1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    };
    const tile_map_tiles_1_0: [tile_map_count_y * tile_map_count_x]u32 = .{
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1,
        1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1,
        0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1,
        1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1,
        1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1,
    };
    const tile_map_tiles_1_1: [tile_map_count_y * tile_map_count_x]u32 = .{
        1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    };

    var tile_maps: [2][2]TileMap = undefined;
    tile_maps[0][0] = .{
        .count_x = tile_map_count_x,
        .count_y = tile_map_count_y,
        .tile_width = tile_size,
        .tile_height = tile_size,
        .x_offset = -(tile_size / 2),
        .y_offset = 0,
        .tiles = &tile_map_tiles_0_0,
    };

    tile_maps[0][1] = tile_maps[0][0];
    tile_maps[0][1].tiles = &tile_map_tiles_1_0;

    tile_maps[1][0] = tile_maps[0][0];
    tile_maps[1][0].tiles = &tile_map_tiles_0_1;

    tile_maps[1][1] = tile_maps[0][0];
    tile_maps[1][1].tiles = &tile_map_tiles_1_1;

    var tile_map: *TileMap = &tile_maps[0][0];
    const world: World = .{
        .count_x = tile_maps.len,
        .count_y = tile_maps[0].len,
        .tile_maps = @ptrCast(&tile_maps),
    };

    const player_width = tile_map.tile_width * 0.75;
    const player_height = tile_map.tile_height;

    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent.ptr));
    if (!game_memory.initialized) {
        game_state.* = .{
            .player_x = 150,
            .player_y = 150,

            .tile_map_x = 0,
            .tile_map_y = 0,
        };
        game_memory.initialized = true;
    }

    for (input.controllers) |controller| if (controller.is_connected) {
        const buttons = &controller.buttons.named;
        if (buttons.start.ended_down) {
            keep_running = false;
        }

        var d_player_x: f32 = 0;
        var d_player_y: f32 = 0;

        if (controller.is_analog) {
            // d_player_x += controller.stick_average_x;
            // d_player_y -= controller.stick_average_y;
        } else {
            if (buttons.move_left.ended_down) d_player_x -= 1;
            if (buttons.move_right.ended_down) d_player_x += 1;
            if (buttons.move_up.ended_down) d_player_y -= 1;
            if (buttons.move_down.ended_down) d_player_y += 1;
        }

        const player_speed = 64;
        d_player_x *= player_speed;
        d_player_y *= player_speed;

        const new_player_x = game_state.player_x + d_player_x * input.dt;
        const new_player_y = game_state.player_y + d_player_y * input.dt;

        const bottom_left_x = new_player_x - (player_width / 2.0);
        const bottom_right_x = new_player_x + (player_width / 2.0);

        const is_valid_tile =
            world.isEmptyPoint(game_state.tile_map_x, game_state.tile_map_y, bottom_left_x, new_player_y) and
            world.isEmptyPoint(game_state.tile_map_x, game_state.tile_map_y, bottom_right_x, new_player_y);

        if (is_valid_tile) {
            game_state.player_x = new_player_x;
            game_state.player_y = new_player_y;
        }
    };

    @memset(@as([]u32, @ptrCast(@alignCast(offscreen_buffer.memory))), 0xff00ff);
    // drawRectangle(offscreen_buffer, 0, 0, @floatFromInt(offscreen_buffer.width), @floatFromInt(offscreen_buffer.height), 1, 0, 1);

    for (0..tile_map.count_y) |iy| {
        const y = tile_map.y_offset + @as(f32, @floatFromInt(iy)) * tile_map.tile_height;
        for (0..tile_map.count_x) |ix| {
            const x = tile_map.x_offset + @as(f32, @floatFromInt(ix)) * tile_map.tile_width;
            const tile = tile_map.getTileUnchecked(ix, iy);
            const grayscale: f32 = if (tile == 1) 1 else 0.5;
            drawRectangle(offscreen_buffer, x, y, x + tile_map.tile_width, y + tile_map.tile_height, grayscale, grayscale, grayscale);
        }
    }

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

pub const TileMap = struct {
    count_x: usize,
    count_y: usize,

    tile_width: f32,
    tile_height: f32,

    x_offset: f32,
    y_offset: f32,

    tiles: []const u32,

    pub inline fn getTileUnchecked(this: *const TileMap, x: usize, y: usize) u32 {
        return this.tiles[x + (y * this.count_x)];
    }

    pub fn isEmptyPoint(this: *const TileMap, px: f32, py: f32) bool {
        var empty = false;

        const player_tile_x: isize = @intFromFloat(@trunc((px - this.x_offset) / this.tile_width));
        const player_tile_y: isize = @intFromFloat(@trunc((py - this.y_offset) / this.tile_height));

        if (player_tile_x >= 0 and player_tile_x < this.count_x and
            player_tile_y >= 0 and player_tile_y < this.count_y)
        {
            const tx: usize = @intCast(player_tile_x);
            const ty: usize = @intCast(player_tile_y);
            const tile = this.getTileUnchecked(tx, ty);
            empty = tile == 0;
        }

        return empty;
    }
};

pub const World = struct {
    count_x: usize,
    count_y: usize,
    tile_maps: []const TileMap,

    pub inline fn getTileMap(this: *const World, x: usize, y: usize) ?*const TileMap {
        if (x < this.count_x and y < this.count_y) {
            return &this.tile_maps[x + (y * this.count_y)];
        }

        return null;
    }

    pub fn isEmptyPoint(this: *const World, tile_map_x: usize, tile_map_y: usize, px: f32, py: f32) bool {
        var empty = false;

        if (this.getTileMap(tile_map_x, tile_map_y)) |tile_map| {
            const player_tile_x: usize = @intFromFloat(@trunc((px - tile_map.x_offset) / tile_map.tile_width));
            const player_tile_y: usize = @intFromFloat(@trunc((py - tile_map.y_offset) / tile_map.tile_height));

            if (player_tile_x >= 0 and player_tile_x < tile_map.count_x and
                player_tile_y >= 0 and player_tile_y < tile_map.count_y)
            {
                const tx: usize = @intCast(player_tile_x);
                const ty: usize = @intCast(player_tile_y);
                const tile = tile_map.getTileUnchecked(tx, ty);
                empty = tile == 0;
            }
        }

        return empty;
    }
};

pub inline fn rgbToU32(r: f32, g: f32, b: f32) u32 {
    return 0 |
        @as(u24, @intFromFloat(r * 255)) << 16 |
        @as(u16, @intFromFloat(g * 255)) << 8 |
        @as(u8, @intFromFloat(b * 255));
}

pub fn drawRectangle(buffer: *OffscreenBuffer, min_x: f32, min_y: f32, max_x: f32, max_y: f32, r: f32, g: f32, b: f32) void {
    const pitch: usize = @intCast(buffer.pitch);
    const bpp: usize = @intCast(buffer.bytes_per_pixel);

    const buffer_width_f: f32 = @floatFromInt(buffer.width);
    const buffer_height_f: f32 = @floatFromInt(buffer.height);

    const minx: usize = @intFromFloat(@min(@max(@floor(min_x), 0), buffer_width_f));
    const miny: usize = @intFromFloat(@min(@max(@floor(min_y), 0), buffer_height_f));
    const maxx: usize = @intFromFloat(@min(@max(@floor(max_x), 0), buffer_width_f));
    const maxy: usize = @intFromFloat(@min(@max(@floor(max_y), 0), buffer_height_f));

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
