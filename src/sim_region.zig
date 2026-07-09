const std = @import("std");
const assert = std.debug.assert;

const MemoryArena = @import("arena.zig");

const v10 = @import("v10.zig");
const StoredEntity = v10.LowEntity;

const _entities = @import("entity.zig");
const invalid_p = _entities.invalid_p;

const World = @import("world.zig");

const math = @import("math");
const V2 = math.V2;
const v2 = V2.init;
const Rect = math.Rect;

const entities_per_region = 4096;

game_state: *v10.GameState,
origin: World.Position,
bounds: Rect,
updateable_bounds: Rect,
max_entity_count: usize,
entities: []Entity,

// Must be power of 2!
sim_entity_hash: [entities_per_region]EntityHash,

const SimRegion = @This();

pub const EntityIndex = u32;

pub const EntityType = enum {
    null,
    hero,
    wall,
    familiar,
    monster,
    sword,
};

const FacingDirection = enum(u2) {
    right,
    up,
    left,
    down,
};

pub const HitPoint = struct {
    pub const max_amount = 4;

    flags: u8 = 0,
    amount: u8 = 0,
};

pub const EntityReference = union {
    ptr: ?*Entity,
    index: EntityIndex,
};

pub const EntityHash = struct {
    ptr: ?*Entity = null,
    index: EntityIndex = 0,
};

pub const EntityFlags = packed struct(u32) {
    collides: bool = false,
    non_spatial: bool = false,
    __reserved_0: u28 = 0,
    in_sim: bool = false,
    __reserved_1: u1 = 0,
};

pub const Entity = struct {
    storage_index: EntityIndex = 0,
    updatable: bool = false,

    type: EntityType = .null,
    flags: EntityFlags = .{},

    p: V2 = .zero,
    dp: V2 = .zero,

    z: f32 = 0,
    dz: f32 = 0,

    size: V2 = .zero,

    distance_limit: f32 = 0,

    facing_direction: FacingDirection = .down,

    t_bob: f32 = 0,

    d_abs_tile_z: i32 = 0,

    hitpoint_max: u32 = 0,
    hitpoints: [16]HitPoint = @splat(.{}),

    sword: EntityReference = .{ .index = 0 },
};

pub const MoveSpec = struct {
    unit_max_ddp: bool = true,
    speed: f32 = 0,
    drag: f32 = 0,
};

pub fn begin(sim_arena: *MemoryArena, game_state: *v10.GameState, region_origin: World.Position, region_bounds_: Rect) *SimRegion {
    const world = game_state.world;

    const sim_region = sim_arena.pushMemory(SimRegion);

    const update_safety_margin = 1;

    sim_region.* = .{
        .game_state = game_state,
        .origin = region_origin,
        .bounds = region_bounds_.addRadius(update_safety_margin, update_safety_margin),
        .updateable_bounds = region_bounds_,
        .max_entity_count = entities_per_region,
        .entities = sim_arena.pushArray(entities_per_region, Entity),
        .sim_entity_hash = @splat(std.mem.zeroes(EntityHash)),
    };
    sim_region.entities.len = 0;

    const min_chunk_p = region_origin.offset(world, sim_region.bounds.min);
    const max_chunk_p = region_origin.offset(world, sim_region.bounds.max);

    var chunk_y: i32 = min_chunk_p.chunk_y;
    while (chunk_y <= max_chunk_p.chunk_y) : (chunk_y += 1) {
        var chunk_x: i32 = min_chunk_p.chunk_x;
        while (chunk_x <= max_chunk_p.chunk_x) : (chunk_x += 1) {
            if (world.getChunk(chunk_x, chunk_y, region_origin.chunk_z, .{})) |chunk| {
                var block_opt: ?*World.EntityBlock = &chunk.first_entity_block;

                while (block_opt) |block| : (block_opt = block.next) {
                    for (block.entity_indices[0..block.entity_count]) |low_index| {
                        const low = &game_state.low_entities[low_index];
                        if (!low.sim.flags.non_spatial) {
                            const sim_space_p = sim_region.getSimSpaceP(low);
                            if (math.isInRectangle(sim_region.bounds, sim_space_p)) {
                                _ = addEntity(sim_region, low_index, low, sim_space_p);
                            }
                        }
                    }
                }
            }
        }
    }

    return sim_region;
}

pub fn end(this: *SimRegion) void {
    const world = this.game_state.world;

    for (this.entities) |*entity| {
        const stored = &this.game_state.low_entities[entity.storage_index];

        assert(stored.sim.flags.in_sim);
        stored.sim = entity.*;
        stored.sim.flags.in_sim = false;

        storeEntityReference(&stored.sim.sword);

        const new_p: World.Position = if (entity.flags.non_spatial) .null else this.origin.offset(world, entity.p);
        world.changeEntityLocation(&this.game_state.world_arena, entity.storage_index, stored, new_p);

        if (entity.storage_index == this.game_state.camera_following_entity_index) {
            var new_cam_p = this.game_state.camera_pos;
            new_cam_p.chunk_z = stored.p.chunk_z;

            if (false) {
                const x_bound_offset: i32 = @round(@as(f32, v10.GameState.screen_tile_width) / 2);
                if (entity.p.x > (x_bound_offset) * world.tile_side_in_meters) {
                    new_cam_p.abs_tile_x += v10.GameState.screen_tile_width;
                } else if (entity.p.x < -(x_bound_offset) * world.tile_side_in_meters) {
                    new_cam_p.abs_tile_x -= v10.GameState.screen_tile_width;
                }

                const y_bound_offset: i32 = @round(@as(f32, v10.GameState.screen_tile_height) / 2);
                if (entity.p.y > (y_bound_offset) * world.tile_side_in_meters) {
                    new_cam_p.abs_tile_y += v10.GameState.screen_tile_height;
                } else if (entity.p.y < -(y_bound_offset) * world.tile_side_in_meters) {
                    new_cam_p.abs_tile_y -= v10.GameState.screen_tile_height;
                }
            } else {
                new_cam_p = stored.p;
            }

            this.game_state.camera_pos = new_cam_p;
        }
    }
}

fn getHashFromStorageIndex(this: *SimRegion, storage_index: EntityIndex) *EntityHash {
    assert(storage_index != 0);

    var result: ?*EntityHash = null;

    const hash_value = storage_index;

    var offset: usize = 0;
    while (offset < this.sim_entity_hash.len) : (offset += 1) {
        const hash_mask: usize = this.sim_entity_hash.len - 1;
        const hash_index: usize = (hash_value + offset) & hash_mask;

        const entry = &this.sim_entity_hash[hash_index];
        if (entry.index == storage_index or entry.index == 0) {
            result = entry;
            break;
        }
    }

    assert(result != null);
    return result.?;
}

inline fn storeEntityReference(ref: *EntityReference) void {
    const index = if (ref.ptr) |ref_entity| ref_entity.storage_index else 0;
    ref.* = EntityReference{ .index = index };
}

inline fn getEntityByStorageIndex(this: *SimRegion, storage_index: EntityIndex) ?*Entity {
    const entry = this.getHashFromStorageIndex(storage_index);
    const result = entry.ptr;
    return result;
}

inline fn loadEntityReference(this: *SimRegion, ref: *EntityReference) void {
    const ptr: ?*Entity = if (ref.index == 0) null else blk: {
        const entry = this.getHashFromStorageIndex(ref.index);

        if (entry.ptr == null) {
            const low_entity = v10.getLowEntity(this.game_state, ref.index).?;

            const sim_space_p = this.getSimSpaceP(low_entity);
            const ptr = this.addEntity(ref.index, low_entity, sim_space_p);

            assert(entry.ptr == ptr);
            assert(entry.index == ref.index);
        }

        break :blk entry.ptr;
    };

    ref.* = EntityReference{ .ptr = ptr };
}

fn addEntityRaw(this: *SimRegion, storage_index: EntityIndex, source_opt: ?*StoredEntity) ?*Entity {
    assert(storage_index != 0);

    var entity_opt: ?*Entity = null;

    const entry = this.getHashFromStorageIndex(storage_index);
    if (entry.ptr == null) {
        if (this.entities.len < this.max_entity_count) {
            const entity: *Entity = @ptrCast(this.entities.ptr + this.entities.len);
            this.entities.len += 1;
            entity_opt = entity;

            entry.index = storage_index;
            entry.ptr = entity;

            if (source_opt) |source| {
                entity.* = source.sim;
                this.loadEntityReference(&entity.sword);

                assert(!source.sim.flags.in_sim);
                source.sim.flags.in_sim = true;
            }

            entity.storage_index = storage_index;
            entity.updatable = false;
        } else {
            // Out of entities
            unreachable;
        }
    }

    return entity_opt;
}

fn addEntity(this: *SimRegion, storage_index: EntityIndex, source_opt: ?*StoredEntity, sim_p_opt: ?V2) ?*Entity {
    var entity: ?*Entity = null;

    if (this.addEntityRaw(storage_index, source_opt)) |dest| {
        entity = dest;

        if (sim_p_opt) |sim_p| {
            dest.p = sim_p;
            dest.updatable = math.isInRectangle(this.updateable_bounds, dest.p);
        } else {
            assert(source_opt != null);
            dest.p = this.getSimSpaceP(source_opt.?);
        }
    }

    return entity;
}

inline fn getSimSpaceP(this: *SimRegion, stored: *StoredEntity) V2 {
    var result: V2 = invalid_p;

    if (!stored.sim.flags.non_spatial) {
        const diff = this.game_state.world.subtract(stored.p, this.origin);
        result = diff.xy;
    }

    return result;
}

pub inline fn makeEntitySpatial(entity: *Entity, p: V2, dp: V2) void {
    entity.flags.non_spatial = false;
    entity.p = p;
    entity.dp = dp;
}

pub inline fn makeEntityNonSpatial(entity: *Entity) void {
    entity.flags.non_spatial = true;
    entity.p = invalid_p;
}

fn handleCollision(a: *Entity, b: *Entity) void {
    if (a.type == .monster and b.type == .sword) {
        a.hitpoint_max = if (a.hitpoint_max == 0) 0 else a.hitpoint_max - 1;
        makeEntityNonSpatial(b);
    }
}

pub fn moveEntity(this: *SimRegion, entity: *Entity, dt: f32, move_spec: MoveSpec, raw_ddp: V2) void {
    assert(!entity.flags.non_spatial);

    var ddp = blk: {
        if (move_spec.unit_max_ddp) {
            const ddp_length_sq = raw_ddp.lengthSquared();

            if (ddp_length_sq > 1) {
                break :blk raw_ddp.mul(1 / @sqrt(ddp_length_sq));
            }
        }

        break :blk raw_ddp;
    };

    ddp = ddp.mul(move_spec.speed);
    ddp = ddp.add(entity.dp.mul(-move_spec.drag));

    var player_delta = V2.add(
        ddp.mul(0.5 * math.square(dt)),
        entity.dp.mul(dt),
    );
    entity.dp = entity.dp.add(ddp.mul(dt));

    const ddz = -9.8;
    entity.z = @max(0, (0.5 * ddz * math.square(dt)) + (entity.dz * dt) + entity.z);
    entity.dz = (ddz * dt) + entity.dz;

    var distance_remaining = entity.distance_limit;
    if (distance_remaining == 0) {
        distance_remaining = 10000;
    }

    var it_count: usize = 0;
    while (it_count < 4) : (it_count += 1) {
        var t_min: f32 = 1;

        const player_delta_length = player_delta.length();
        if (player_delta_length > 0) {
            if (player_delta_length > distance_remaining) {
                t_min = distance_remaining / player_delta_length;
            }

            var wall_normal: V2 = .zero;
            var hit_entity_opt: ?*Entity = null;

            const desired_position = entity.p.add(player_delta);

            const stops_on_collision = entity.flags.collides;

            if (!entity.flags.non_spatial) {
                for (this.entities) |*test_entity| {
                    if (entity != test_entity) {
                        if (test_entity.flags.collides and !test_entity.flags.non_spatial) {
                            const diameter = test_entity.size.add(entity.size);
                            const min_corner = diameter.mul(-0.5);
                            const max_corner = diameter.mul(0.5);

                            const rel = entity.p.sub(test_entity.p);

                            if (testWall(min_corner.x, rel.x, rel.y, player_delta.x, player_delta.y, &t_min, min_corner.y, max_corner.y)) {
                                wall_normal = v2(-1, 0);
                                hit_entity_opt = test_entity;
                            }
                            if (testWall(max_corner.x, rel.x, rel.y, player_delta.x, player_delta.y, &t_min, min_corner.y, max_corner.y)) {
                                wall_normal = v2(1, 0);
                                hit_entity_opt = test_entity;
                            }
                            if (testWall(min_corner.y, rel.y, rel.x, player_delta.y, player_delta.x, &t_min, min_corner.x, max_corner.x)) {
                                wall_normal = v2(0, -1);
                                hit_entity_opt = test_entity;
                            }
                            if (testWall(max_corner.y, rel.y, rel.x, player_delta.y, player_delta.x, &t_min, min_corner.x, max_corner.x)) {
                                wall_normal = v2(0, 1);
                                hit_entity_opt = test_entity;
                            }
                        }
                    }
                }
            }

            if (test_wall_hh) {
                // Current hh version, gets stuck on edges perpendicular to the one the player is sliding along.
                entity.p = entity.p.add(player_delta.mul(t_min));
            } else {
                const push_out: f32 = 0.0001;
                const delta = player_delta.mul(t_min).add(wall_normal.mul(push_out));
                entity.p = entity.p.add(delta);
            }
            distance_remaining -= t_min * player_delta_length;

            if (hit_entity_opt) |hit_entity| {
                player_delta = desired_position.sub(entity.p);
                if (stops_on_collision) {
                    player_delta = player_delta.sub(wall_normal.mul(player_delta.inner(wall_normal)));
                    entity.dp = entity.dp.sub(wall_normal.mul(entity.dp.inner(wall_normal)));
                }

                var a = entity;
                var b = hit_entity;
                if (@intFromEnum(a.type) > @intFromEnum(b.type)) {
                    const temp = a;
                    a = b;
                    b = temp;
                }
                handleCollision(a, b);
            } else {
                break;
            }
        } else {
            break;
        }
    }

    if (entity.distance_limit != 0) {
        entity.distance_limit = distance_remaining;
    }

    entity.facing_direction =
        if (entity.dp.x == 0 and entity.dp.y == 0)
            entity.facing_direction
        else if (@abs(entity.dp.x) > @abs(entity.dp.y))
            if (entity.dp.x > 0) .right else .left
        else if (entity.dp.y > 0) .up else .down;
}

const test_wall_hh = true;
fn testWall(wall_x: f32, test_x: f32, test_y: f32, delta_x: f32, delta_y: f32, t_min: *f32, wall_min_y: f32, wall_max_y: f32) bool {
    var hit = false;

    if (delta_x != 0) {
        const t_result = (wall_x - test_x) / delta_x;

        if (t_result >= 0 and t_min.* > t_result) {
            const y = test_y + (t_result * delta_y);
            if (y >= wall_min_y and y <= wall_max_y) {
                if (test_wall_hh) {
                    // Current hh version, gets stuck on edges perpendicular to the one the player is sliding along.
                    const t_epsilon: f32 = 0.0001;
                    t_min.* = @max(0, t_result - t_epsilon);
                } else {
                    t_min.* = t_result;
                }
                hit = true;
            }
        }
    }

    return hit;
}
