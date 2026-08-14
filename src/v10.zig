const std = @import("std");
const log = std.log.scoped(.v10);

const core = @import("core");
const assert = core.assert;
const intrinsics = core.intrinsics;
const mem = core.mem;

const math = core.math;
const Color = math.Color;
const V2 = math.V2;
const v2 = V2.init;
const V3 = math.V3;
const v3 = V3.init;
const V4 = math.V4;
const v4 = V4.init;
const Rect3 = math.Rect3;

const SimRegion = @import("sim_region.zig");
const MoveSpec = SimRegion.MoveSpec;

const Entity = @import("entity.zig");
const EntityIndex = Entity.Index;
const EntityType = Entity.Type;
const EntityReference = Entity.Reference;
const HitPoint = Entity.HitPoint;

const Random = @import("random.zig");
const MemoryArena = @import("arena.zig");
const TemporaryMemory = MemoryArena.TemporaryMemory;
const World = @import("world.zig");

const common = @import("v10_common");
const ThreadContext = common.ThreadContext;
const Memory = common.Memory;
const Input = common.Input;
const OffscreenBuffer = common.OffscreenBuffer;
const AudioBuffer = common.AudioBuffer;

const RenderGroup = @import("render_group.zig");

const os = @import("builtin").os.tag;

pub const std_options = core.default_std_options;

pub const LowEntity = struct {
    sim: Entity = .{},
    p: World.Position = .null,
};

pub const ControlledHero = struct {
    index: EntityIndex = 0,
    ddp: V2 = .zero,
    dz: f32 = 0,
    d_sword: V2 = .zero,
};

pub const PairwiseCollisionRule = struct {
    can_collide: bool,
    storage_index_a: EntityIndex,
    storage_index_b: EntityIndex,

    next_in_hash: ?*PairwiseCollisionRule = null,
};

pub const GroundBuffer = struct {
    p: World.Position = .zero,
    bitmap: LoadedBitmap,
};

pub const GameState = struct {
    const screen_tile_width = 17;
    const screen_tile_height = 9;
    const controller_count = @typeInfo(@FieldType(Input, "controllers")).array.len;

    world_arena: MemoryArena = undefined,
    world: *World = undefined,

    typical_floor_height: f32 = 0,

    meters_to_pixels: f32 = 0,
    pixels_to_meters: f32 = 0,

    camera_following_entity_index: EntityIndex = 0,
    camera_pos: World.Position = .zero,

    controlled_heroes: [controller_count]ControlledHero = @splat(std.mem.zeroes(ControlledHero)),

    low_entity_count: u32 = 0,
    low_entities: [100_000]LowEntity = @splat(.{}),

    grass: [2]LoadedBitmap = @splat(.{}),
    stone: [4]LoadedBitmap = @splat(.{}),
    tuft: [3]LoadedBitmap = @splat(.{}),

    backdrop: LoadedBitmap = .{},
    hero_shadow: LoadedBitmap = .{},
    hero_bitmaps: [4]HeroBitmaps = @splat(.{}),

    tree: LoadedBitmap = .{},
    sword: LoadedBitmap = .{},
    stairwell: LoadedBitmap = .{},

    // Must be power of 2
    collision_rule_hash: [16]?*PairwiseCollisionRule = @splat(null),
    first_free_collision_rule: ?*PairwiseCollisionRule = null,

    null_collision: *Entity.CollisionGroup = undefined,
    sword_collision: *Entity.CollisionGroup = undefined,
    stair_collision: *Entity.CollisionGroup = undefined,
    player_collision: *Entity.CollisionGroup = undefined,
    monster_collision: *Entity.CollisionGroup = undefined,
    familiar_collision: *Entity.CollisionGroup = undefined,
    wall_collision: *Entity.CollisionGroup = undefined,
    standard_room_collision: *Entity.CollisionGroup = undefined,

    time: f32 = 0,
};

pub const TransientState = struct {
    initialized: bool = false,

    arena: MemoryArena = undefined,

    ground_buffers: []GroundBuffer = &.{},
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
    low_entity.sim.collision = game_state.null_collision;
    low_entity.p = .null;

    game_state.world.changeEntityLocation(&game_state.world_arena, low_index, low_entity, p);

    const result = AddLowEntityResult{
        .low = low_entity,
        .low_index = low_index,
    };

    return result;
}

pub fn addGroundedLowEntity(game_state: *GameState, entity_type: EntityType, p: World.Position, collision: *Entity.CollisionGroup) AddLowEntityResult {
    const entity = addLowEntity(game_state, entity_type, p);
    entity.low.sim.collision = collision;

    return entity;
}

pub fn addStandardRoom(
    game_state: *GameState,
    center_tile_x: f32,
    center_tile_y: f32,
    min_tile_z: f32,
) AddLowEntityResult {
    const p = chunkPositionFromTilePosition(
        game_state.world,
        @intFromFloat(center_tile_x),
        @intFromFloat(center_tile_y),
        @intFromFloat(min_tile_z),
    );
    const entity = addGroundedLowEntity(game_state, .space, p, game_state.standard_room_collision);

    entity.low.sim.flags = .{
        .traversable = true,
    };

    return entity;
}

pub fn addPlayer(game_state: *GameState) AddLowEntityResult {
    const entity = addGroundedLowEntity(game_state, .hero, game_state.camera_pos, game_state.player_collision);

    entity.low.sim.flags = .{
        .collides = true,
        .moveable = true,
    };

    initHitpoints(&entity.low.sim, 3);

    const sword = addSword(game_state);
    entity.low.sim.sword = EntityReference{ .index = sword.low_index };

    if (game_state.camera_following_entity_index == 0) {
        game_state.camera_following_entity_index = entity.low_index;
    }

    return entity;
}

pub fn addWall(game_state: *GameState, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const p = chunkPositionFromTilePosition(game_state.world, abs_tile_x, abs_tile_y, abs_tile_z);
    const entity = addGroundedLowEntity(game_state, .wall, p, game_state.wall_collision);

    entity.low.sim.flags.collides = true;

    return entity;
}

pub fn addMonster(game_state: *GameState, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const p = chunkPositionFromTilePosition(game_state.world, abs_tile_x, abs_tile_y, abs_tile_z);
    const entity = addGroundedLowEntity(game_state, .monster, p, game_state.monster_collision);

    initHitpoints(&entity.low.sim, 3);
    entity.low.sim.flags = .{
        .collides = true,
        .moveable = true,
    };

    return entity;
}

pub fn addFamiliar(game_state: *GameState, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const p = chunkPositionFromTilePosition(game_state.world, abs_tile_x, abs_tile_y, abs_tile_z);
    const entity = addGroundedLowEntity(game_state, .familiar, p, game_state.familiar_collision);

    entity.low.sim.flags = .{
        .collides = true,
        .moveable = true,
    };

    return entity;
}

pub fn addSword(game_state: *GameState) AddLowEntityResult {
    const entity = addLowEntity(game_state, .sword, .null);

    entity.low.sim.collision = game_state.sword_collision;
    entity.low.sim.flags = .{
        .collides = true,
        .moveable = true,
        .non_spatial = true,
    };

    return entity;
}

pub fn addStair(game_state: *GameState, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
    const p = chunkPositionFromTilePosition(game_state.world, abs_tile_x, abs_tile_y, abs_tile_z);

    const entity = addGroundedLowEntity(game_state, .stairwell, p, game_state.stair_collision);

    entity.low.sim.walkable_dim = entity.low.sim.collision.total_volume.dim.xy();
    entity.low.sim.walkable_height = game_state.typical_floor_height;

    entity.low.sim.flags = .{
        .collides = true,
    };

    return entity;
}

fn initHitpoints(entity: *Entity, count: u32) void {
    assert(count <= entity.hitpoints.len);
    entity.hitpoint_max = count;
    @memset(
        entity.hitpoints[0..entity.hitpoint_max],
        .{ .amount = HitPoint.max_amount },
    );
}

fn drawHitpoints(entity: *Entity, render_group: *RenderGroup) void {
    if (entity.hitpoint_max >= 1) {
        const health_dim = v2(0.2, 0.2);
        const spacing_x = health_dim.x * 1.5;

        var hit_p = v2(
            -0.5 * @as(f32, @floatFromInt(entity.hitpoint_max - 1)) * spacing_x,
            -0.25,
        );

        for (entity.hitpoints[0..entity.hitpoint_max]) |*hit_point| {
            var color: Color = .rgba(1, 0, 0, 0.5);
            if (hit_point.amount == 0) {
                color = .rgba(0.2, 0.2, 0.2, 1);
            }

            render_group.pushRect(hit_p, 0, health_dim, color, .{ .entity_z_c = 0 });

            hit_p.x += spacing_x;
        }
    }
}

pub inline fn addCollisionRule(game_state: *GameState, storage_index_a: EntityIndex, storage_index_b: EntityIndex, should_collide: bool) void {
    addCollisionRuleRaw(game_state, storage_index_a, storage_index_b, should_collide);
}

pub fn addCollisionRuleRaw(game_state: *GameState, storage_index_a_: EntityIndex, storage_index_b_: EntityIndex, should_collide: bool) void {
    const default_order = .{ storage_index_a_, storage_index_b_ };

    const storage_index_a, const storage_index_b = if (storage_index_a_ > storage_index_b_)
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
            found_opt = game_state.world_arena.push(PairwiseCollisionRule);
        }

        found_opt.?.next_in_hash = game_state.collision_rule_hash[hash_bucket];
        game_state.collision_rule_hash[hash_bucket] = found_opt;
    }

    if (found_opt) |found| {
        found.can_collide = should_collide;
        found.storage_index_a = storage_index_a;
        found.storage_index_b = storage_index_b;
    }
}

pub fn clearCollisionRulesFor(game_state: *GameState, storage_index: EntityIndex) void {
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

pub const LoadedBitmap = struct {
    width: i32 = 0,
    height: i32 = 0,
    pitch: i32 = 0,
    memory: [*]u8 = undefined,

    pub const bytes_per_pixel = 4;
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

    assert(buffer.frames.len >= 0);

    for (buffer.frames) |*frame| {
        // const sine_value: f32 = intrinsics.sin(game_state.t_sine);
        // const sample_value: i16 = @intFromFloat(@as(f32, @floatFromInt(tone_volume)) * sine_value);
        // sample_value = 0;
        const sample_value: i16 = 0;

        frame.* = .{ .left = sample_value, .right = sample_value };

        // game_state.t_sine += math.tau / wave_period;
        // if (game_state.t_sine > math.tau) game_state.t_sine -= math.tau;
    }
}

pub fn chunkPositionFromTilePosition(world: *const World, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) World.Position {
    const tile_side_in_meters: f32 = 1.4;
    const tile_depth_in_meters: f32 = 3;

    const tile_dim = v3(tile_side_in_meters, tile_side_in_meters, tile_depth_in_meters);
    const offset = V3.i(abs_tile_x, abs_tile_y, abs_tile_z).hadamard(tile_dim);
    const result = World.Position.zero.offset(world, offset);

    assert(World.isCanonicalOffset(world, result._offset));

    return result;
}

pub export fn updateAndRender(thread_context: *ThreadContext, game_memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer) callconv(.c) void {
    assert(@sizeOf(GameState) <= game_memory.permanent.len);
    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent));

    const ground_buffer_width = 256;
    const ground_buffer_height = 256;

    if (!game_memory.initialized) {
        game_state.* = .{};

        const game_state_size = @sizeOf(GameState);
        const world_arena_size = game_memory.permanent.len - game_state_size;

        game_state.world_arena = .init(game_memory.permanent[game_state_size..][0..world_arena_size]);

        game_state.world = game_state.world_arena.push(World);
        const world: *World = game_state.world;

        game_state.typical_floor_height = 3;
        game_state.meters_to_pixels = 42;
        game_state.pixels_to_meters = 1 / game_state.meters_to_pixels;

        const world_chunk_dim_in_meters = v3(
            game_state.pixels_to_meters * ground_buffer_width,
            game_state.pixels_to_meters * ground_buffer_height,
            game_state.typical_floor_height,
        );

        world.init(world_chunk_dim_in_meters);

        _ = addLowEntity(game_state, .null, .null);

        const tile_side_in_meters = 1.4;

        game_state.null_collision = .null(game_state);
        game_state.sword_collision = .simpleGrounded(game_state, 1, 0.5, 0.1);
        game_state.stair_collision = .simpleGrounded(
            game_state,
            tile_side_in_meters,
            2 * tile_side_in_meters,
            1.1 * game_state.typical_floor_height,
        );
        game_state.player_collision = .simpleGrounded(game_state, 1, 0.5, 1.2);
        game_state.monster_collision = .simpleGrounded(game_state, 1, 0.5, 0.5);
        game_state.familiar_collision = .simpleGrounded(game_state, 1, 0.5, 0.5);
        game_state.wall_collision = .simpleGrounded(
            game_state,
            tile_side_in_meters,
            tile_side_in_meters,
            game_state.typical_floor_height,
        );
        game_state.standard_room_collision = .simpleGrounded(
            game_state,
            GameState.screen_tile_width * tile_side_in_meters,
            GameState.screen_tile_height * tile_side_in_meters,
            0.9 * game_state.typical_floor_height,
        );

        const asset_prefix = "../../hh_assets/";
        // const asset_prefix = "";

        const asset_load_begin_ts = std.Io.Timestamp.now(thread_context.io, .real);

        game_state.grass[0] = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/grass00.bmp");
        game_state.grass[1] = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/grass01.bmp");

        game_state.stone[0] = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/ground00.bmp");
        game_state.stone[1] = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/ground01.bmp");
        game_state.stone[2] = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/ground02.bmp");
        game_state.stone[3] = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/ground03.bmp");

        game_state.tuft[0] = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/tuft00.bmp");
        game_state.tuft[1] = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/tuft01.bmp");
        game_state.tuft[2] = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/tuft02.bmp");

        game_state.backdrop = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_background.bmp");
        game_state.hero_shadow = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_shadow.bmp");
        game_state.tree = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/tree00.bmp");
        game_state.sword = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/rock03.bmp");
        game_state.stairwell = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/rock02.bmp");

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

        const asset_load_duration = asset_load_begin_ts.untilNow(thread_context.io, .real);
        log.info("Asset loading took: {f}", .{asset_load_duration});

        const world_build_begin_ts = std.Io.Timestamp.now(thread_context.io, .real);

        var series = Random.Series.seed(1234);

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
            // const door_direction = series.randomChoice(if (door_up or door_down) 2 else 3);
            const door_direction = series.randomChoice(2);

            var created_ladder = false;

            if (door_direction == 2) {
                created_ladder = true;
                if (abs_tile_z == screen_base_z) {
                    door_up = true;
                } else {
                    door_down = true;
                }
            } else if (door_direction == 1) {
                door_right = true;
            } else {
                door_top = true;
            }

            _ = addStandardRoom(
                game_state,
                @as(f32, @floatFromInt(screen_x * GameState.screen_tile_width)) + (@as(f32, GameState.screen_tile_width) / 2),
                @as(f32, @floatFromInt(screen_y * GameState.screen_tile_height)) + (@as(f32, GameState.screen_tile_height) / 2),
                @floatFromInt(abs_tile_z),
            );

            for (0..GameState.screen_tile_height) |tile_y_| {
                const tile_y: i32 = @intCast(tile_y_);

                for (0..GameState.screen_tile_width) |tile_x_| {
                    const tile_x: i32 = @intCast(tile_x_);

                    const abs_tile_x: i32 = (screen_x * GameState.screen_tile_width) + tile_x;
                    const abs_tile_y: i32 = (screen_y * GameState.screen_tile_height) + tile_y;

                    var should_be_wall = false;

                    if ((tile_x == 0) and
                        (!door_left or (tile_y != (GameState.screen_tile_height / 2))))
                    {
                        should_be_wall = true;
                    } else if ((tile_x == GameState.screen_tile_width - 1) and
                        (!door_right or (tile_y != (GameState.screen_tile_height / 2))))
                    {
                        should_be_wall = true;
                    } else if ((tile_y == 0) and
                        (!door_bottom or (tile_x != (GameState.screen_tile_width / 2))))
                    {
                        should_be_wall = true;
                    } else if ((tile_y == GameState.screen_tile_height - 1) and
                        (!door_top or (tile_x != (GameState.screen_tile_width / 2))))
                    {
                        should_be_wall = true;
                    }

                    if (should_be_wall) {
                        _ = addWall(game_state, abs_tile_x, abs_tile_y, abs_tile_z);
                    } else if (created_ladder) {
                        if (tile_x == 10 and tile_y == 5) {
                            _ = addStair(game_state, abs_tile_x, abs_tile_y, if (door_down) abs_tile_z - 1 else abs_tile_z);
                        }
                    }
                }
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

            if (door_direction == 2) {
                if (abs_tile_z == screen_base_z) {
                    abs_tile_z = screen_base_z + 1;
                } else {
                    abs_tile_z = screen_base_z;
                }
            } else if (door_direction == 1) {
                screen_x += 1;
            } else {
                screen_y += 1;
            }
        }

        const cam_tile_x = (screen_base_x * GameState.screen_tile_width) + (GameState.screen_tile_width / 2);
        const cam_tile_y = (screen_base_y * GameState.screen_tile_height) + (GameState.screen_tile_height / 2);
        const cam_tile_z = screen_base_z;

        game_state.camera_pos = chunkPositionFromTilePosition(game_state.world, cam_tile_x, cam_tile_y, cam_tile_z);

        _ = addMonster(game_state, cam_tile_x - 3, cam_tile_y + 2, cam_tile_z);

        for (0..1) |_| {
            const fox = series.randomBetweenInt(-7, 7);
            const foy = series.randomBetweenInt(-3, -1);
            log.debug("fox,foy: {},{}", .{ fox, foy });
            _ = addFamiliar(game_state, cam_tile_x + fox, cam_tile_y + foy, cam_tile_z);
        }

        const world_build_duration = world_build_begin_ts.untilNow(thread_context.io, .real);
        log.info("World building took: {f}", .{world_build_duration});

        game_memory.initialized = true;
    }

    assert(@sizeOf(TransientState) <= game_memory.transient.len);
    const tran_state: *TransientState = @ptrCast(@alignCast(game_memory.transient));
    const transient_state_size = @sizeOf(TransientState);
    const transient_arena_size = game_memory.transient.len - transient_state_size;
    if (!tran_state.initialized) {
        tran_state.arena = .init(game_memory.transient[transient_state_size..][0..transient_arena_size]);

        tran_state.ground_buffers = tran_state.arena.pushArray(64, GroundBuffer);

        for (tran_state.ground_buffers) |*ground_buffer| {
            ground_buffer.* = .{
                .p = .null,
                .bitmap = makeEmptyBitmap(&tran_state.arena, ground_buffer_width, ground_buffer_height),
            };
        }

        tran_state.initialized = true;
    }

    // if (input.executable_reloaded) {
    //     for (tran_state.ground_buffers) |*ground_buffer| {
    //         ground_buffer.p = .null;
    //     }
    // }

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
            con_hero.ddp = .zero;
            con_hero.dz = 0;
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

    const render_memory = TemporaryMemory.begin(&tran_state.arena);
    const render_group = RenderGroup.init(render_memory.arena, 4 * mem.MiB, game_state.meters_to_pixels);

    assert(offscreen_buffer.pitch >= offscreen_buffer.width);
    const offscreen_buffer_data = offscreen_buffer.memory[0 .. @as(usize, @intCast(offscreen_buffer.pitch * offscreen_buffer.height)) * OffscreenBuffer.bytes_per_pixel];

    var draw_buffer_: LoadedBitmap = .{
        .width = offscreen_buffer.width,
        .height = offscreen_buffer.height,
        .pitch = offscreen_buffer.pitch,
        .memory = @ptrCast(offscreen_buffer_data.ptr),
    };
    const draw_buffer = &draw_buffer_;

    render_group.clear(.rgba(1, 0, 1, 1));

    const screen_center = v2(
        @floatFromInt(@divTrunc(offscreen_buffer.width, 2)),
        @floatFromInt(@divTrunc(offscreen_buffer.height, 2)),
    );

    const screen_width_meters = @as(f32, @floatFromInt(draw_buffer.width)) * game_state.pixels_to_meters;
    const screen_height_meters = @as(f32, @floatFromInt(draw_buffer.height)) * game_state.pixels_to_meters;

    const camera_bounds_meters = Rect3.centerDim(.zero, v3(screen_width_meters, screen_height_meters, 0));

    for (tran_state.ground_buffers) |*ground_buffer| {
        if (ground_buffer.p.isValid()) {
            const bitmap = &ground_buffer.bitmap;
            const delta = world.subtract(ground_buffer.p, game_state.camera_pos);

            render_group.pushBitmap(bitmap, delta.xy(), delta.z, V2.i(bitmap.width, bitmap.height).mul(0.5), .{});
        }
    }

    {
        const min_chunk_p = game_state.camera_pos.offset(world, camera_bounds_meters.min);
        const max_chunk_p = game_state.camera_pos.offset(world, camera_bounds_meters.max);

        const screen_dim = world.chunk_dim_in_meters.xy();

        var chunk_z: i32 = min_chunk_p.chunk_z;
        while (chunk_z <= max_chunk_p.chunk_z) : (chunk_z += 1) {
            //
            var chunk_y: i32 = min_chunk_p.chunk_y;
            while (chunk_y <= max_chunk_p.chunk_y) : (chunk_y += 1) {
                //
                var chunk_x: i32 = min_chunk_p.chunk_x;
                while (chunk_x <= max_chunk_p.chunk_x) : (chunk_x += 1) {
                    //
                    const chunk_center_p = World.getCenteredChunkPoint(chunk_x, chunk_y, chunk_z);
                    const rel_p = world.subtract(chunk_center_p, game_state.camera_pos);

                    var furthest_buffer_length_sq: f32 = 0;
                    var furthest_buffer_opt: ?*GroundBuffer = null;

                    for (tran_state.ground_buffers) |*ground_buffer| {
                        if (world.areInSameChunk(ground_buffer.p, chunk_center_p)) {
                            furthest_buffer_opt = null;
                            break;
                        } else if (ground_buffer.p.isValid()) {
                            const gb_rel_p = world.subtract(ground_buffer.p, game_state.camera_pos);
                            const buffer_length_sq = gb_rel_p.xy().lengthSquared();

                            if (furthest_buffer_length_sq < buffer_length_sq) {
                                furthest_buffer_length_sq = buffer_length_sq;
                                furthest_buffer_opt = ground_buffer;
                            }
                        } else {
                            furthest_buffer_length_sq = math.maxFloat(f32);
                            furthest_buffer_opt = ground_buffer;
                            break;
                        }
                    }

                    if (furthest_buffer_opt) |empty_buffer| {
                        fillGroundChunk(game_state, tran_state, empty_buffer, chunk_center_p);
                    }

                    render_group.pushRectOutline(rel_p.xy(), 0, screen_dim, .rgb(1, 1, 0), .{});
                    _ = .{ rel_p, screen_dim };
                }
            }
        }
    }

    const sim_bounds_extension: V3 = .scalar(15);
    const sim_bounds = camera_bounds_meters.addRadius(sim_bounds_extension);

    const sim_memory = TemporaryMemory.begin(&tran_state.arena);
    const sim_region = SimRegion.begin(sim_memory.arena, game_state, game_state.camera_pos, sim_bounds, input.dt);

    for (sim_region.entities) |*entity| {
        if (entity.updatable) {
            const shadow_alpha = @max(0, 1 - (0.5 * entity.p.z));

            var move_spec: MoveSpec = .{};
            var ddp: V3 = .zero;

            const basis = render_memory.arena.push(RenderGroup.Basis);
            basis.* = .{ .p = .zero };
            render_group.default_basis = basis;

            const hero_bitmap = &game_state.hero_bitmaps[@intFromEnum(entity.facing_direction)];

            switch (entity.type) {
                .null => unreachable,

                .hero => {
                    // pushRect(&piece_group, .zero, 0, entity.dim.xy(), v4(1, 0, 0, 1), .{});

                    for (&game_state.controlled_heroes) |*con_hero| {
                        if (con_hero.index == entity.storage_index) {
                            if (con_hero.dz != 0) {
                                entity.dp.z = con_hero.dz;
                            }

                            move_spec = MoveSpec{ .speed = 50, .drag = 8 };
                            ddp = V3.v2z(con_hero.ddp, 0);

                            if (con_hero.d_sword.x != 0 or con_hero.d_sword.y != 0) {
                                if (entity.sword.ptr) |sword| if (sword.flags.non_spatial) {
                                    sword.distance_limit = 5;
                                    addCollisionRule(game_state, entity.storage_index, sword.storage_index, false);
                                    SimRegion.makeEntitySpatial(sword, entity.p, entity.dp.add(.v2z(con_hero.d_sword.mul(5), 0)));
                                };
                            }
                        }
                    }

                    render_group.pushBitmap(&game_state.hero_shadow, V2.zero, 0, hero_bitmap.alignment, .{ .alpha = shadow_alpha, .entity_z_c = 0 });
                    render_group.pushBitmap(&hero_bitmap.torso, V2.zero, 0, hero_bitmap.alignment, .{});
                    render_group.pushBitmap(&hero_bitmap.cape, V2.zero, 0, hero_bitmap.alignment, .{});
                    render_group.pushBitmap(&hero_bitmap.head, V2.zero, 0, hero_bitmap.alignment, .{});

                    drawHitpoints(entity, render_group);
                },

                .wall => {
                    render_group.pushBitmap(&game_state.tree, V2.zero, 0, v2(40, 80), .{});
                },

                .sword => {
                    move_spec = MoveSpec{ .unit_max_ddp = false, .speed = 0 };
                    ddp = V3.zero;

                    if (entity.distance_limit == 0) {
                        clearCollisionRulesFor(game_state, entity.storage_index);
                        SimRegion.makeEntityNonSpatial(entity);
                    }

                    render_group.pushBitmap(&game_state.hero_shadow, V2.zero, 0, hero_bitmap.alignment, .{ .alpha = shadow_alpha, .entity_z_c = 0 });
                    render_group.pushBitmap(&game_state.sword, V2.zero, 0, v2(29, 10), .{});
                },

                .stairwell => {
                    render_group.pushRect(.zero, 0, entity.walkable_dim, .rgba(1, 0.5, 0, 1), .{ .entity_z_c = 0 });
                    render_group.pushRect(.zero, entity.walkable_height, entity.walkable_dim, .rgba(1, 1, 0, 1), .{ .entity_z_c = 0 });
                },

                .familiar => {
                    var closest_hero_opt: ?*Entity = null;
                    var closest_hero_d_sq: f32 = math.square(10);

                    if (false) {
                        for (sim_region.entities) |*test_entity| {
                            if (test_entity.type == .hero and closest_hero_d_sq > 0) {
                                const test_d_sq = test_entity.p.sub(entity.p).lengthSquared();
                                if (closest_hero_d_sq > test_d_sq) {
                                    closest_hero_opt = test_entity;
                                    closest_hero_d_sq = test_d_sq;
                                }
                            }
                        }
                    }

                    ddp = V3.zero;
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

                    render_group.pushBitmap(&game_state.hero_shadow, V2.zero, 0, hero_bitmap.alignment, .{
                        .alpha = (0.5 * shadow_alpha) + (0.2 * bob_sin),
                        .entity_z_c = 0,
                    });
                    render_group.pushBitmap(&hero_bitmap.head, V2.zero, 0.25 * bob_sin, hero_bitmap.alignment, .{});
                },

                .monster => {
                    render_group.pushBitmap(&game_state.hero_shadow, V2.zero, 0, hero_bitmap.alignment, .{ .alpha = shadow_alpha, .entity_z_c = 0 });
                    render_group.pushBitmap(&hero_bitmap.torso, V2.zero, 0, hero_bitmap.alignment, .{});

                    drawHitpoints(entity, render_group);
                },

                .space => {
                    for (entity.collision.volumes) |*volume| {
                        render_group.pushRectOutline(volume.offset.xy(), 0, volume.dim.xy(), .rgb(0, 0.5, 1), .{});
                    }
                },
            }

            if (!entity.flags.non_spatial and
                entity.flags.moveable)
            {
                sim_region.moveEntity(game_state, entity, input.dt, move_spec, ddp);
            }

            basis.p = entity.getGroundPoint();
        }
    }

    game_state.time += input.dt;
    const angle: f32 = 0.1 * game_state.time;
    // const disp = 100 * @cos(5 * angle);

    const origin = screen_center;
    const x_axis = v2(@cos(angle), @sin(angle)).mul(100);
    const y_axis = x_axis.perp();

    _ = render_group.coordinateSystem(
        origin.sub(x_axis.add(y_axis).mul(0.5)),
        x_axis,
        y_axis,
        .rgb(0.5 + 0.5 * @sin(angle), 0.5 + 0.5 * @sin(2.9 * angle), 0.5 + 0.5 * @cos(9.9 * angle)),
        &game_state.tree,
    );

    render_group.toOutput(draw_buffer);

    sim_region.end(game_state);

    sim_memory.end();
    render_memory.end();

    game_state.world_arena.check();
    tran_state.arena.check();
}

fn fillGroundChunk(game_state: *GameState, tran_state: *TransientState, ground_buffer: *GroundBuffer, chunk_p: World.Position) void {
    const ground_memory = tran_state.arena.beginTemporaryMemory();

    const render_group = RenderGroup.init(ground_memory.arena, mem.MiB, 1);
    render_group.clear(.rgb(0.5, 0.5, 0));

    const bitmap = &ground_buffer.bitmap;

    ground_buffer.p = chunk_p;

    const width: f32 = @floatFromInt(bitmap.width);
    const height: f32 = @floatFromInt(bitmap.height);

    for (0..3) |y| {
        const chunk_offset_y = -1 + @as(i32, @intCast(y));

        for (0..3) |x| {
            const chunk_offset_x = -1 + @as(i32, @intCast(x));

            const chunk_x = chunk_p.chunk_x + chunk_offset_x;
            const chunk_y = chunk_p.chunk_y + chunk_offset_y;
            const chunk_z = chunk_p.chunk_z;

            var series = Random.Series.seed(@bitCast(139 *% chunk_x +% 593 *% chunk_y +% 329 *% chunk_z));

            const center = v2(width, -height).hadamard(.i(chunk_offset_x, chunk_offset_y));

            for (0..100) |_| {
                var stamp: *const LoadedBitmap = undefined;
                if (series.randomBool()) {
                    stamp = &game_state.grass[series.randomChoice(game_state.grass.len)];
                } else {
                    stamp = &game_state.stone[series.randomChoice(game_state.stone.len)];
                }

                const bitmap_center = V2.i(stamp.width, stamp.height).mul(0.5);

                const offset: V2 = v2(
                    width * series.randomUnilateral(),
                    height * series.randomUnilateral(),
                );

                const p = center.add(offset).sub(bitmap_center);

                // render_group.pushBitmap(stamp, v2(p.x - width / 2, -p.y + height / 2), 0, .zero, .{});
                render_group.pushBitmap(stamp, p, 0, .zero, .{});
            }
        }
    }

    for (0..3) |y| {
        const chunk_offset_y = -1 + @as(i32, @intCast(y));

        for (0..3) |x| {
            const chunk_offset_x = -1 + @as(i32, @intCast(x));

            const chunk_x = chunk_p.chunk_x + chunk_offset_x;
            const chunk_y = chunk_p.chunk_y + chunk_offset_y;
            const chunk_z = chunk_p.chunk_z;

            var series = Random.Series.seed(@bitCast(139 *% chunk_x +% 593 *% chunk_y +% 329 *% chunk_z));

            const center = v2(width, -height).hadamard(.i(chunk_offset_x, chunk_offset_y));

            for (0..50) |_| {
                const stamp = &game_state.tuft[series.randomChoice(game_state.tuft.len)];

                const bitmap_center = V2.i(stamp.width, stamp.height).mul(0.5);

                const offset: V2 = v2(
                    width * series.randomUnilateral(),
                    height * series.randomUnilateral(),
                );

                const p = center.add(offset).sub(bitmap_center);

                // render_group.pushBitmap(stamp, v2(p.x - width / 2, -p.y + height / 2), 0, .zero, .{});
                render_group.pushBitmap(stamp, p, 0, .zero, .{});
            }
        }
    }

    render_group.toOutput(bitmap);
    ground_memory.end();
}

pub fn makeEmptyBitmap(arena: *MemoryArena, width: i32, height: i32) LoadedBitmap {
    const byte_size: usize = @as(usize, @intCast(width * height)) * LoadedBitmap.bytes_per_pixel;

    const data = arena.pushArray(byte_size, u8);

    const result: LoadedBitmap = .{
        .width = width,
        .height = height,
        .pitch = width * LoadedBitmap.bytes_per_pixel,
        .memory = @ptrCast(data.ptr),
    };

    return result;
}

pub inline fn makeEmptyBitmapClear(arena: *MemoryArena, width: i32, height: i32) LoadedBitmap {
    const result = makeEmptyBitmap(arena, width, height);
    clearBitmap(&result);
    return result;
}

pub inline fn clearBitmap(bitmap: *const LoadedBitmap) void {
    assert(bitmap.pitch > 0);

    const total_size: usize = @intCast(bitmap.width * bitmap.height * LoadedBitmap.bytes_per_pixel);
    @memset(bitmap.memory[0..total_size], 0);
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

        const read_result = pd.readEntireFile(thread_context, filename);
        if (read_result.len != 0) {
            const content = read_result;

            assert(content.len >= @sizeOf(BitmapHeader));
            const header: *BitmapHeader = @ptrCast(@alignCast(content));
            assert(header.header_size >= 40); // Earlier types are not binary compatible
            assert(header.compression == 3);

            const magic: [2]u8 = @bitCast(header.file_type);
            assert(std.mem.eql(u8, magic[0..], "BM"));

            assert(header.bits_per_pixel == 32); // TODO: account for scan line alignment
            result.memory = @ptrCast(content.ptr + header.bitmap_offset);
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

            const red_shift_down = red_scan.index;
            const green_shift_down = green_scan.index;
            const blue_shift_down = blue_scan.index;
            const alpha_shift_down = alpha_scan.index;

            const total_size: usize = @intCast(header.width * header.height * LoadedBitmap.bytes_per_pixel);
            const pixels: []align(1) u32 = @ptrCast(result.memory[0..total_size]);
            for (pixels) |*pixel| {
                const c = pixel.*;

                const a: f32 = @floatFromInt((c & alpha_mask) >> alpha_shift_down);
                var r: f32 = @floatFromInt((c & red_mask) >> red_shift_down);
                var g: f32 = @floatFromInt((c & green_mask) >> green_shift_down);
                var b: f32 = @floatFromInt((c & blue_mask) >> blue_shift_down);

                const an: f32 = a / 255;

                r = r * an;
                g = g * an;
                b = b * an;

                pixel.* =
                    @as(u32, @bitCast(@as(i32, @intFromFloat(r + 0.5)))) << 16 |
                    @as(u32, @bitCast(@as(i32, @intFromFloat(g + 0.5)))) << 8 |
                    @as(u32, @bitCast(@as(i32, @intFromFloat(b + 0.5)))) << 0 |
                    @as(u32, @bitCast(@as(i32, @intFromFloat(a + 0.5)))) << 24;
            }

            log.debug("Loaded bmp: {s} ({},{})", .{ filename, result.width, result.height });
        } else {
            log.debug("Failed to load bmp: {s} ({},{})", .{ filename, result.width, result.height });
        }

        result.pitch = -result.width * LoadedBitmap.bytes_per_pixel;
        result.memory = intrinsics.ptrOffset(result.memory, -result.pitch * (result.height - 1));

        return result;
    }
};
