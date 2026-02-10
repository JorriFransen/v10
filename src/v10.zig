const std = @import("std");
const log = std.log.scoped(.v10);
const options = @import("options");
const platform = @import("v10_platform.zig");
const intrinsics = @import("intrinsics.zig");

const assert = std.debug.assert;

const ThreadContext = platform.ThreadContext;
const Memory = platform.Memory;
const Input = platform.Input;
const OffscreenBuffer = platform.OffscreenBuffer;
const AudioBuffer = platform.AudioBuffer;

const os = @import("builtin").os.tag;

pub const GameState = struct {
    player_tile_map_x: u27,
    player_tile_map_y: u27,

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

    var keep_running = true;
    _ = &keep_running;

    const tile_size_in_pixels = 60;
    const tile_count_x = 17;
    const tile_count_y = 9;
    const tile_map_tiles_0_0: [tile_count_y * tile_count_x]u32 = .{
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
    const tile_map_tiles_0_1: [tile_count_y * tile_count_x]u32 = .{
        1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    };
    const tile_map_tiles_1_0: [tile_count_y * tile_count_x]u32 = .{
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
    const tile_map_tiles_1_1: [tile_count_y * tile_count_x]u32 = .{
        1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    };

    var tile_maps: [2][2]TileMap = undefined;
    tile_maps[0][0].tiles = &tile_map_tiles_0_0;
    tile_maps[0][1].tiles = &tile_map_tiles_1_0;
    tile_maps[1][0].tiles = &tile_map_tiles_0_1;
    tile_maps[1][1].tiles = &tile_map_tiles_1_1;

    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent.ptr));
    if (!game_memory.initialized) {
        game_state.* = .{
            .player_tile_map_x = 0,
            .player_tile_map_y = 0,

            .player_x = 150,
            .player_y = 150,
        };
        game_memory.initialized = true;
    }

    const world: World = .{
        .tile_size_in_meters = 1.4,
        .tile_size_in_pixels = tile_size_in_pixels,
        .tile_map_count_x = tile_maps.len,
        .tile_map_count_y = tile_maps[0].len,
        .tile_count_x = tile_count_x,
        .tile_count_y = tile_count_y,
        .tile_map_x_offset = -(tile_size_in_pixels / 2),
        .tile_map_y_offset = 0,
        .tile_maps = @ptrCast(&tile_maps),
    };

    var tile_map: *TileMap = world.getTileMap(game_state.player_tile_map_x, game_state.player_tile_map_y).?;

    const player_width: f32 = @as(f32, @floatFromInt(world.tile_size_in_pixels)) * 0.75;
    const player_height: f32 = @floatFromInt(world.tile_size_in_pixels);

    for (input.controllers) |controller| if (controller.is_connected) {
        const buttons = &controller.buttons.named;
        // if (buttons.start.ended_down) {
        //     keep_running = false;
        // }

        var d_player_x: f32 = 0;
        var d_player_y: f32 = 0;

        if (controller.is_analog) {
            d_player_x += controller.stick_average_x;
            d_player_y -= controller.stick_average_y;
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

        const new_player_pos: RawPosition = .init(game_state.player_tile_map_x, game_state.player_tile_map_y, new_player_x, new_player_y);
        var bottom_left_pos = new_player_pos;
        bottom_left_pos.map_relative_x = bottom_left_x;
        var bottom_right_pos = new_player_pos;
        bottom_right_pos.map_relative_x = bottom_right_x;

        const is_valid_tile =
            world.isEmptyPoint(new_player_pos) and
            world.isEmptyPoint(bottom_left_pos) and
            world.isEmptyPoint(bottom_right_pos);

        if (is_valid_tile) {
            const new_pos = world.getCanonicalPosition(new_player_pos);

            game_state.player_tile_map_x = new_pos.tile_x.map;
            game_state.player_tile_map_y = new_pos.tile_y.map;
            game_state.player_x = new_pos.tile_relative_x + (@as(f32, @floatFromInt(new_pos.tile_x.tile * world.tile_size_in_pixels)));
            game_state.player_y = new_pos.tile_relative_y + (@as(f32, @floatFromInt(new_pos.tile_y.tile * world.tile_size_in_pixels)));
        }
    };

    @memset(@as([]u32, @ptrCast(@alignCast(offscreen_buffer.memory))), 0xff00ff);
    // drawRectangle(offscreen_buffer, 0, 0, @floatFromInt(offscreen_buffer.width), @floatFromInt(offscreen_buffer.height), 1, 0, 1);

    for (0..world.tile_count_y) |iy| {
        const y = world.tile_map_y_offset + @as(f32, @floatFromInt(iy * world.tile_size_in_pixels));
        for (0..world.tile_count_x) |ix| {
            const x = world.tile_map_x_offset + @as(f32, @floatFromInt(ix * world.tile_size_in_pixels));
            const tile = tile_map.getTileUnchecked(&world, @intCast(ix), @intCast(iy));
            const grayscale: f32 = if (tile == 1) 1 else 0.5;
            drawRectangle(
                offscreen_buffer,
                x,
                y,
                x + @as(f32, @floatFromInt(world.tile_size_in_pixels)),
                y + @as(f32, @floatFromInt(world.tile_size_in_pixels)),
                grayscale,
                grayscale,
                grayscale,
            );
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
        // const sine_value: f32 = intrinsics.sin(game_state.t_sine);
        // const sample_value: i16 = @intFromFloat(@as(f32, @floatFromInt(tone_volume)) * sine_value);
        const sample_value: i16 = 0;

        frame.* = .{ .left = sample_value, .right = sample_value };

        // game_state.t_sine += std.math.tau / @as(f32, @floatFromInt(wave_period));
        // if (game_state.t_sine > std.math.tau) game_state.t_sine -= std.math.tau;
    }
}

pub const PackedTilePosition = packed struct(u32) {
    tile: u5,
    map: u27,
};

pub const CanonicalPosition = struct {
    tile_x: PackedTilePosition,
    tile_y: PackedTilePosition,

    tile_relative_x: f32,
    tile_relative_y: f32,
};

pub const RawPosition = struct {
    tile_map_x: u27,
    tile_map_y: u27,

    map_relative_x: f32,
    map_relative_y: f32,

    pub inline fn init(tile_map_x: u27, tile_map_y: u27, map_relative_x: f32, map_relative_y: f32) RawPosition {
        return .{
            .tile_map_x = tile_map_x,
            .tile_map_y = tile_map_y,
            .map_relative_x = map_relative_x,
            .map_relative_y = map_relative_y,
        };
    }
};

pub const TileMap = struct {
    tiles: []const u32,

    pub inline fn getTileUnchecked(this: *const TileMap, world: *const World, x: u5, y: u5) u32 {
        assert(x < world.tile_count_x);
        assert(y < world.tile_count_y);
        return this.tiles[x + (y * @as(usize, world.tile_count_x))];
    }
};

pub const World = struct {
    tile_size_in_meters: f32,
    tile_size_in_pixels: usize,

    tile_map_count_x: u27,
    tile_map_count_y: u27,

    /// per tile map
    tile_count_x: u5,
    /// per tile map
    tile_count_y: u5,

    /// drawing offset
    tile_map_x_offset: f32,
    /// drawing offset
    tile_map_y_offset: f32,

    tile_maps: []TileMap,

    pub inline fn getTileMap(this: *const World, x: u27, y: u27) ?*TileMap {
        if (x < this.tile_map_count_x and y < this.tile_map_count_y) {
            return &this.tile_maps[x + (y * @as(usize, this.tile_map_count_y))];
        }

        return null;
    }

    pub fn isEmptyPoint(world: *const World, raw_pos: RawPosition) bool {
        const pos = world.getCanonicalPosition(raw_pos);
        const tile_map_opt = world.getTileMap(pos.tile_x.map, pos.tile_y.map);
        return world.isEmptyTile(tile_map_opt, pos.tile_x.tile, pos.tile_y.tile);
    }

    pub fn isEmptyTile(world: *const World, tile_map_opt: ?*const TileMap, tile_x: u5, tile_y: u5) bool {
        var empty = false;

        if (tile_map_opt) |tile_map| {
            if (tile_x < world.tile_count_x and tile_y < world.tile_count_y) {
                const tile = tile_map.getTileUnchecked(world, tile_x, tile_y);
                empty = tile == 0;
            }
        }

        return empty;
    }

    pub inline fn getCanonicalPosition(world: *const World, raw: RawPosition) CanonicalPosition {
        var result: CanonicalPosition = .{
            .tile_x = .{ .tile = undefined, .map = @intCast(raw.tile_map_x) },
            .tile_y = .{ .tile = undefined, .map = @intCast(raw.tile_map_y) },
            .tile_relative_x = undefined,
            .tile_relative_y = undefined,
        };

        const x = raw.map_relative_x - world.tile_map_x_offset;
        const y = raw.map_relative_y - world.tile_map_y_offset;

        var test_tile_x = intrinsics.floorFloatToInt(isize, x / @as(f32, @floatFromInt(world.tile_size_in_pixels)));
        var test_tile_y = intrinsics.floorFloatToInt(isize, y / @as(f32, @floatFromInt(world.tile_size_in_pixels)));

        result.tile_relative_x = raw.map_relative_x - @as(f32, @floatFromInt(test_tile_x * @as(isize, @intCast(world.tile_size_in_pixels))));
        result.tile_relative_y = raw.map_relative_y - @as(f32, @floatFromInt(test_tile_y * @as(isize, @intCast(world.tile_size_in_pixels))));

        if (test_tile_x < 0) {
            test_tile_x += @intCast(world.tile_count_x);
            result.tile_x.map -= 1;
        } else if (test_tile_x >= world.tile_count_x) {
            test_tile_x -= @intCast(world.tile_count_x);
            result.tile_x.map += 1;
        }

        if (test_tile_y < 0) {
            test_tile_y += @intCast(world.tile_count_y);
            result.tile_y.map -= 1;
        } else if (test_tile_y >= world.tile_count_y) {
            test_tile_y -= @intCast(world.tile_count_y);
            result.tile_y.map += 1;
        }

        result.tile_x.tile = @intCast(test_tile_x);
        result.tile_y.tile = @intCast(test_tile_y);

        return result;
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

    const minx = intrinsics.floorFloatToUInt(usize, @min(@max(min_x, 0), buffer_width_f));
    const miny = intrinsics.floorFloatToUInt(usize, @min(@max(min_y, 0), buffer_height_f));
    const maxx = intrinsics.floorFloatToUInt(usize, @min(@max(max_x, 0), buffer_width_f));
    const maxy = intrinsics.floorFloatToUInt(usize, @min(@max(max_y, 0), buffer_height_f));

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
