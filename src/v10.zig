const std = @import("std");
const log = std.log.scoped(.v10);
const options = @import("options");
const common = @import("v10_common");
const intrinsics = @import("intrinsics.zig");

const SimRegion = @import("sim_region.zig");
const Entity = SimRegion.Entity;
pub const EntityIndex = SimRegion.EntityIndex;
const EntityType = SimRegion.EntityType;
const EntityReference = SimRegion.EntityReference;
const HitPoint = SimRegion.HitPoint;
const MoveSpec = SimRegion.MoveSpec;

const entities = @import("entity.zig");

const math = @import("math");
const V2 = math.V2;
const v2 = V2.init;
const v2i = V2.initSigned;
const v2u = V2.initUnsigned;
const V4 = math.V4;
const v4 = V4.init;
const Rect = math.Rect;

const assert = std.debug.assert;

const Random = @import("random.zig");
const MemoryArena = @import("arena.zig");
const World = @import("world.zig");

const ThreadContext = common.ThreadContext;
const Memory = common.Memory;
const Input = common.Input;
const OffscreenBuffer = common.OffscreenBuffer;
const AudioBuffer = common.AudioBuffer;

const os = @import("builtin").os.tag;

pub const std_options = common.std_options;

pub const LowEntity = struct {
    sim: SimRegion.Entity = .{},
    p: World.Position = .null,
};

pub const EntityVisiblePiece = struct {
    bitmap: ?*const LoadedBitmap,
    offset: V2,
    offset_z: f32,
    entity_z_c: f32,

    r: f32,
    g: f32,
    b: f32,
    a: f32,

    dim: V2,
};

pub const EntityVisiblePieceGroup = struct {
    game_state: *GameState,
    count: u32 = 0,
    pieces: [16]EntityVisiblePiece = undefined,
};

pub const ControlledHero = struct {
    index: EntityIndex = 0,
    ddp: V2 = .zero,
    dz: f32 = 0,
    d_sword: V2 = .zero,
};

pub const PairwiseCollisionRule = struct {
    pub const double_entries = true;

    should_collide: bool,
    storage_index_a: EntityIndex,
    storage_index_b: EntityIndex,

    next_in_hash: ?*PairwiseCollisionRule = null,
};

pub const GameState = struct {
    const screen_tile_width: i32 = 17;
    const screen_tile_height: i32 = 9;
    const controller_count = @typeInfo(@FieldType(Input, "controllers")).array.len;

    world_arena: MemoryArena = undefined,
    world: *World = undefined,

    meters_to_pixels: f32 = 0,

    camera_following_entity_index: EntityIndex = 0,
    camera_pos: World.Position = .zero,

    controlled_heroes: [controller_count]ControlledHero = @splat(std.mem.zeroes(ControlledHero)),

    low_entity_count: u32 = 0,
    low_entities: [100_000]LowEntity = @splat(.{}),

    backdrop: LoadedBitmap = .{},
    hero_shadow: LoadedBitmap = .{},
    hero_bitmaps: [4]HeroBitmaps = std.mem.zeroes([4]HeroBitmaps),

    tree: LoadedBitmap = .{},
    sword: LoadedBitmap = .{},

    // Must be power of 2
    collision_rule_hash: [16]?*PairwiseCollisionRule = @splat(null),
    first_free_collision_rule: ?*PairwiseCollisionRule = null,
};

pub const AddLowEntityResult = struct {
    low: *LowEntity,
    low_index: EntityIndex,
};

pub inline fn getLowEntity(game_state: *GameState, index: EntityIndex) ?*LowEntity {
    var result: ?*LowEntity = null;

    if (index > 0 and index < game_state.low_entity_count) {
        result = &game_state.low_entities[index];
    }

    return result;
}

pub fn addLowEntity(game_state: *GameState, entity_type: EntityType, p: World.Position) AddLowEntityResult {
    assert(game_state.low_entity_count < game_state.low_entities.len);
    assert(game_state.low_entity_count < math.maxInt(u32));

    const low_index: EntityIndex = game_state.low_entity_count;
    game_state.low_entity_count += 1;

    const low_entity = &game_state.low_entities[low_index];
    low_entity.* = .{};
    low_entity.sim.type = entity_type;
    low_entity.p = .null;

    game_state.world.changeEntityLocation(&game_state.world_arena, low_index, low_entity, p);

    const result = AddLowEntityResult{
        .low = low_entity,
        .low_index = low_index,
    };

    return result;
}

pub fn addWall(game_state: *GameState, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const p = game_state.world.chunkPositionFromTilePosition(abs_tile_x, abs_tile_y, abs_tile_z);
    const entity = addLowEntity(game_state, .wall, p);

    entity.low.sim.size = V2.scalar(game_state.world.tile_side_in_meters);
    entity.low.sim.flags.collides = true;

    return entity;
}

pub fn addPlayer(game_state: *GameState) AddLowEntityResult {
    const entity = addLowEntity(game_state, .hero, game_state.camera_pos);

    entity.low.sim.size = v2(1, 0.5);
    entity.low.sim.flags.collides = true;

    initHitpoints(&entity.low.sim, 3);

    const sword = addSword(game_state);
    entity.low.sim.sword = EntityReference{ .index = sword.low_index };

    if (game_state.camera_following_entity_index == 0) {
        game_state.camera_following_entity_index = entity.low_index;
    }

    return entity;
}

pub fn addMonster(game_state: *GameState, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const p = game_state.world.chunkPositionFromTilePosition(abs_tile_x, abs_tile_y, abs_tile_z);
    const entity = addLowEntity(game_state, .monster, p);

    initHitpoints(&entity.low.sim, 3);
    entity.low.sim.size = v2(1, 0.5);
    entity.low.sim.flags.collides = true;

    return entity;
}

pub fn addFamiliar(game_state: *GameState, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const p = game_state.world.chunkPositionFromTilePosition(abs_tile_x, abs_tile_y, abs_tile_z);
    const entity = addLowEntity(game_state, .familiar, p);

    entity.low.sim.size = v2(1, 0.5);

    return entity;
}

pub fn addSword(game_state: *GameState) AddLowEntityResult {
    const entity = addLowEntity(game_state, .sword, .null);

    entity.low.sim.size = v2(1, 0.5);
    entity.low.sim.flags.non_spatial = true;

    return entity;
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

fn initHitpoints(entity: *Entity, count: u32) void {
    assert(count <= entity.hitpoints.len);
    entity.hitpoint_max = count;
    @memset(
        entity.hitpoints[0..entity.hitpoint_max],
        .{ .amount = HitPoint.max_amount },
    );
}

fn drawHitpoints(entity: *Entity, piece_group: *EntityVisiblePieceGroup) void {
    if (entity.hitpoint_max >= 1) {
        const health_dim = v2(0.2, 0.2);
        const spacing_x = health_dim.x * 1.5;

        var hit_p = v2(
            -0.5 * @as(f32, @floatFromInt(entity.hitpoint_max - 1)) * spacing_x,
            -0.25,
        );

        for (entity.hitpoints[0..entity.hitpoint_max]) |*hit_point| {
            var color = v4(1, 0, 0, 1);
            if (hit_point.amount == 0) {
                color = v4(0.2, 0.2, 0.2, 1);
            }

            pushRect(piece_group, hit_p, 0, health_dim, color, .{ .entity_z_c = 0 });
            hit_p.x += spacing_x;
        }
    }
}

pub inline fn addCollisionRule(game_state: *GameState, storage_index_a: EntityIndex, storage_index_b: EntityIndex, should_collide: bool) void {
    if (PairwiseCollisionRule.double_entries) {
        addCollisionRuleRaw(game_state, storage_index_a, storage_index_b, should_collide);
        addCollisionRuleRaw(game_state, storage_index_b, storage_index_a, should_collide);
    } else {
        addCollisionRuleRaw(game_state, storage_index_a, storage_index_b, should_collide);
    }
}

pub fn addCollisionRuleRaw(game_state: *GameState, storage_index_a_: EntityIndex, storage_index_b_: EntityIndex, should_collide: bool) void {
    const default_order = .{ storage_index_a_, storage_index_b_ };

    const storage_index_a, const storage_index_b = if (PairwiseCollisionRule.double_entries)
        default_order
    else if (storage_index_a_ > storage_index_b_)
        .{ storage_index_b_, storage_index_a_ }
    else
        default_order;

    const hash_bucket = storage_index_a & (game_state.collision_rule_hash.len - 1);
    var rule_opt: ?*PairwiseCollisionRule = game_state.collision_rule_hash[hash_bucket];

    var found_opt: ?*PairwiseCollisionRule = null;

    while (rule_opt) |rule| : (rule_opt = rule.next_in_hash) {
        if (rule.storage_index_a == storage_index_a and
            rule.storage_index_b == storage_index_b)
        {
            found_opt = rule;
            break;
        }
    }

    if (found_opt == null) {
        found_opt = game_state.first_free_collision_rule;
        if (found_opt) |found| {
            game_state.first_free_collision_rule = found.next_in_hash;
        } else {
            found_opt = game_state.world_arena.pushMemory(PairwiseCollisionRule);
        }

        found_opt.?.next_in_hash = game_state.collision_rule_hash[hash_bucket];
        game_state.collision_rule_hash[hash_bucket] = found_opt;
    }

    if (found_opt) |found| {
        found.should_collide = should_collide;
        found.storage_index_a = storage_index_a;
        found.storage_index_b = storage_index_b;
    }
}

pub fn clearCollisionRulesFor(game_state: *GameState, storage_index: EntityIndex) void {
    if (PairwiseCollisionRule.double_entries) {
        const old_freelist_head = game_state.first_free_collision_rule;

        removeCollisionRule(game_state, storage_index);

        var freelist_rule_opt = game_state.first_free_collision_rule;
        while (freelist_rule_opt) |freelist_rule| {
            assert(freelist_rule.storage_index_a == storage_index);

            removeCollisionRule(game_state, freelist_rule.storage_index_b);

            if (freelist_rule.next_in_hash == old_freelist_head) break;
            freelist_rule_opt = freelist_rule.next_in_hash;
        }
    } else {
        for (&game_state.collision_rule_hash) |*entry| {
            var rule_opt: *?*PairwiseCollisionRule = entry;

            while (rule_opt.*) |rule| {
                if (rule.storage_index_a == storage_index or rule.storage_index_b == storage_index) {
                    const removed_rule = rule;
                    rule_opt.* = rule.next_in_hash;

                    removed_rule.next_in_hash = game_state.first_free_collision_rule;
                    game_state.first_free_collision_rule = removed_rule;
                } else {
                    rule_opt = &rule.next_in_hash;
                }
            }
        }
    }
}

pub fn removeCollisionRule(game_state: *GameState, storage_index: EntityIndex) void {
    const hash_bucket = storage_index & (game_state.collision_rule_hash.len - 1);
    var rule_opt: *?*PairwiseCollisionRule = &game_state.collision_rule_hash[hash_bucket];

    while (rule_opt.*) |rule| {
        if (rule.storage_index_a == storage_index) {
            const removed = rule;
            rule_opt.* = rule.next_in_hash;

            removed.next_in_hash = game_state.first_free_collision_rule;
            game_state.first_free_collision_rule = removed;
        } else {
            rule_opt = &rule.next_in_hash;
        }
    }
}

pub fn drawRectangle(buffer: *OffscreenBuffer, min: V2, max: V2, r: f32, g: f32, b: f32) void {
    const pitch: usize = @intCast(buffer.pitch);
    const bpp: usize = @intCast(buffer.bytes_per_pixel);

    const buffer_width_f: f32 = @floatFromInt(buffer.width);
    const buffer_height_f: f32 = @floatFromInt(buffer.height);

    const minx: usize = @round(@min(@max(min.x, 0), buffer_width_f));
    const miny: usize = @round(@min(@max(min.y, 0), buffer_height_f));
    const maxx: usize = @round(@min(@max(max.x, 0), buffer_width_f));
    const maxy: usize = @round(@min(@max(max.y, 0), buffer_height_f));

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

pub fn drawBitmap(buffer: *OffscreenBuffer, bitmap: *const LoadedBitmap, px: f32, py: f32, c_alpha: f32) void {
    const pitch: usize = @intCast(buffer.pitch);
    const bpp: usize = @intCast(buffer.bytes_per_pixel);

    const real_x: f32 = px;
    const real_y: f32 = py;

    var min_x: i32 = @round(real_x);
    var min_y: i32 = @round(real_y);
    var max_x: i32 = min_x + @as(i32, @intCast(bitmap.width));
    var max_y: i32 = min_y + @as(i32, @intCast(bitmap.height));

    var source_offset_x: u32 = 0;
    if (min_x < 0) {
        source_offset_x = @intCast(-min_x);
        min_x = 0;
    }

    var source_offset_y: u32 = 0;
    if (min_y < 0) {
        source_offset_y = @intCast(-min_y);
        min_y = 0;
    }

    if (max_x > buffer.width) {
        max_x = @intCast(buffer.width);
    }

    if (max_y > buffer.height) {
        max_y = @intCast(buffer.height);
    }

    const minx: u32 = @intCast(min_x);
    const miny: u32 = @intCast(min_y);
    const maxx: u32 = @intCast(@max(0, max_x));
    const maxy: u32 = @intCast(@max(0, max_y));

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

            const a: f32 = (@as(f32, @floatFromInt(sc.a)) / 255 * c_alpha);

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

        // game_state.t_sine += math.tau / wave_period;
        // if (game_state.t_sine > math.tau) game_state.t_sine -= math.tau;
    }
}

pub fn init(thread_context: *ThreadContext, game_memory: *Memory) void {
    assert(@sizeOf(GameState) <= game_memory.permanent_len);

    assert(@sizeOf(GameState) <= game_memory.transient_len);
    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent));

    game_state.* = .{};

    const game_state_size = @sizeOf(GameState);
    const world_arena_size = game_memory.permanent_len - game_state_size;

    game_state.world_arena = .init(game_memory.permanent[game_state_size .. game_state_size + world_arena_size]);

    game_state.world = game_state.world_arena.pushMemory(World);
    const world: *World = game_state.world;

    world.init(1.4);

    const tile_size_in_pixels = 60;
    game_state.meters_to_pixels = tile_size_in_pixels / world.tile_side_in_meters;

    _ = addLowEntity(game_state, .null, .null);

    const asset_prefix = "../../hh_assets/";
    // const asset_prefix = "";

    const asset_load_begin = std.Io.Timestamp.now(thread_context.io, .real);

    game_state.backdrop = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_background.bmp");
    game_state.hero_shadow = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_shadow.bmp");
    game_state.tree = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/tree00.bmp");
    game_state.sword = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/rock03.bmp");

    game_state.hero_bitmaps[0].head = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_right_head.bmp");
    game_state.hero_bitmaps[0].cape = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_right_cape.bmp");
    game_state.hero_bitmaps[0].torso = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_right_torso.bmp");
    game_state.hero_bitmaps[0].alignment = v2(72, 182);

    game_state.hero_bitmaps[1].head = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_back_head.bmp");
    game_state.hero_bitmaps[1].cape = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_back_cape.bmp");
    game_state.hero_bitmaps[1].torso = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_back_torso.bmp");
    game_state.hero_bitmaps[1].alignment = v2(72, 182);

    game_state.hero_bitmaps[2].head = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_left_head.bmp");
    game_state.hero_bitmaps[2].cape = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_left_cape.bmp");
    game_state.hero_bitmaps[2].torso = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_left_torso.bmp");
    game_state.hero_bitmaps[2].alignment = v2(72, 182);

    game_state.hero_bitmaps[3].head = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_front_head.bmp");
    game_state.hero_bitmaps[3].cape = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_front_cape.bmp");
    game_state.hero_bitmaps[3].torso = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_front_torso.bmp");
    game_state.hero_bitmaps[3].alignment = v2(72, 182);

    const asset_load_duration = asset_load_begin.untilNow(thread_context.io, .real);
    log.info("Asset loading took: {f}", .{asset_load_duration});

    var next_random_number_index: usize = 0;

    const screen_base_x: i32 = 0;
    const screen_base_y: i32 = 0;
    const screen_base_z: i32 = 0;

    var screen_x: i32 = screen_base_x;
    var screen_y: i32 = screen_base_y;
    var abs_tile_z: i32 = screen_base_z;

    var door_left = false;
    var door_right = false;
    var door_top = false;
    var door_bottom = false;
    var door_up = false;
    var door_down = false;

    for (0..2000) |_| {
        const random_number = Random.random_number_table[next_random_number_index];
        next_random_number_index += 1;

        const random_choice =
            // if (door_up or door_down)
            random_number % 2
        // else
        //     random_number % 3
        ;

        var created_ladder = false;

        if (random_choice == 2) {
            if (abs_tile_z == screen_base_z) {
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

        for (0..GameState.screen_tile_height) |tile_y_| {
            const tile_y: i32 = @intCast(tile_y_);

            for (0..GameState.screen_tile_width) |tile_x_| {
                const tile_x: i32 = @intCast(tile_x_);

                const abs_tile_x: i32 = (screen_x * GameState.screen_tile_width) + tile_x;
                const abs_tile_y: i32 = (screen_y * GameState.screen_tile_height) + tile_y;

                var tile_value: u32 = 1;

                if ((tile_x == 0) and
                    (!door_left or (tile_y != (GameState.screen_tile_height / 2))))
                {
                    tile_value = 2;
                } else if ((tile_x == GameState.screen_tile_width - 1) and
                    (!door_right or (tile_y != (GameState.screen_tile_height / 2))))
                {
                    tile_value = 2;
                } else if ((tile_y == 0) and
                    (!door_bottom or (tile_x != (GameState.screen_tile_width / 2))))
                {
                    tile_value = 2;
                } else if ((tile_y == GameState.screen_tile_height - 1) and
                    (!door_top or (tile_x != (GameState.screen_tile_width / 2))))
                {
                    tile_value = 2;
                }

                if (tile_x == 10 and tile_y == 6) {
                    if (door_up) {
                        tile_value = 3;
                    } else if (door_down) {
                        tile_value = 4;
                    }
                }

                _ = world.getChunk(0, 0, 0, .{});

                if (tile_value == 2) {
                    _ = addWall(game_state, abs_tile_x, abs_tile_y, abs_tile_z);
                }
            }
        }

        if (random_choice == 2) {
            if (abs_tile_z == screen_base_z) {
                abs_tile_z = screen_base_z + 1;
            } else {
                abs_tile_z = screen_base_z;
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

    const cam_tile_x = (screen_base_x * GameState.screen_tile_width) + (GameState.screen_tile_width / 2);
    const cam_tile_y = (screen_base_y * GameState.screen_tile_height) + (GameState.screen_tile_height / 2);
    const cam_tile_z = screen_base_z;

    game_state.camera_pos = game_state.world.chunkPositionFromTilePosition(cam_tile_x, cam_tile_y, cam_tile_z);

    _ = addMonster(game_state, cam_tile_x + 2, cam_tile_y + 2, cam_tile_z);

    _ = addFamiliar(game_state, cam_tile_x - 2, cam_tile_y + 2, cam_tile_z);

    // _ = addWall(game_state, -1, -1, 0);

}

pub export fn updateAndRender(thread_context: *ThreadContext, game_memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer) callconv(.c) void {
    assert(@sizeOf(GameState) <= game_memory.transient_len);
    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent));

    if (!game_memory.initialized) {
        init(thread_context, game_memory);
        game_memory.initialized = true;
    }

    const world: *World = game_state.world;

    // TODO: Is controller.connected supposed to exist?
    for (input.controllers, 0..) |controller, controller_index| {
        const buttons = &controller.buttons.named;

        const con_hero = &game_state.controlled_heroes[controller_index];
        if (con_hero.index == 0) {
            if (buttons.start.ended_down) {
                con_hero.* = .{};
                con_hero.index = addPlayer(game_state).low_index;
                game_state.controlled_heroes[controller_index] = .{ .index = con_hero.index };
            }
        } else {
            con_hero.dz = 0;
            con_hero.ddp = .zero;
            con_hero.d_sword = .zero;

            if (controller.is_analog) {
                con_hero.ddp.x += controller.stick_average_x;
                con_hero.ddp.y += controller.stick_average_y;
            } else {
                if (buttons.move_up.ended_down) {
                    con_hero.ddp.y = 1;
                }
                if (buttons.move_down.ended_down) {
                    con_hero.ddp.y = -1;
                }
                if (buttons.move_left.ended_down) {
                    con_hero.ddp.x = -1;
                }
                if (buttons.move_right.ended_down) {
                    con_hero.ddp.x = 1;
                }
            }

            if (buttons.start.ended_down) {
                con_hero.dz = 3;
            }

            if (buttons.action_up.ended_down) {
                con_hero.d_sword = v2(0, 1);
            }
            if (buttons.action_down.ended_down) {
                con_hero.d_sword = v2(0, -1);
            }
            if (buttons.action_left.ended_down) {
                con_hero.d_sword = v2(-1, 0);
            }
            if (buttons.action_right.ended_down) {
                con_hero.d_sword = v2(1, 0);
            }
        }
    }

    const tile_span_x = GameState.screen_tile_width * 3;
    const tile_span_y = GameState.screen_tile_height * 3;
    const bound_dim = v2(tile_span_x, tile_span_y).mul(world.tile_side_in_meters);
    const camera_bounds: Rect = .centerDim(V2.zero, bound_dim);

    var sim_arena = MemoryArena.init(game_memory.transient[0..game_memory.transient_len]);
    const sim_region = SimRegion.begin(&sim_arena, game_state, game_state.camera_pos, camera_bounds);

    @memset(@as([]u32, @ptrCast(@alignCast(offscreen_buffer.memory[0..offscreen_buffer.memory_len]))), 0xff00ff);
    drawRectangle(offscreen_buffer, V2.zero, v2u(offscreen_buffer.width, offscreen_buffer.height), 0.5, 0.5, 0.5);
    // drawBitmap(offscreen_buffer, game_state.backdrop, 0, 0, .{});

    const screen_center = v2(
        @floatFromInt(@divTrunc(offscreen_buffer.width, 2)),
        @floatFromInt(@divTrunc(offscreen_buffer.height, 2)),
    );

    var piece_group: EntityVisiblePieceGroup = .{ .game_state = game_state };
    for (sim_region.entities) |*entity| {
        if (entity.updatable) {
            piece_group.count = 0;

            const shadow_alpha = @max(0, 1 - entity.z);

            var move_spec: MoveSpec = .{};
            var ddp: V2 = .zero;

            const hero_bitmap = &game_state.hero_bitmaps[@intFromEnum(entity.facing_direction)];

            switch (entity.type) {
                .null => unreachable,

                .hero => {
                    for (&game_state.controlled_heroes) |*con_hero| {
                        if (con_hero.index == entity.storage_index) {
                            if (con_hero.dz != 0) {
                                entity.dz = con_hero.dz;
                            }

                            move_spec = MoveSpec{ .speed = 50, .drag = 8 };
                            ddp = con_hero.ddp;

                            if (con_hero.d_sword.x != 0 or con_hero.d_sword.y != 0) {
                                if (entity.sword.ptr) |sword| if (sword.flags.non_spatial) {
                                    sword.distance_limit = 5;
                                    addCollisionRule(game_state, entity.storage_index, sword.storage_index, false);
                                    SimRegion.makeEntitySpatial(sword, entity.p, entity.dp.add(con_hero.d_sword.mul(5)));
                                };
                            }
                        }
                    }

                    pushBitmap(&piece_group, &game_state.hero_shadow, V2.zero, 0, hero_bitmap.alignment, .{ .alpha = shadow_alpha, .entity_z_c = 0 });
                    pushBitmap(&piece_group, &hero_bitmap.torso, V2.zero, 0, hero_bitmap.alignment, .{});
                    pushBitmap(&piece_group, &hero_bitmap.cape, V2.zero, 0, hero_bitmap.alignment, .{});
                    pushBitmap(&piece_group, &hero_bitmap.head, V2.zero, 0, hero_bitmap.alignment, .{});

                    drawHitpoints(entity, &piece_group);
                },

                .wall => {
                    pushBitmap(&piece_group, &game_state.tree, V2.zero, 0, v2(40, 80), .{});
                },

                .sword => {
                    move_spec = MoveSpec{ .unit_max_ddp = false, .speed = 0 };
                    ddp = V2.zero;

                    if (entity.distance_limit == 0) {
                        clearCollisionRulesFor(game_state, entity.storage_index);
                        SimRegion.makeEntityNonSpatial(entity);
                    }

                    pushBitmap(&piece_group, &game_state.hero_shadow, V2.zero, 0, hero_bitmap.alignment, .{ .alpha = shadow_alpha, .entity_z_c = 0 });
                    pushBitmap(&piece_group, &game_state.sword, V2.zero, 0, v2(29, 10), .{});
                },

                .familiar => {
                    var closest_hero_opt: ?*Entity = null;
                    var closest_hero_d_sq: f32 = math.square(10);

                    for (sim_region.entities) |*test_entity| {
                        if (test_entity.type == .hero and closest_hero_d_sq > 0) {
                            const test_d_sq = test_entity.p.sub(entity.p).lengthSquared();
                            if (closest_hero_d_sq > test_d_sq) {
                                closest_hero_opt = test_entity;
                                closest_hero_d_sq = test_d_sq;
                            }
                        }
                    }

                    ddp = V2.zero;
                    if (closest_hero_opt) |hero| {
                        if (closest_hero_d_sq >= math.square(3)) {
                            const acceleration = 0.5;
                            const one_over_length = acceleration / math.sqrt(closest_hero_d_sq);
                            ddp = hero.p.sub(entity.p).mul(one_over_length);
                        }
                    }

                    move_spec = MoveSpec{ .speed = 50, .drag = 8 };

                    entity.t_bob += input.dt;
                    if (entity.t_bob > math.tau) entity.t_bob -= math.tau;

                    const bob_sin = @sin(2 * entity.t_bob);

                    pushBitmap(&piece_group, &game_state.hero_shadow, V2.zero, 0, hero_bitmap.alignment, .{
                        .alpha = (0.5 * shadow_alpha) + (0.2 * bob_sin),
                        .entity_z_c = 0,
                    });
                    pushBitmap(&piece_group, &hero_bitmap.head, V2.zero, 0.25 * bob_sin, hero_bitmap.alignment, .{});
                },

                .monster => {
                    pushBitmap(&piece_group, &game_state.hero_shadow, V2.zero, 0, hero_bitmap.alignment, .{ .alpha = shadow_alpha, .entity_z_c = 0 });
                    pushBitmap(&piece_group, &hero_bitmap.torso, V2.zero, 0, hero_bitmap.alignment, .{});

                    drawHitpoints(entity, &piece_group);
                },
            }

            if (!entity.flags.non_spatial) {
                sim_region.moveEntity(game_state, entity, input.dt, move_spec, ddp);
            }

            const entity_ground_point = v2(
                screen_center.x + (game_state.meters_to_pixels * entity.p.x),
                screen_center.y - (game_state.meters_to_pixels * entity.p.y),
            );
            const entity_z = game_state.meters_to_pixels * -entity.z;

            for (piece_group.pieces[0..piece_group.count]) |*piece| {
                const center = v2(
                    entity_ground_point.x + piece.offset.x,
                    entity_ground_point.y + piece.offset.y + piece.offset_z + (piece.entity_z_c * entity_z),
                );

                if (piece.bitmap) |bitmap| {
                    drawBitmap(offscreen_buffer, bitmap, center.x, center.y, piece.a);
                } else {
                    const dim = piece.dim.mul(game_state.meters_to_pixels);
                    const half_dim = dim.mul(0.5);
                    drawRectangle(
                        offscreen_buffer,
                        center.sub(half_dim),
                        center.add(half_dim),
                        piece.r,
                        piece.g,
                        piece.b,
                    );
                }
            }
        }
    }

    sim_region.end(game_state);
}

const PushPieceOptions = struct {
    alpha: f32 = 1,
    entity_z_c: f32 = 1,
};

fn pushPiece(
    group: *EntityVisiblePieceGroup,
    bitmap: ?*const LoadedBitmap,
    offset: V2,
    offset_z: f32,
    dim: V2,
    @"align": V2,
    entity_z_c: f32,
    color: V4,
) void {
    assert(group.count < group.pieces.len);

    const c = color.color();

    group.pieces[group.count] = .{
        .bitmap = bitmap,
        .offset = v2(offset.x, -offset.y).mul(group.game_state.meters_to_pixels).sub(@"align"),
        .offset_z = offset_z * group.game_state.meters_to_pixels,
        .entity_z_c = entity_z_c,
        .r = c.r,
        .g = c.g,
        .b = c.b,
        .a = c.a,
        .dim = dim,
    };
    group.count += 1;
}

inline fn pushBitmap(group: *EntityVisiblePieceGroup, bitmap: *const LoadedBitmap, offset: V2, offset_z: f32, @"align": V2, o: PushPieceOptions) void {
    pushPiece(group, bitmap, offset, offset_z, V2.zero, @"align", o.entity_z_c, v4(1, 1, 1, o.alpha));
}

const PushRectOptions = struct {
    entity_z_c: f32 = 1,
};

inline fn pushRect(group: *EntityVisiblePieceGroup, offset: V2, offset_z: f32, dim: V2, color: V4, o: PushRectOptions) void {
    pushPiece(
        group,
        null,
        offset,
        offset_z,
        dim,
        V2.zero,
        o.entity_z_c,
        color,
    );
}

pub export fn getAudioFrames(thread_context: *ThreadContext, game_memory: *Memory, sound_buffer: *AudioBuffer) callconv(.c) void {
    _ = thread_context;
    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent));
    outputSound(game_state, sound_buffer);
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

    pub fn loadBMP(pd: *const common.DEBUG, thread_context: *ThreadContext, filename: [:0]const u8) LoadedBitmap {
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

            const red_mask = header.red_mask;
            const green_mask = header.green_mask;
            const blue_mask = header.blue_mask;
            const alpha_mask = header.alpha_mask;

            assert(alpha_mask == ~(red_mask | green_mask | blue_mask));
            assert(@popCount(red_mask) == 8);
            assert(@popCount(green_mask) == 8);
            assert(@popCount(blue_mask) == 8);
            assert(@popCount(alpha_mask) == 8);

            const red_scan = intrinsics.findLSBSet(red_mask);
            const green_scan = intrinsics.findLSBSet(green_mask);
            const blue_scan = intrinsics.findLSBSet(blue_mask);
            const alpha_scan = intrinsics.findLSBSet(alpha_mask);

            assert(red_scan.found);
            assert(green_scan.found);
            assert(blue_scan.found);
            assert(alpha_scan.found);

            if (red_scan.index != 16 or green_scan.index != 8 or
                blue_scan.index != 0 or alpha_scan.index != 24)
            {
                const red_shift = 16 - @as(i32, @intCast(red_scan.index));
                const green_shift = 8 - @as(i32, @intCast(green_scan.index));
                const blue_shift = 0 - @as(i32, @intCast(blue_scan.index));
                const alpha_shift = 24 - @as(i32, @intCast(alpha_scan.index));

                for (result.pixels) |*pixel| {
                    const c = pixel.*;

                    pixel.* =
                        intrinsics.rotateLeft(c & red_mask, @intCast(red_shift)) |
                        intrinsics.rotateLeft(c & green_mask, @intCast(green_shift)) |
                        intrinsics.rotateLeft(c & blue_mask, @intCast(blue_shift)) |
                        intrinsics.rotateLeft(c & alpha_mask, @intCast(alpha_shift));
                }
            }
        }

        log.debug("Loaded bmp: {s} ({},{})", .{ filename, result.width, result.height });

        return result;
    }
};
