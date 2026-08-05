const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.v10);

const common = @import("v10_common");
const intrinsics = @import("intrinsics.zig");

const SimRegion = @import("sim_region.zig");
const MoveSpec = SimRegion.MoveSpec;

const Entity = @import("entity.zig");
const EntityIndex = Entity.Index;
const EntityType = Entity.Type;
const EntityReference = Entity.Reference;
const HitPoint = Entity.HitPoint;

const math = @import("math");
const V2 = math.V2;
const v2 = V2.init;
const V3 = math.V3;
const v3 = V3.init;
const V4 = math.V4;
const v4 = V4.init;
const Rect3 = math.Rect3;

const Random = @import("random.zig");
const MemoryArena = @import("arena.zig");
const TemporaryMemory = MemoryArena.TemporaryMemory;
const World = @import("world.zig");

const ThreadContext = common.ThreadContext;
const Memory = common.Memory;
const Input = common.Input;
const OffscreenBuffer = common.OffscreenBuffer;
const AudioBuffer = common.AudioBuffer;

const os = @import("builtin").os.tag;

pub const std_options = common.std_options;

pub const LowEntity = struct {
    sim: Entity = .{},
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
    pub const double_entries = false;

    can_collide: bool,
    storage_index_a: EntityIndex,
    storage_index_b: EntityIndex,

    next_in_hash: ?*PairwiseCollisionRule = null,
};

pub const GroundBuffer = struct {
    p: World.Position = .zero,
    data: []u32,
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
};

pub const TransientState = struct {
    initialized: bool = false,

    arena: MemoryArena = undefined,

    ground_bitmap_template: LoadedBitmap = .{},
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
            .a = 0,
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
        found.can_collide = should_collide;
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

pub fn drawRectangle(buffer: *LoadedBitmap, min: V2, max: V2, r: f32, g: f32, b: f32) void {
    const pitch: usize = @intCast(buffer.pitch);
    const bpp: usize = @intCast(OffscreenBuffer.bytes_per_pixel);

    const buffer_width_f: f32 = @floatFromInt(buffer.width);
    const buffer_height_f: f32 = @floatFromInt(buffer.height);

    const minx: usize = @round(@min(@max(min.x, 0), buffer_width_f));
    const miny: usize = @round(@min(@max(min.y, 0), buffer_height_f));
    const maxx: usize = @round(@min(@max(max.x, 0), buffer_width_f));
    const maxy: usize = @round(@min(@max(max.y, 0), buffer_height_f));

    assert(bpp == @sizeOf(u32));

    const color = ColorU8ARGB.fromF32RGB(r, g, b);

    var row: [*]u8 = @as([*]u8, @ptrCast(buffer.memory)) + (minx * bpp) + (miny * pitch);
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

pub const DrawRectangleOutlineOptions = struct {
    r: f32 = 2,
};

pub inline fn drawRectangleOutline(buffer: *LoadedBitmap, min: V2, max: V2, color: V3, o: DrawRectangleOutlineOptions) void {
    const vr: V2 = .scalar(o.r);
    const c = color.color();

    drawRectangle(buffer, v2(min.x, min.y).sub(vr), v2(max.x, min.y).add(vr), c.r, c.g, c.b);
    drawRectangle(buffer, v2(min.x, max.y).sub(vr), v2(max.x, max.y).add(vr), c.r, c.g, c.b);

    drawRectangle(buffer, v2(min.x, min.y).sub(vr), v2(min.x, max.y).add(vr), c.r, c.g, c.b);
    drawRectangle(buffer, v2(max.x, min.y).sub(vr), v2(max.x, max.y).add(vr), c.r, c.g, c.b);
}

pub fn drawBitmap(buffer: *LoadedBitmap, bitmap: *const LoadedBitmap, px: f32, py: f32, c_alpha: f32) void {
    const bpp = LoadedBitmap.bytes_per_pixel;

    const real_x: f32 = px;
    const real_y: f32 = py;

    var min_x: i32 = @round(real_x);
    var min_y: i32 = @round(real_y);
    var max_x: i32 = min_x + @as(i32, @intCast(bitmap.width));
    var max_y: i32 = min_y + @as(i32, @intCast(bitmap.height));

    var source_offset_x: i32 = 0;
    if (min_x < 0) {
        source_offset_x = @intCast(-min_x);
        min_x = 0;
    }

    var source_offset_y: i32 = 0;
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

    max_x = @intCast(@max(0, max_x));
    max_y = @intCast(@max(0, max_y));

    // TEMPORARY
    if (bitmap.width == 0 or bitmap.height == 0) return;
    // TEMPORARY

    const source_offset: usize = @bitCast(@as(isize, @intCast(source_offset_y * bitmap.pitch + bpp * source_offset_x)));
    var source_row: [*]u8 = @as([*]u8, @ptrCast(bitmap.memory)) + source_offset;

    const dest_offset: usize = @bitCast(@as(isize, @intCast((min_x * bpp) + (min_y * buffer.pitch))));
    var dest_row: [*]u8 = @as([*]u8, @ptrCast(buffer.memory)) + dest_offset;

    var y: usize = @intCast(min_y);
    while (y < max_y) : (y += 1) {
        var source: [*]align(1) u32 = @ptrCast(source_row);
        var dest: [*]align(1) u32 = @ptrCast(dest_row);

        var x: usize = @intCast(min_x);
        while (x < max_x) : (x += 1) {
            const sc = ColorU8ARGB.fromU32(source[0]);
            const dc = ColorU8ARGB.fromU32(dest[0]);

            const sa: f32 = sc.a;
            const rsa: f32 = (sa / 255) * c_alpha;
            const sr: f32 = c_alpha * sc.r;
            const sg: f32 = c_alpha * sc.g;
            const sb: f32 = c_alpha * sc.b;

            const da: f32 = dc.a;
            const dr: f32 = dc.r;
            const dg: f32 = dc.g;
            const db: f32 = dc.b;
            const rda: f32 = (da / 255);

            const inv_rsa: f32 = 1 - rsa;
            const a: f32 = 255 * (rsa + rda - (rsa * rda));
            const r: f32 = inv_rsa * dr + sr;
            const g: f32 = inv_rsa * dg + sg;
            const b: f32 = inv_rsa * db + sb;

            // dest[0] = (ColorU8ARGB{
            //     .r = @intFromFloat(r + 0.5),
            //     .g = @intFromFloat(g + 0.5),
            //     .b = @intFromFloat(b + 0.5),
            //     .a = @intFromFloat(a + 0.5),
            // }).asU32();

            dest[0] =
                @as(u32, @bitCast(@as(i32, @intFromFloat(a + 0.5)))) << 24 |
                @as(u32, @bitCast(@as(i32, @intFromFloat(r + 0.5)))) << 16 |
                @as(u32, @bitCast(@as(i32, @intFromFloat(g + 0.5)))) << 8 |
                @as(u32, @bitCast(@as(i32, @intFromFloat(b + 0.5)))) << 0;

            source += 1;
            dest += 1;
        }

        dest_row += @bitCast(@as(isize, @intCast(buffer.pitch)));
        source_row += @bitCast(@as(isize, @intCast(bitmap.pitch)));
    }
}

pub const LoadedBitmap = struct {
    width: i32 = 0,
    height: i32 = 0,
    pitch: i32 = 0,
    memory: [*]align(1) u32 = undefined,
    data: []align(1) u32 = &.{},

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

        game_state.world = game_state.world_arena.pushMemory(World);
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

        tran_state.ground_buffers = tran_state.arena.pushArray(32, GroundBuffer);

        for (tran_state.ground_buffers) |*ground_buffer| {
            ground_buffer.p = .null;
            tran_state.ground_bitmap_template = makeEmptyBitmap(&tran_state.arena, ground_buffer_width, ground_buffer_height);
            ground_buffer.data = @ptrCast(@alignCast(tran_state.ground_bitmap_template.data));
        }

        tran_state.initialized = true;
    }

    if (input.executable_reloaded) {
        for (tran_state.ground_buffers) |*ground_buffer| {
            ground_buffer.p = .null;
        }
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

    assert(offscreen_buffer.pitch >= offscreen_buffer.width);
    const offscreen_buffer_data = offscreen_buffer.memory[0 .. @as(usize, @intCast(offscreen_buffer.pitch * offscreen_buffer.height)) * OffscreenBuffer.bytes_per_pixel];

    var draw_buffer_: LoadedBitmap = .{
        .width = offscreen_buffer.width,
        .height = offscreen_buffer.height,
        .pitch = offscreen_buffer.pitch,
        .memory = @ptrCast(offscreen_buffer_data.ptr),
        .data = @ptrCast(offscreen_buffer_data),
    };
    const draw_buffer = &draw_buffer_;

    // @memset(@as([]u32, @ptrCast(@alignCast(offscreen_buffer.memory[0..offscreen_buffer.memory_len]))), 0xff00ff);
    drawRectangle(draw_buffer, V2.zero, .i(offscreen_buffer.width, offscreen_buffer.height), 0.5, 0.5, 0.5);

    const screen_center = v2(
        @floatFromInt(@divTrunc(offscreen_buffer.width, 2)),
        @floatFromInt(@divTrunc(offscreen_buffer.height, 2)),
    );

    const screen_width_meters = @as(f32, @floatFromInt(draw_buffer.width)) * game_state.pixels_to_meters;
    const screen_height_meters = @as(f32, @floatFromInt(draw_buffer.height)) * game_state.pixels_to_meters;

    const camera_bounds_meters = Rect3.centerDim(.zero, v3(screen_width_meters, screen_height_meters, 0));

    for (tran_state.ground_buffers) |*ground_buffer| {
        if (ground_buffer.p.isValid()) {
            var bitmap = tran_state.ground_bitmap_template;
            bitmap.data = ground_buffer.data;
            bitmap.memory = ground_buffer.data.ptr;

            const delta = world.subtract(ground_buffer.p, game_state.camera_pos).mul(game_state.meters_to_pixels);
            const ground_p: V2 = v2(
                screen_center.x + delta.x - 0.5 * @as(f32, @floatFromInt(bitmap.width)),
                screen_center.y - delta.y - 0.5 * @as(f32, @floatFromInt(bitmap.height)),
            );

            drawBitmap(draw_buffer, &bitmap, ground_p.x, ground_p.y, 1);
        }
    }

    chunk_fill_blk: {
        const min_chunk_p = game_state.camera_pos.offset(world, camera_bounds_meters.min);
        const max_chunk_p = game_state.camera_pos.offset(world, camera_bounds_meters.max);

        const screen_dim = world.chunk_dim_in_meters.xy().mul(game_state.meters_to_pixels);

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

                    const screen_p = v2(
                        screen_center.x + game_state.meters_to_pixels * rel_p.x,
                        screen_center.y - game_state.meters_to_pixels * rel_p.y,
                    );

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
                        fillGroundChunk(tran_state, game_state, empty_buffer, chunk_center_p);
                        break :chunk_fill_blk;
                    }

                    // drawRectangleOutline(
                    //     draw_buffer,
                    //     screen_p.sub(screen_dim.mul(0.5)),
                    //     screen_p.add(screen_dim.mul(0.5)),
                    //     v3(1, 1, 0),
                    //     .{},
                    // );
                    _ = .{ screen_dim, screen_p };
                }
            }
        }
    }

    const sim_bounds_extension: V3 = .scalar(15);
    const sim_bounds = camera_bounds_meters.addRadius(sim_bounds_extension);

    const sim_memory = TemporaryMemory.begin(&tran_state.arena);
    const sim_region = SimRegion.begin(sim_memory.arena, game_state, game_state.camera_pos, sim_bounds, input.dt);

    var piece_group: EntityVisiblePieceGroup = .{ .game_state = game_state };
    for (sim_region.entities) |*entity| {
        if (entity.updatable) {
            piece_group.count = 0;

            const shadow_alpha = @max(0, 1 - (0.5 * entity.p.z));

            var move_spec: MoveSpec = .{};
            var ddp: V3 = .zero;

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
                    ddp = V3.zero;

                    if (entity.distance_limit == 0) {
                        clearCollisionRulesFor(game_state, entity.storage_index);
                        SimRegion.makeEntityNonSpatial(entity);
                    }

                    pushBitmap(&piece_group, &game_state.hero_shadow, V2.zero, 0, hero_bitmap.alignment, .{ .alpha = shadow_alpha, .entity_z_c = 0 });
                    pushBitmap(&piece_group, &game_state.sword, V2.zero, 0, v2(29, 10), .{});
                },

                .stairwell => {
                    pushRect(&piece_group, .zero, 0, entity.walkable_dim, v4(1, 0.5, 0, 1), .{ .entity_z_c = 0 });
                    pushRect(&piece_group, .zero, entity.walkable_height, entity.walkable_dim, v4(1, 1, 0, 1), .{ .entity_z_c = 0 });
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

                .space => {
                    // for (entity.collision.volumes) |*volume| {
                    //     pushRectOutline(&piece_group, volume.offset.xy(), 0, volume.dim.xy(), v4(0, 0.5, 1, 1), .{});
                    // }
                },
            }

            if (!entity.flags.non_spatial and
                entity.flags.moveable)
            {
                sim_region.moveEntity(game_state, entity, input.dt, move_spec, ddp);
            }

            if (entity.p.x != Entity.invalid_p.x and
                entity.p.y != Entity.invalid_p.y and
                entity.p.z != Entity.invalid_p.z)
            {
                const entity_base_p = entity.getGroundPoint();

                for (piece_group.pieces[0..piece_group.count]) |*piece| {
                    const z_fudge = 1 + (0.1 * (entity_base_p.z + piece.offset_z));

                    const entity_ground_point = v2(
                        screen_center.x + (game_state.meters_to_pixels * entity_base_p.x * z_fudge),
                        screen_center.y - (game_state.meters_to_pixels * entity_base_p.y * z_fudge),
                    );

                    const entity_z = game_state.meters_to_pixels * -entity_base_p.z;
                    // const entity_z = 0;

                    const center = v2(
                        entity_ground_point.x + piece.offset.x,
                        entity_ground_point.y + piece.offset.y + (piece.entity_z_c * entity_z),
                    );

                    if (piece.bitmap) |bitmap| {
                        drawBitmap(draw_buffer, bitmap, center.x, center.y, piece.a);
                    } else {
                        const dim = piece.dim.mul(game_state.meters_to_pixels);
                        const half_dim = dim.mul(0.5);
                        drawRectangle(
                            draw_buffer,
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
    }

    sim_region.end(game_state);

    sim_memory.end();

    game_state.world_arena.check();
    tran_state.arena.check();
}

fn fillGroundChunk(trans_state: *TransientState, game_state: *GameState, ground_buffer: *GroundBuffer, chunk_p: World.Position) void {
    var bitmap = trans_state.ground_bitmap_template;
    bitmap.data = ground_buffer.data;
    bitmap.memory = ground_buffer.data.ptr;

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
                drawBitmap(&bitmap, stamp, p.x, p.y, 1);
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

            for (0..30) |_| {
                const stamp = &game_state.tuft[series.randomChoice(game_state.tuft.len)];

                const bitmap_center = V2.i(stamp.width, stamp.height).mul(0.5);

                const offset: V2 = v2(
                    width * series.randomUnilateral(),
                    height * series.randomUnilateral(),
                );

                const p = center.add(offset).sub(bitmap_center);
                drawBitmap(&bitmap, stamp, p.x, p.y, 1);
            }
        }
    }
}

pub fn makeEmptyBitmap(arena: *MemoryArena, width: i32, height: i32) LoadedBitmap {
    const byte_size: usize = @as(usize, @intCast(width * height)) * LoadedBitmap.bytes_per_pixel;

    const data = arena.pushArray(byte_size, u8);

    const result: LoadedBitmap = .{
        .width = width,
        .height = height,
        .pitch = width * LoadedBitmap.bytes_per_pixel,
        .memory = @ptrCast(data.ptr),
        .data = @ptrCast(data),
    };

    return result;
}

pub inline fn makeEmptyBitmapClear(arena: *MemoryArena, width: i32, height: i32) LoadedBitmap {
    const result = makeEmptyBitmap(arena, width, height);
    clearBitmap(&result);
    return result;
}

pub inline fn clearBitmap(bitmap: *LoadedBitmap) void {
    @memset(bitmap.data, 0);
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
        .offset_z = offset_z,
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

inline fn pushRectOutline(group: *EntityVisiblePieceGroup, offset: V2, offset_z: f32, dim: V2, color: V4, o: PushRectOptions) void {
    const thickness = 0.1;

    pushPiece(group, null, offset.sub(v2(0, 0.5 * dim.y)), offset_z, v2(dim.x, thickness), .zero, o.entity_z_c, color);
    pushPiece(group, null, offset.add(v2(0, 0.5 * dim.y)), offset_z, v2(dim.x, thickness), .zero, o.entity_z_c, color);

    pushPiece(group, null, offset.sub(v2(0.5 * dim.x, 0)), offset_z, v2(thickness, dim.y), .zero, o.entity_z_c, color);
    pushPiece(group, null, offset.add(v2(0.5 * dim.x, 0)), offset_z, v2(thickness, dim.y), .zero, o.entity_z_c, color);
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
            result.data = result.memory[0..@intCast(header.width * header.height)];
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

            // if (red_scan.index != 16 or green_scan.index != 8 or
            //     blue_scan.index != 0 or alpha_scan.index != 24)
            // {
            const red_shift_down = red_scan.index;
            const green_shift_down = green_scan.index;
            const blue_shift_down = blue_scan.index;
            const alpha_shift_down = alpha_scan.index;

            for (result.data) |*pixel| {
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
            // }

            log.debug("Loaded bmp: {s} ({},{})", .{ filename, result.width, result.height });
        } else {
            log.debug("Failed to load bmp: {s} ({},{})", .{ filename, result.width, result.height });
        }

        result.pitch = -result.width * LoadedBitmap.bytes_per_pixel;
        result.memory = @ptrCast(@as([*]u8, @ptrCast(result.memory)) + @as(usize, @bitCast(@as(isize, -result.pitch * (result.height - 1)))));

        return result;
    }
};
