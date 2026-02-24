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
    player_pos: WorldPosition,
};

pub export fn init(thread_context: *ThreadContext, game_memory: *Memory) callconv(.c) void {
    _ = thread_context;
    _ = game_memory;
}

pub export fn updateAndRender(thread_context: *ThreadContext, game_memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer) callconv(.c) bool {
    _ = thread_context;

    assert(@sizeOf(GameState) <= game_memory.permanent_len);

    var keep_running = true;
    _ = &keep_running;

    const tile_size_in_pixels: usize = 60;
    const tile_size_in_meters: f32 = 1.4;

    const chunk_dim = 256;
    const temp_tiles: [18][34]u32 = .{
        .{ 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        .{ 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1 },
        .{ 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1 },
        .{ 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1 },
        .{ 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1 },
        .{ 1, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1 },
        .{ 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
        .{ 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1 },
        .{ 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1 },
        .{ 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1 },
        .{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        .{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        .{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        .{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        .{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        .{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        .{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        .{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
    };

    var chunk_0_0 = std.mem.zeroes([chunk_dim][chunk_dim]u32);
    for (temp_tiles, 0..) |row, y| {
        const dest: []u32 = chunk_0_0[y][0..row.len];
        @memcpy(dest, row[0..]);
    }

    var chunks: [1][1]TileChunk = undefined;
    chunks[0][0].tiles = @as([]u32, @ptrCast(&chunk_0_0));

    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent));
    if (!game_memory.initialized) {
        game_state.* = .{
            .player_pos = .{
                .abs_tile_x = 3,
                .abs_tile_y = 1,
                .tile_relative_x = 0,
                .tile_relative_y = 0,
            },
        };
        game_memory.initialized = true;
    }

    const world: World = .{
        .tile_size_in_meters = tile_size_in_meters,
        .tile_size_in_pixels = tile_size_in_pixels,
        .meters_to_pixels = tile_size_in_pixels / tile_size_in_meters,
        .chunk_count_x = chunks.len,
        .chunk_count_y = chunks[0].len,
        .chunk_dim = chunk_dim,
        .chunks = @ptrCast(&chunks),
    };

    const player_height: f32 = 1.4;
    const player_width: f32 = player_height * 0.75;

    for (input.controllers) |controller| if (controller.is_connected) {
        const buttons = &controller.buttons.named;
        // if (buttons.start.ended_down) {
        //     keep_running = false;
        // }

        var d_player_x: f32 = 0;
        var d_player_y: f32 = 0;
        var player_speed: f32 = 2;

        if (controller.is_analog) {
            d_player_x += controller.stick_average_x;
            d_player_y += controller.stick_average_y;
        } else {
            if (buttons.move_left.ended_down) d_player_x -= 1;
            if (buttons.move_right.ended_down) d_player_x += 1;
            if (buttons.move_up.ended_down) d_player_y += 1;
            if (buttons.move_down.ended_down) d_player_y -= 1;
        }

        if (buttons.action_up.ended_down) {
            player_speed *= 2;
        }

        d_player_x *= player_speed;
        d_player_y *= player_speed;

        const new_player_x = game_state.player_pos.tile_relative_x + d_player_x * input.dt;
        const new_player_y = game_state.player_pos.tile_relative_y + d_player_y * input.dt;

        var new_player_pos = game_state.player_pos;
        new_player_pos.tile_relative_x = new_player_x;
        new_player_pos.tile_relative_y = new_player_y;
        new_player_pos.recanonicalize(&world);

        var bottom_left_pos = new_player_pos;
        bottom_left_pos.tile_relative_x -= (player_width / 2);
        bottom_left_pos.recanonicalize(&world);

        var bottom_right_pos = new_player_pos;

        bottom_right_pos.tile_relative_x += (player_width / 2);
        bottom_right_pos.recanonicalize(&world);

        const is_valid_tile =
            world.isTileEmpty(new_player_pos) and
            world.isTileEmpty(bottom_left_pos) and
            world.isTileEmpty(bottom_right_pos);

        if (is_valid_tile) {
            game_state.player_pos = new_player_pos;
        }
    };

    @memset(@as([]u32, @ptrCast(@alignCast(offscreen_buffer.memory[0..offscreen_buffer.memory_len]))), 0xff00ff);
    // drawRectangle(offscreen_buffer, 0, 0, @floatFromInt(offscreen_buffer.width), @floatFromInt(offscreen_buffer.height), 1, 0, 1);

    const player_pos = game_state.player_pos;

    const screen_center_x: f32 = @floatFromInt(@divTrunc(offscreen_buffer.width, 2));
    const screen_center_y: f32 = @floatFromInt(@divTrunc(offscreen_buffer.height, 2));

    var rel_row: i32 = -10;
    while (rel_row < 10) : (rel_row += 1) {
        var rel_column: i32 = -20;
        while (rel_column < 20) : (rel_column += 1) {
            const row: u32 = player_pos.abs_tile_y +% @as(u32, @bitCast(rel_row));
            const column: u32 = player_pos.abs_tile_x +% @as(u32, @bitCast(rel_column));

            const tile = world.getTile(column, row);
            var grayscale: f32 = if (tile == 1) 1 else 0.5;

            if (player_pos.abs_tile_x == column and player_pos.abs_tile_y == row) {
                grayscale = 0;
            }

            const tile_size: f32 = @floatFromInt(world.tile_size_in_pixels);

            const center_x: f32 = screen_center_x - (world.meters_to_pixels * player_pos.tile_relative_x) + @as(f32, @floatFromInt(rel_column * @as(i32, @intCast(world.tile_size_in_pixels))));
            const center_y: f32 = screen_center_y + (world.meters_to_pixels * player_pos.tile_relative_y) - @as(f32, @floatFromInt(rel_row * @as(i32, @intCast(world.tile_size_in_pixels))));
            const min_x: f32 = center_x - (0.5 * tile_size);
            const min_y: f32 = center_y - (0.5 * tile_size);
            const max_x: f32 = center_x + (0.5 * tile_size);
            const max_y: f32 = center_y + (0.5 * tile_size);

            drawRectangle(
                offscreen_buffer,
                min_x,
                min_y,
                max_x,
                max_y,
                grayscale,
                grayscale,
                grayscale,
            );
        }
    }

    {
        const player_width_pixels = player_width * world.meters_to_pixels;
        const player_height_pixels = player_height * world.meters_to_pixels;

        // const player_left: f32 = center_x + (world.meters_to_pixels * player_pos.tile_relative_x) - (player_width_pixels / 2);
        // const player_top: f32 = center_y - (world.meters_to_pixels * player_pos.tile_relative_y) - (player_height_pixels);

        const player_left: f32 = screen_center_x - (player_width_pixels / 2);
        const player_top: f32 = screen_center_y - (player_height_pixels);

        const player_right = player_left + (player_width_pixels);
        const player_bottom = player_top + (player_height_pixels);
        drawRectangle(offscreen_buffer, player_left, player_top, player_right, player_bottom, 1, 1, 0);
    }

    return keep_running;
}

pub export fn getAudioFrames(thread_context: *ThreadContext, game_memory: *Memory, sound_buffer: *AudioBuffer) callconv(.c) void {
    _ = thread_context;
    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent));
    outputSound(game_state, sound_buffer, 400);
}

pub fn outputSound(game_state: *GameState, buffer: *AudioBuffer, tone_hz: i32) void {
    _ = game_state;
    _ = tone_hz;
    // const tone_volume = 3000;
    // const wave_period = @divTrunc(buffer.frames_per_second, tone_hz);

    assert(buffer.frames_len >= 0);

    for (buffer.frames[0..buffer.frames_len]) |*frame| {
        // const sine_value: f32 = intrinsics.sin(game_state.t_sine);
        // const sample_value: i16 = @intFromFloat(@as(f32, @floatFromInt(tone_volume)) * sine_value);
        const sample_value: i16 = 0;

        frame.* = .{ .left = sample_value, .right = sample_value };

        // game_state.t_sine += std.math.tau / @as(f32, @floatFromInt(wave_period));
        // if (game_state.t_sine > std.math.tau) game_state.t_sine -= std.math.tau;
    }
}

pub const TileChunkPosition = struct {
    chunk_x: u32,
    chunk_y: u32,

    rel_tile_x: u32,
    rel_tile_y: u32,
};

pub const PackedTileChunkPosition = packed struct(u32) {
    tile: u8,
    chunk: u24,
};

pub fn getChunkPositionFor(abs_tile_x: u32, abs_tile_y: u32) TileChunkPosition {
    const packed_x: PackedTileChunkPosition = @bitCast(abs_tile_x);
    const packed_y: PackedTileChunkPosition = @bitCast(abs_tile_y);

    return .{
        .chunk_x = packed_x.chunk,
        .chunk_y = packed_y.chunk,
        .rel_tile_x = packed_x.tile,
        .rel_tile_y = packed_y.tile,
    };
}

pub const WorldPosition = struct {
    // Packed chunk.tile : 24.8
    abs_tile_x: u32,
    // Packed chunk.tile : 24.8
    abs_tile_y: u32,

    /// In meters, from the bottom left
    tile_relative_x: f32,
    /// In meters, from the bottom left
    tile_relative_y: f32,

    pub fn recanonicalize(this: *WorldPosition, world: *const World) void {
        world.recanonicalizeCoord(&this.abs_tile_x, &this.tile_relative_x);
        world.recanonicalizeCoord(&this.abs_tile_y, &this.tile_relative_y);
    }
};

pub const TileChunk = struct {
    tiles: []const u32,

    pub fn getTileUnchecked(this: *const TileChunk, world: *const World, x: u32, y: u32) u32 {
        assert(x < world.chunk_dim);
        assert(y < world.chunk_dim);

        return this.tiles[x + (y * world.chunk_dim)];
    }
};

pub const World = struct {
    tile_size_in_meters: f32,
    tile_size_in_pixels: usize,
    meters_to_pixels: f32,

    chunk_dim: u32,

    chunk_count_x: u24,
    chunk_count_y: u24,

    chunks: []TileChunk,

    pub inline fn getChunk(this: *const World, pos: TileChunkPosition) ?*TileChunk {
        const x = pos.chunk_x;
        const y = pos.chunk_y;

        if (x < this.chunk_count_x and y < this.chunk_count_y) {
            return &this.chunks[x + (y * this.chunk_count_y)];
        }

        return null;
    }

    pub fn getTile(world: *const World, abs_tile_x: u32, abs_tile_y: u32) u32 {
        const pos = getChunkPositionFor(abs_tile_x, abs_tile_y);
        const chunk_opt = world.getChunk(pos);
        return world.getChunkTile(chunk_opt, pos.rel_tile_x, pos.rel_tile_y);
    }

    pub fn isTileEmpty(world: *const World, can_pos: WorldPosition) bool {
        var empty = false;

        const tile_value = world.getTile(can_pos.abs_tile_x, can_pos.abs_tile_y);
        empty = tile_value == 0;

        return empty;
    }

    pub fn getChunkTile(world: *const World, chunk_opt: ?*const TileChunk, x: u32, y: u32) u32 {
        var result: u32 = 0;
        if (chunk_opt) |chunk| {
            result = chunk.getTileUnchecked(world, x, y);
        }

        return result;
    }

    pub fn recanonicalizeCoord(world: *const World, tile: *u32, tile_rel: *f32) void {
        // const tile_offset: i32 = intrinsics.floorFloatToInt(i32, tile_rel.* / world.tile_size_in_meters);
        const tile_offset: i32 = intrinsics.roundFloatToInt(i32, tile_rel.* / world.tile_size_in_meters);
        tile.* +%= @as(u32, @bitCast(tile_offset));
        tile_rel.* -= @as(f32, @floatFromInt(tile_offset)) * world.tile_size_in_meters;

        assert(tile_rel.* >= -(0.5 * world.tile_size_in_meters));
        assert(tile_rel.* <= (0.5 * world.tile_size_in_meters));
    }

    pub fn recanonicalize(world: *const World, pos: WorldPosition) WorldPosition {
        var result = pos;
        result.recanonicalize(world);
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

    var row: [*]u8 = buffer.memory + (minx * bpp) + (miny * pitch);
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
