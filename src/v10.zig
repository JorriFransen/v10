const std = @import("std");
const log = std.log.scoped(.v10);
const options = @import("options");
const platform = @import("v10_platform.zig");
const intrinsics = @import("intrinsics.zig");

const assert = std.debug.assert;

const Random = @import("v10_random.zig");
const MemoryArena = @import("v10_arena.zig");
const TileMap = @import("v10_tilemap.zig");

const ThreadContext = platform.ThreadContext;
const Memory = platform.Memory;
const Input = platform.Input;
const OffscreenBuffer = platform.OffscreenBuffer;
const AudioBuffer = platform.AudioBuffer;

const os = @import("builtin").os.tag;

pub const World = struct {
    tilemap: *TileMap,
};

pub const GameState = struct {
    world_arena: MemoryArena = undefined,
    world: *World = undefined,
    player_pos: TileMap.Position = undefined,

    backdrop: LoadedBitmap = .{},
    hero_head: LoadedBitmap = .{},
    // hero_cape: LoadedBitmap = .{},
    // hero_torso: LoadedBitmap = .{},
};

pub const LoadedBitmap = struct {
    width: u32 = 0,
    height: u32 = 0,
    pixels: []align(1) u32 = &.{},
};

pub export fn init(thread_context: *ThreadContext, game_memory: *Memory) callconv(.c) void {
    _ = thread_context;
    _ = game_memory;
}

pub export fn updateAndRender(thread_context: *ThreadContext, game_memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer) callconv(.c) bool {
    assert(@sizeOf(GameState) <= game_memory.permanent_len);

    var keep_running = true;
    _ = &keep_running;

    assert(@sizeOf(GameState) <= game_memory.transient_len);
    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent));

    if (!game_memory.initialized) {
        game_state.* = .{};

        // const asset_prefix = "/home/jorri/dev/hh_data/";
        const asset_prefix = "../data/";

        game_state.backdrop = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_background.bmp");
        game_state.hero_head = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_front_head.bmp");
        // game_state.hero_cape = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_front_cape.bmp");
        // game_state.hero_torso = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_front_torso.bmp");

        game_state.player_pos = .{
            .abs_tile_x = 3,
            .abs_tile_y = 1,
            .chunk_z = 0,
            .offset_x = 0,
            .offset_y = 0,
        };

        const game_state_size = @sizeOf(GameState);
        const world_arena_size = game_memory.permanent_len - game_state_size;

        game_state.world_arena = .init(game_memory.permanent[game_state_size .. game_state_size + world_arena_size]);
        game_state.world = game_state.world_arena.pushMemory(World);
        const world: *World = game_state.world;
        world.tilemap = game_state.world_arena.pushMemory(TileMap);
        const tilemap: *TileMap = world.tilemap;

        const chunk_count_x = 128;
        const chunk_count_y = 128;
        const chunk_count_z = 2;
        const chunk_count = chunk_count_x * chunk_count_y * chunk_count_z;
        const chunks = game_state.world_arena.pushMemory([chunk_count]TileMap.Chunk);
        for (chunks) |*chunk| chunk.tiles = &.{};

        tilemap.* = .{
            .tile_size_in_meters = 1.4,
            .chunk_count_x = chunk_count_x,
            .chunk_count_y = chunk_count_y,
            .chunk_count_z = chunk_count_z,
            .chunks = chunks,
        };

        var next_random_number_index: usize = 0;
        const screen_tile_width = 17;
        const screen_tile_height = 9;
        var screen_x: u32 = 0;
        var screen_y: u32 = 0;
        var chunk_z: u32 = 0;

        var door_left = false;
        var door_right = false;
        var door_top = false;
        var door_bottom = false;
        var door_up = false;
        var door_down = false;

        for (0..100) |_| {
            const random_number = Random.random_number_table[next_random_number_index];
            next_random_number_index += 1;

            const random_choice = if (door_up or door_down)
                random_number % 2
            else
                random_number % 3;

            var created_ladder = false;

            if (random_choice == 2) {
                if (chunk_z == 0) {
                    door_up = true;
                    created_ladder = true;
                } else {
                    door_down = true;
                    created_ladder = true;
                }
            } else if (random_choice == 1) {
                door_right = true;
            } else {
                door_top = true;
            }

            for (0..screen_tile_height) |tile_y| {
                for (0..screen_tile_width) |tile_x| {
                    const abs_tile_x: u32 = @intCast((screen_x * screen_tile_width) + tile_x);
                    const abs_tile_y: u32 = @intCast((screen_y * screen_tile_height) + tile_y);

                    var tile_value: u32 = 1;

                    if ((tile_x == 0) and (!door_left or (tile_y != (screen_tile_height / 2)))) {
                        tile_value = 2;
                    } else if ((tile_x == screen_tile_width - 1) and (!door_right or (tile_y != (screen_tile_height / 2)))) {
                        tile_value = 2;
                    } else if ((tile_y == 0) and (!door_bottom or (tile_x != (screen_tile_width / 2)))) {
                        tile_value = 2;
                    } else if ((tile_y == screen_tile_height - 1) and (!door_top or (tile_x != (screen_tile_width / 2)))) {
                        tile_value = 2;
                    }

                    if (tile_x == 10 and tile_y == 6) {
                        if (door_up) {
                            tile_value = 3;
                        } else if (door_down) {
                            tile_value = 4;
                        }
                    }

                    tilemap.setTile(&game_state.world_arena, abs_tile_x, abs_tile_y, chunk_z, tile_value);
                }
            }

            if (random_choice == 2) {
                if (chunk_z == 0) {
                    chunk_z = 1;
                } else {
                    chunk_z = 0;
                }
            } else if (random_choice == 1) {
                screen_x += 1;
            } else {
                screen_y += 1;
            }

            door_left = door_right;
            door_bottom = door_top;

            if (created_ladder) {
                door_down = !door_down;
                door_up = !door_up;
            } else {
                door_down = false;
                door_up = false;
            }

            door_right = false;
            door_top = false;
        }
        game_memory.initialized = true;
    }

    const world: *World = game_state.world;
    const tilemap: *TileMap = world.tilemap;

    const tile_size_in_pixels = 60;
    const meters_to_pixels = tile_size_in_pixels / tilemap.tile_size_in_meters;

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
            player_speed *= 5;
        }

        d_player_x *= player_speed;
        d_player_y *= player_speed;

        const new_player_x = game_state.player_pos.offset_x + d_player_x * input.dt;
        const new_player_y = game_state.player_pos.offset_y + d_player_y * input.dt;

        var new_player_pos = game_state.player_pos;
        new_player_pos.offset_x = new_player_x;
        new_player_pos.offset_y = new_player_y;
        new_player_pos.recanonicalize(tilemap);

        var bottom_left_pos = new_player_pos;
        bottom_left_pos.offset_x -= (player_width / 2);
        bottom_left_pos.recanonicalize(tilemap);

        var bottom_right_pos = new_player_pos;

        bottom_right_pos.offset_x += (player_width / 2);
        bottom_right_pos.recanonicalize(tilemap);

        if (tilemap.isTileEmpty(new_player_pos) and
            tilemap.isTileEmpty(bottom_left_pos) and
            tilemap.isTileEmpty(bottom_right_pos))
        {
            if (!TileMap.inSameTile(game_state.player_pos, new_player_pos)) {
                const tile = tilemap.getTile(new_player_pos);
                if (tile == 3) {
                    new_player_pos.chunk_z += 1;
                } else if (tile == 4) {
                    new_player_pos.chunk_z -= 1;
                }
            }
            game_state.player_pos = new_player_pos;
        }
    };

    @memset(@as([]u32, @ptrCast(@alignCast(offscreen_buffer.memory[0..offscreen_buffer.memory_len]))), 0xff00ff);
    // drawRectangle(offscreen_buffer, 0, 0, @floatFromInt(offscreen_buffer.width), @floatFromInt(offscreen_buffer.height), 1, 0, 1);

    drawBitmap(offscreen_buffer, game_state.backdrop, 0, 0);

    const player_pos = game_state.player_pos;

    const screen_center_x: f32 = @floatFromInt(@divTrunc(offscreen_buffer.width, 2));
    const screen_center_y: f32 = @floatFromInt(@divTrunc(offscreen_buffer.height, 2));

    var rel_row: i32 = -10;
    while (rel_row < 10) : (rel_row += 1) {
        var rel_column: i32 = -20;
        while (rel_column < 20) : (rel_column += 1) {
            const row: u32 = player_pos.abs_tile_y +% @as(u32, @bitCast(rel_row));
            const column: u32 = player_pos.abs_tile_x +% @as(u32, @bitCast(rel_column));

            const tile = tilemap.getTileXYZ(column, row, player_pos.chunk_z);
            if (tile > 1) {
                var grayscale: f32 = if (tile == 1) 0.5 else 1;

                if (player_pos.abs_tile_x == column and player_pos.abs_tile_y == row) {
                    grayscale = 0;
                } else if (tile > 2) {
                    grayscale = 0.25;
                }

                const tile_size: f32 = @floatFromInt(tile_size_in_pixels);

                const center_x: f32 = screen_center_x - (meters_to_pixels * player_pos.offset_x) + @as(f32, @floatFromInt(rel_column * @as(i32, @intCast(tile_size_in_pixels))));
                const center_y: f32 = screen_center_y + (meters_to_pixels * player_pos.offset_y) - @as(f32, @floatFromInt(rel_row * @as(i32, @intCast(tile_size_in_pixels))));
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
    }

    {
        const player_width_pixels = player_width * meters_to_pixels;
        const player_height_pixels = player_height * meters_to_pixels;

        const player_left: f32 = screen_center_x - (player_width_pixels / 2);
        const player_top: f32 = screen_center_y - (player_height_pixels);

        const player_right = player_left + (player_width_pixels);
        const player_bottom = player_top + (player_height_pixels);
        drawRectangle(offscreen_buffer, player_left, player_top, player_right, player_bottom, 1, 1, 0);
        drawBitmap(offscreen_buffer, game_state.hero_head, player_left, player_top);
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

    const minx = intrinsics.roundFloatToUInt(usize, @min(@max(min_x, 0), buffer_width_f));
    const miny = intrinsics.roundFloatToUInt(usize, @min(@max(min_y, 0), buffer_height_f));
    const maxx = intrinsics.roundFloatToUInt(usize, @min(@max(max_x, 0), buffer_width_f));
    const maxy = intrinsics.roundFloatToUInt(usize, @min(@max(max_y, 0), buffer_height_f));

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

pub fn drawBitmap(buffer: *OffscreenBuffer, bitmap: LoadedBitmap, x: f32, y: f32) void {
    const pitch: usize = @intCast(buffer.pitch);
    const bpp: usize = @intCast(buffer.bytes_per_pixel);

    const buffer_width_f: f32 = @floatFromInt(buffer.width);
    const buffer_height_f: f32 = @floatFromInt(buffer.height);
    const bitmap_width_f: f32 = @floatFromInt(bitmap.width);
    const bitmap_height_f: f32 = @floatFromInt(bitmap.height);

    const minx = intrinsics.roundFloatToUInt(usize, @min(@max(x, 0), buffer_width_f));
    const miny = intrinsics.roundFloatToUInt(usize, @min(@max(y, 0), buffer_height_f));
    const maxx = intrinsics.roundFloatToUInt(usize, @min(@max(x + bitmap_width_f, 0), buffer_width_f));
    const maxy = intrinsics.roundFloatToUInt(usize, @min(@max(y + bitmap_height_f, 0), buffer_height_f));

    var source_row: [*]align(1) u32 = bitmap.pixels.ptr + (bitmap.width * (bitmap.height - 1));
    var dest_row: [*]u8 = buffer.memory + (minx * bpp) + (miny * pitch);

    var iy: usize = @intCast(miny);
    while (iy < maxy) : (iy += 1) {
        var source: [*]align(1) u32 = source_row;
        var dest: [*]u32 = @ptrCast(@alignCast(dest_row));

        var ix: usize = @intCast(minx);
        while (ix < maxx) : (ix += 1) {
            dest[0] = source[0];

            source += 1;
            dest += 1;
        }

        dest_row += @intCast(buffer.pitch);
        source_row -= bitmap.width;
    }
}

pub const DEBUG = if (options.internal_build) struct {
    pub const BitmapHeader = packed struct {
        file_type: u16,
        file_size: u32,
        reserved_1: u16,
        reserved_2: u16,
        bitmap_offset: u32,
        header_size: u32,
        width: i32,
        height: i32,
        planes: u16,
        bits_per_pixel: u16,
        compression: u32,
        image_size: u32,
        x_pixels_per_meter: u32,
        y_pixels_per_meter: u32,
        color_count: u32,
        important_color_count: u32,
        red_mask: u32,
        green_mask: u32,
        blue_mask: u32,
        alpha_mask: u32,
    };

    pub fn loadBMP(pd: *const platform.DEBUG, thread_context: *ThreadContext, filename: [:0]const u8) LoadedBitmap {
        var result: LoadedBitmap = .{};

        const read_result = pd.readEntireFile(thread_context, filename, filename.len);
        if (read_result.size != 0) {
            const content = read_result.slice();

            assert(content.len >= @sizeOf(BitmapHeader));
            const header: *BitmapHeader = @ptrCast(@alignCast(content));
            assert(header.header_size >= 40); // Earlier types are not binary compatible

            const magic: [2]u8 = @bitCast(header.file_type);
            assert(std.mem.eql(u8, magic[0..], "BM"));

            const pixel_count: u32 = @intCast(header.width * header.height);

            assert(header.bits_per_pixel == 32); // TODO: account for scan line alignment
            result.pixels = @as([*]align(1) u32, @ptrCast(content.ptr + header.bitmap_offset))[0..pixel_count];
            assert(result.pixels.len == pixel_count);
            result.width = @intCast(header.width);
            result.height = @intCast(header.height);

            if (!(header.alpha_mask == 0xff000000 and header.red_mask == 0x00ff0000 and header.green_mask == 0x0000ff00 and header.blue_mask == 0x000000ff)) {

                // ARGB expected

                // RGBA
                if (header.alpha_mask == 0x000000ff and header.red_mask == 0xff000000 and header.green_mask == 0x00ff0000 and header.blue_mask == 0x0000ff00) {
                    for (result.pixels) |*pixel| {
                        pixel.* = (pixel.* >> 8) | (pixel.* << 24);
                    }
                } else {
                    log.warn("Unsupported bmp format ({s})", .{filename});
                }
            }
        }

        log.debug("Loaded bmp: {s} ({},{})", .{ filename, result.width, result.height });

        return result;
    }
} else void;
