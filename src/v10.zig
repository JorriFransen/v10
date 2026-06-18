const std = @import("std");
const log = std.log.scoped(.v10);
const options = @import("options");
const platform = @import("v10_platform.zig");
const intrinsics = @import("intrinsics.zig");

const math = @import("math.zig");
const V2 = math.V2;
const v2 = V2.init;

const assert = std.debug.assert;

const Random = @import("random.zig");
const MemoryArena = @import("arena.zig");
const TileMap = @import("tilemap.zig");

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

    camera_pos: TileMap.Position = undefined,
    player_pos: TileMap.Position = undefined,
    player_velocity: V2 = .{},

    backdrop: LoadedBitmap = .{},
    hero_facing_direction: u32 = 0,
    hero_bitmaps: [4]HeroBitmaps = std.mem.zeroes([4]HeroBitmaps),
};

pub const LoadedBitmap = struct {
    width: u32 = 0,
    height: u32 = 0,
    pixels: []align(1) u32 = &.{},
};

pub const HeroBitmaps = struct {
    alignment: V2 = .{},
    head: LoadedBitmap = .{},
    cape: LoadedBitmap = .{},
    torso: LoadedBitmap = .{},
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

        const game_state_size = @sizeOf(GameState);
        const world_arena_size = game_memory.permanent_len - game_state_size;

        game_state.world_arena = .init(game_memory.permanent[game_state_size .. game_state_size + world_arena_size]);

        const asset_prefix = "../../hh_assets";
        // const asset_prefix = "../data/";

        game_state.backdrop = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_background.bmp");

        game_state.hero_bitmaps[0].head = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_right_head.bmp");
        game_state.hero_bitmaps[0].cape = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_right_cape.bmp");
        game_state.hero_bitmaps[0].torso = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_right_torso.bmp");
        game_state.hero_bitmaps[0].alignment = v2(72, 182);

        game_state.hero_bitmaps[1].head = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_back_head.bmp");
        game_state.hero_bitmaps[1].cape = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_back_cape.bmp");
        game_state.hero_bitmaps[1].torso = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_back_torso.bmp");
        game_state.hero_bitmaps[1].alignment = v2(72, 182);

        game_state.hero_bitmaps[2].head = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_left_head.bmp");
        game_state.hero_bitmaps[2].cape = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_left_cape.bmp");
        game_state.hero_bitmaps[2].torso = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_left_torso.bmp");
        game_state.hero_bitmaps[2].alignment = v2(72, 182);

        game_state.hero_bitmaps[3].head = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_front_head.bmp");
        game_state.hero_bitmaps[3].cape = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_front_cape.bmp");
        game_state.hero_bitmaps[3].torso = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "/test/test_hero_front_torso.bmp");
        game_state.hero_bitmaps[3].alignment = v2(72, 182);

        game_state.camera_pos = .{
            .abs_tile_x = 17 / 2,
            .abs_tile_y = 9 / 2,
            .chunk_z = 0,
        };
        game_state.player_pos = .{
            .abs_tile_x = 1,
            .abs_tile_y = 3,
            .chunk_z = 0,
            .offset = .init(5, 5),
        };
        game_state.player_velocity = v2(0, 0);

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

        var player_acceleration: V2 = .{};

        if (controller.is_analog) {
            // game_state.tone_hz = 400 + (50 * controller.stick_average_y);

            player_acceleration.x += controller.stick_average_x;
            player_acceleration.y += controller.stick_average_y;
        } else {
            if (buttons.move_up.ended_down) {
                player_acceleration.y = 1;
                game_state.hero_facing_direction = 1;
            }
            if (buttons.move_down.ended_down) {
                player_acceleration.y = -1;
                game_state.hero_facing_direction = 3;
            }
            if (buttons.move_left.ended_down) {
                player_acceleration.x = -1;
                game_state.hero_facing_direction = 2;
            }
            if (buttons.move_right.ended_down) {
                player_acceleration.x = 1;
                game_state.hero_facing_direction = 0;
            }
        }

        if (player_acceleration.x != 0 and player_acceleration.y != 0) {
            player_acceleration = player_acceleration.mul(0.707106781187);
        }

        var player_speed: f32 = 10; // ms/s^2
        if (buttons.action_up.ended_down) {
            player_speed = 50; // ms/s^2
        }

        player_acceleration = player_acceleration.mul(player_speed);

        player_acceleration = player_acceleration.add(game_state.player_velocity.mul(-1.5));

        var new_player_pos = game_state.player_pos;
        new_player_pos.offset = player_acceleration.mul(0.5 * math.square(input.dt))
            .add(game_state.player_velocity.mul(input.dt))
            .add(new_player_pos.offset);

        game_state.player_velocity = game_state.player_velocity.add(player_acceleration.mul(input.dt));
        new_player_pos.recanonicalize(tilemap);

        var bottom_left_pos = new_player_pos;
        bottom_left_pos.offset.x -= (player_width / 2);
        bottom_left_pos.recanonicalize(tilemap);

        var bottom_right_pos = new_player_pos;

        bottom_right_pos.offset.x += (player_width / 2);
        bottom_right_pos.recanonicalize(tilemap);

        var collision_position_opt: ?TileMap.Position = null;
        if (!tilemap.isTileEmpty(new_player_pos)) {
            collision_position_opt = new_player_pos;
        }
        if (!tilemap.isTileEmpty(bottom_left_pos)) {
            collision_position_opt = bottom_left_pos;
        }
        if (!tilemap.isTileEmpty(bottom_right_pos)) {
            collision_position_opt = bottom_right_pos;
        }

        if (collision_position_opt) |col_p| {
            var wall_normal: V2 = .{};

            if (col_p.abs_tile_x < game_state.player_pos.abs_tile_x)
                wall_normal = v2(1, 0);
            if (col_p.abs_tile_x > game_state.player_pos.abs_tile_x)
                wall_normal = v2(-1, 0);
            if (col_p.abs_tile_y < game_state.player_pos.abs_tile_y)
                wall_normal = v2(0, 1);
            if (col_p.abs_tile_y > game_state.player_pos.abs_tile_y)
                wall_normal = v2(0, -1);

            // game_state.player_velocity = game_state.player_velocity.sub(wall_normal.mul(1 * game_state.player_velocity.inner(wall_normal)));
            game_state.player_velocity = V2.sub(
                game_state.player_velocity,
                wall_normal.mul(1 * game_state.player_velocity.inner(wall_normal)),
            );
        } else {
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
        game_state.camera_pos.chunk_z = game_state.player_pos.chunk_z;

        const diff = tilemap.subtract(&game_state.player_pos, &game_state.camera_pos);

        if (diff.xy.x > (17 / 2) * tilemap.tile_size_in_meters) {
            game_state.camera_pos.abs_tile_x +%= 17;
        } else if (diff.xy.x < -(17 / 2) * tilemap.tile_size_in_meters) {
            game_state.camera_pos.abs_tile_x -%= 17;
        }

        if (diff.xy.y > (9 / 2) * tilemap.tile_size_in_meters) {
            game_state.camera_pos.abs_tile_y +%= 9;
        } else if (diff.xy.y < -(9 / 2) * tilemap.tile_size_in_meters) {
            game_state.camera_pos.abs_tile_y -%= 9;
        }
    };

    @memset(@as([]u32, @ptrCast(@alignCast(offscreen_buffer.memory[0..offscreen_buffer.memory_len]))), 0xff00ff);
    // drawRectangle(offscreen_buffer, 0, 0, @floatFromInt(offscreen_buffer.width), @floatFromInt(offscreen_buffer.height), 1, 0, 1);

    drawBitmap(offscreen_buffer, game_state.backdrop, .{}, .{});

    const camera_pos = &game_state.camera_pos;

    const screen_center = v2(
        @floatFromInt(@divTrunc(offscreen_buffer.width, 2)),
        @floatFromInt(@divTrunc(offscreen_buffer.height, 2)),
    );

    var rel_row: i32 = -10;
    while (rel_row < 10) : (rel_row += 1) {
        var rel_column: i32 = -20;
        while (rel_column < 20) : (rel_column += 1) {
            const row: u32 = camera_pos.abs_tile_y +% @as(u32, @bitCast(rel_row));
            const column: u32 = camera_pos.abs_tile_x +% @as(u32, @bitCast(rel_column));

            const tile = tilemap.getTileXYZ(column, row, camera_pos.chunk_z);
            if (tile > 1) {
                var grayscale: f32 = if (tile == 1) 0.5 else 1;

                if (camera_pos.abs_tile_x == column and camera_pos.abs_tile_y == row) {
                    grayscale = 0;
                } else if (tile > 2) {
                    grayscale = 0.25;
                }

                const half_tile_size = V2.scalar(@floatFromInt(tile_size_in_pixels / 2));

                const center = v2(
                    screen_center.x - (meters_to_pixels * camera_pos.offset.x) + @as(f32, @floatFromInt(rel_column * @as(i32, @intCast(tile_size_in_pixels)))),
                    screen_center.y + (meters_to_pixels * camera_pos.offset.y) - @as(f32, @floatFromInt(rel_row * @as(i32, @intCast(tile_size_in_pixels)))),
                );
                const min = center.sub(half_tile_size);
                const max = center.add(half_tile_size);

                drawRectangle(offscreen_buffer, min, max, grayscale, grayscale, grayscale);
            }
        }
    }

    {
        const player_pos = &game_state.player_pos;

        const player_size = v2(player_width, player_height).mul(meters_to_pixels);

        const diff = tilemap.subtract(player_pos, camera_pos).xy.mul(meters_to_pixels);

        const player_ground_point = v2(screen_center.x + diff.x, screen_center.y - diff.y);

        const player_top_left = v2(
            player_ground_point.x - (player_size.x / 2),
            player_ground_point.y - (player_size.y),
        );
        const player_bottom_right = player_top_left.add(player_size);

        drawRectangle(offscreen_buffer, player_top_left, player_bottom_right, 1, 1, 0);

        const hero_bitmap = &game_state.hero_bitmaps[game_state.hero_facing_direction];
        drawBitmap(offscreen_buffer, hero_bitmap.torso, player_ground_point, hero_bitmap.alignment);
        drawBitmap(offscreen_buffer, hero_bitmap.cape, player_ground_point, hero_bitmap.alignment);
        drawBitmap(offscreen_buffer, hero_bitmap.head, player_ground_point, hero_bitmap.alignment);
    }

    return keep_running;
}

pub export fn getAudioFrames(thread_context: *ThreadContext, game_memory: *Memory, sound_buffer: *AudioBuffer) callconv(.c) void {
    _ = thread_context;
    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent));
    outputSound(game_state, sound_buffer);
}

pub fn outputSound(game_state: *GameState, buffer: *AudioBuffer) void {
    _ = game_state;
    // _ = tone_hz;
    // const tone_volume = 4000;
    // const wave_period = @as(f32, @floatFromInt(buffer.frames_per_second)) / game_state.tone_hz;

    assert(buffer.frames_len >= 0);

    for (buffer.frames[0..buffer.frames_len]) |*frame| {
        // const sine_value: f32 = intrinsics.sin(game_state.t_sine);
        // const sample_value: i16 = @intFromFloat(@as(f32, @floatFromInt(tone_volume)) * sine_value);
        // sample_value = 0;
        const sample_value: i16 = 0;

        frame.* = .{ .left = sample_value, .right = sample_value };

        // game_state.t_sine += std.math.tau / wave_period;
        // if (game_state.t_sine > std.math.tau) game_state.t_sine -= std.math.tau;
    }
}

pub const ColorU8ARGB = packed struct(u32) {
    b: u8,
    g: u8,
    r: u8,
    a: u8,

    pub inline fn asU32(this: ColorU8ARGB) u32 {
        return @bitCast(this);
    }

    pub inline fn fromU32(int: u32) ColorU8ARGB {
        return @bitCast(int);
    }

    pub inline fn fromF32RGB(rf: f32, gf: f32, bf: f32) ColorU8ARGB {
        return .{
            .r = @intFromFloat(rf * 255),
            .g = @intFromFloat(gf * 255),
            .b = @intFromFloat(bf * 255),
            .a = 255,
        };
    }
};

pub fn drawRectangle(buffer: *OffscreenBuffer, min: V2, max: V2, r: f32, g: f32, b: f32) void {
    const pitch: usize = @intCast(buffer.pitch);
    const bpp: usize = @intCast(buffer.bytes_per_pixel);

    const buffer_width_f: f32 = @floatFromInt(buffer.width);
    const buffer_height_f: f32 = @floatFromInt(buffer.height);

    const minx = intrinsics.roundFloatToUInt(usize, @min(@max(min.x, 0), buffer_width_f));
    const miny = intrinsics.roundFloatToUInt(usize, @min(@max(min.y, 0), buffer_height_f));
    const maxx = intrinsics.roundFloatToUInt(usize, @min(@max(max.x, 0), buffer_width_f));
    const maxy = intrinsics.roundFloatToUInt(usize, @min(@max(max.y, 0), buffer_height_f));

    assert(bpp == @sizeOf(u32));

    const color = ColorU8ARGB.fromF32RGB(r, g, b);

    var row: [*]u8 = buffer.memory + (minx * bpp) + (miny * pitch);
    var y: usize = @intCast(miny);
    while (y < maxy) : (y += 1) {
        var pixel: [*]u32 = @ptrCast(@alignCast(row));
        var x: usize = @intCast(minx);
        while (x < maxx) : (x += 1) {
            pixel[0] = color.asU32();
            pixel += 1;
        }

        row += pitch;
    }
}

pub fn drawBitmap(buffer: *OffscreenBuffer, bitmap: LoadedBitmap, pos_: V2, alignment: V2) void {
    const pitch: usize = @intCast(buffer.pitch);
    const bpp: usize = @intCast(buffer.bytes_per_pixel);

    const pos = pos_.sub(alignment);
    const buf_size = v2(@floatFromInt(buffer.width), @floatFromInt(buffer.height));
    const bitmap_size = v2(@floatFromInt(bitmap.width), @floatFromInt(bitmap.height));
    const max_pos = pos.add(bitmap_size);

    const source_offset_x: usize = @intFromFloat(-@min(pos.x, 0));
    const source_offset_y: usize = @intFromFloat(-@min(pos.y, 0));

    const minx = intrinsics.roundFloatToUInt(usize, @min(@max(pos.x, 0), buf_size.x));
    const miny = intrinsics.roundFloatToUInt(usize, @min(@max(pos.y, 0), buf_size.y));
    const maxx = intrinsics.roundFloatToUInt(usize, @min(@max(max_pos.x, 0), buf_size.x));
    const maxy = intrinsics.roundFloatToUInt(usize, @min(@max(max_pos.y, 0), buf_size.y));

    // TEMPORARY
    if (bitmap.pixels.len == 0) return;
    // TEMPORARY

    var source_row: [*]align(1) u32 = bitmap.pixels.ptr + (bitmap.width * (bitmap.height - 1)) + source_offset_x - (bitmap.width * source_offset_y);
    var dest_row: [*]u8 = buffer.memory + (minx * bpp) + (miny * pitch);

    var y: usize = @intCast(miny);
    while (y < maxy) : (y += 1) {
        var source: [*]align(1) u32 = source_row;
        var dest: [*]u32 = @ptrCast(@alignCast(dest_row));

        var x: usize = @intCast(minx);
        while (x < maxx) : (x += 1) {
            const sc = ColorU8ARGB.fromU32(source[0]);
            const dc = ColorU8ARGB.fromU32(dest[0]);

            const a: f32 = @as(f32, @floatFromInt(sc.a)) / 255;
            const sr: f32 = sc.r;
            const sg: f32 = sc.g;
            const sb: f32 = sc.b;

            const dr: f32 = dc.r;
            const dg: f32 = dc.g;
            const db: f32 = dc.b;

            const r: f32 = (1 - a) * dr + a * sr;
            const g: f32 = (1 - a) * dg + a * sg;
            const b: f32 = (1 - a) * db + a * sb;

            dest[0] = (ColorU8ARGB{
                .r = @intFromFloat(r + 0.5),
                .g = @intFromFloat(g + 0.5),
                .b = @intFromFloat(b + 0.5),
                .a = 255,
            }).asU32();

            source += 1;
            dest += 1;
        }

        dest_row += @intCast(buffer.pitch);
        source_row -= bitmap.width;
    }
}

pub const DEBUG = struct {
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
            assert(header.compression == 3);

            const magic: [2]u8 = @bitCast(header.file_type);
            assert(std.mem.eql(u8, magic[0..], "BM"));

            const pixel_count: u32 = @intCast(header.width * header.height);

            assert(header.bits_per_pixel == 32); // TODO: account for scan line alignment
            result.pixels = @as([*]align(1) u32, @ptrCast(content.ptr + header.bitmap_offset))[0..pixel_count];
            assert(result.pixels.len == pixel_count);
            result.width = @intCast(header.width);
            result.height = @intCast(header.height);

            assert(header.alpha_mask == ~(header.red_mask | header.green_mask | header.blue_mask));
            assert(@popCount(header.red_mask) == 8);
            assert(@popCount(header.green_mask) == 8);
            assert(@popCount(header.blue_mask) == 8);
            assert(@popCount(header.alpha_mask) == 8);

            const red_shift = intrinsics.findLSBSet(header.red_mask);
            const green_shift = intrinsics.findLSBSet(header.green_mask);
            const blue_shift = intrinsics.findLSBSet(header.blue_mask);
            const alpha_shift = intrinsics.findLSBSet(header.alpha_mask);

            // Don't need to check *_shift.found, assertions on popcount already guard this

            if (!(header.alpha_mask == 0xff000000 and header.red_mask == 0x00ff0000 and header.green_mask == 0x0000ff00 and header.blue_mask == 0x000000ff)) {
                for (result.pixels) |*pixel| {
                    const c = pixel.*;

                    pixel.* = (ColorU8ARGB{
                        .a = @intCast((c >> @intCast(alpha_shift.index)) & 0xff),
                        .r = @intCast((c >> @intCast(red_shift.index)) & 0xff),
                        .g = @intCast((c >> @intCast(green_shift.index)) & 0xff),
                        .b = @intCast((c >> @intCast(blue_shift.index)) & 0xff),
                    }).asU32();
                }
            }
        }

        log.debug("Loaded bmp: {s} ({},{})", .{ filename, result.width, result.height });

        return result;
    }
};
