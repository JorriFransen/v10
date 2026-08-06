const std = @import("std");
const assert = std.debug.assert;

const MemoryArena = @import("arena.zig");

const v10 = @import("v10.zig");
const GameState = v10.GameState;
const LowEntity = v10.LowEntity;
const PairwiseCollisionRule = v10.PairwiseCollisionRule;

const Entity = @import("entity.zig");
const EntityIndex = Entity.Index;
const EntityReference = Entity.Reference;
const invalid_p = Entity.invalid_p;

const World = @import("world.zig");

const math = @import("math");
const V3 = math.V3;
const v3 = V3.init;
const Rect3 = math.Rect3;

const entities_per_region = 4096;

max_entity_radius: f32 = undefined,
max_entity_velocity: f32 = undefined,
origin: World.Position,
bounds: Rect3,
updateable_bounds: Rect3,
max_entity_count: usize,
entities: []Entity,

// Must be power of 2!
sim_entity_hash: [entities_per_region]EntityHash,

const SimRegion = @This();

pub const EntityHash = struct {
    ptr: ?*Entity = null,
    index: EntityIndex = 0,
};

pub const MoveSpec = struct {
    unit_max_ddp: bool = true,
    speed: f32 = 0,
    drag: f32 = 0,
};
const TestWall = struct {
    x: f32,
    rel_x: f32,
    rel_y: f32,
    delta_x: f32,
    delta_y: f32,
    min_y: f32,
    max_y: f32,

    normal: V3,

    pub inline fn init(x: f32, rel_x: f32, rel_y: f32, delta_x: f32, delta_y: f32, min_y: f32, max_y: f32, normal: V3) @This() {
        return .{
            .x = x,
            .rel_x = rel_x,
            .rel_y = rel_y,
            .delta_x = delta_x,
            .delta_y = delta_y,
            .min_y = min_y,
            .max_y = max_y,
            .normal = normal,
        };
    }
};

pub fn begin(sim_arena: *MemoryArena, game_state: *GameState, region_origin: World.Position, bounds: Rect3, dt: f32) *SimRegion {
    const world = game_state.world;

    const sim_region = sim_arena.push(SimRegion);

    {
        sim_region.max_entity_radius = 5;
        sim_region.max_entity_velocity = 30;
        const update_safety_margin = sim_region.max_entity_radius + (dt * sim_region.max_entity_velocity);
        const update_safety_margin_z = 1;

        const updatable_bounds = bounds.addRadius(.scalar(sim_region.max_entity_radius));

        sim_region.* = .{
            .origin = region_origin,
            .bounds = updatable_bounds.addRadius(v3(update_safety_margin, update_safety_margin, update_safety_margin_z)),
            .updateable_bounds = updatable_bounds,
            .max_entity_count = entities_per_region,
            .entities = sim_arena.pushArray(entities_per_region, Entity),
            .sim_entity_hash = @splat(std.mem.zeroes(EntityHash)),
        };
        sim_region.entities.len = 0;
    }

    const min_chunk_p = region_origin.offset(world, sim_region.bounds.min);
    const max_chunk_p = region_origin.offset(world, sim_region.bounds.max);

    var chunk_z: i32 = min_chunk_p.chunk_z;
    while (chunk_z <= max_chunk_p.chunk_z) : (chunk_z += 1) {
        //
        var chunk_y: i32 = min_chunk_p.chunk_y;
        while (chunk_y <= max_chunk_p.chunk_y) : (chunk_y += 1) {
            //
            var chunk_x: i32 = min_chunk_p.chunk_x;
            while (chunk_x <= max_chunk_p.chunk_x) : (chunk_x += 1) {
                //
                if (world.getChunk(chunk_x, chunk_y, chunk_z, .{})) |chunk| {
                    var block_opt: ?*World.EntityBlock = &chunk.first_entity_block;

                    while (block_opt) |block| : (block_opt = block.next) {
                        for (block.entity_indices[0..block.entity_count]) |low_index| {
                            const low = &game_state.low_entities[low_index];
                            if (!low.sim.flags.non_spatial) {
                                const sim_space_p = sim_region.getSimSpaceP(game_state, low);
                                if (entityOverlapsRectangle(sim_space_p, low.sim.collision.total_volume, sim_region.bounds)) {
                                    _ = sim_region.addEntity(game_state, low_index, low, sim_space_p);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return sim_region;
}

pub fn end(this: *SimRegion, game_state: *GameState) void {
    const world = game_state.world;

    for (this.entities) |*entity| {
        const stored = &game_state.low_entities[entity.storage_index];

        assert(stored.sim.flags.in_sim);
        stored.sim = entity.*;
        stored.sim.flags.in_sim = false;

        storeEntityReference(&stored.sim.sword);

        const new_p: World.Position = if (entity.flags.non_spatial) .null else this.origin.offset(world, entity.p);
        world.changeEntityLocation(&game_state.world_arena, entity.storage_index, stored, new_p);

        if (entity.storage_index == game_state.camera_following_entity_index) {
            var new_cam_p = game_state.camera_pos;
            new_cam_p.chunk_z = stored.p.chunk_z;

            if (false) {
                const x_bound_offset: i32 = @round(@as(f32, GameState.screen_tile_width) / 2);
                if (entity.p.x > (x_bound_offset) * world.tile_side_in_meters) {
                    new_cam_p.abs_tile_x += GameState.screen_tile_width;
                } else if (entity.p.x < -(x_bound_offset) * world.tile_side_in_meters) {
                    new_cam_p.abs_tile_x -= GameState.screen_tile_width;
                }

                const y_bound_offset: i32 = @round(@as(f32, GameState.screen_tile_height) / 2);
                if (entity.p.y > (y_bound_offset) * world.tile_side_in_meters) {
                    new_cam_p.abs_tile_y += GameState.screen_tile_height;
                } else if (entity.p.y < -(y_bound_offset) * world.tile_side_in_meters) {
                    new_cam_p.abs_tile_y -= GameState.screen_tile_height;
                }
            } else {
                const cam_z_offset = new_cam_p._offset.z;
                new_cam_p = stored.p;
                new_cam_p._offset.z = cam_z_offset;
            }

            game_state.camera_pos = new_cam_p;
        }
    }
}

inline fn entityOverlapsRectangle(p: V3, volume: Entity.CollisionVolume, rect: Rect3) bool {
    // const minkowski_rect = rect.addRadius(volume.dim.mul(0.5));
    // const result = math.isInRectangle3(minkowski_rect, p.add(volume.offset));
    // return result;

    const entity_rect: Rect3 = .centerDim(p.add(volume.offset), volume.dim);
    const result = entity_rect.intersects(rect);
    return result;
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

inline fn loadEntityReference(this: *SimRegion, game_state: *GameState, ref: *EntityReference) void {
    const ptr: ?*Entity = if (ref.index == 0) null else blk: {
        const entry = this.getHashFromStorageIndex(ref.index);

        if (entry.ptr == null) {
            const low_entity = v10.getLowEntity(game_state, ref.index).?;

            const sim_space_p = this.getSimSpaceP(game_state, low_entity);
            const ptr = this.addEntity(game_state, ref.index, low_entity, sim_space_p);

            assert(entry.ptr == ptr);
            assert(entry.index == ref.index);
        }

        break :blk entry.ptr;
    };

    ref.* = EntityReference{ .ptr = ptr };
}

fn addEntityRaw(this: *SimRegion, game_state: *GameState, storage_index: EntityIndex, source_opt: ?*LowEntity) ?*Entity {
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
                this.loadEntityReference(game_state, &entity.sword);

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

fn addEntity(this: *SimRegion, game_state: *GameState, storage_index: EntityIndex, source_opt: ?*LowEntity, sim_p_opt: ?V3) ?*Entity {
    var entity: ?*Entity = null;

    if (this.addEntityRaw(game_state, storage_index, source_opt)) |dest| {
        entity = dest;

        if (sim_p_opt) |sim_p| {
            dest.p = sim_p;
            dest.updatable = entityOverlapsRectangle(dest.p, dest.collision.total_volume, this.updateable_bounds);
        } else {
            assert(source_opt != null);
            dest.p = this.getSimSpaceP(game_state, source_opt.?);
        }
    }

    return entity;
}

inline fn getSimSpaceP(this: *SimRegion, game_state: *GameState, stored: *LowEntity) V3 {
    var result: V3 = invalid_p;

    if (!stored.sim.flags.non_spatial) {
        result = game_state.world.subtract(stored.p, this.origin);
    }

    return result;
}

pub inline fn makeEntitySpatial(entity: *Entity, p: V3, dp: V3) void {
    entity.flags.non_spatial = false;
    entity.p = p;
    entity.dp = dp;
}

pub inline fn makeEntityNonSpatial(entity: *Entity) void {
    entity.flags.non_spatial = true;
    entity.p = invalid_p;
}

fn canOverlap(game_state: *GameState, moving: *Entity, region: *Entity) bool {
    _ = game_state;

    var result = false;

    if (moving != region) {
        if (region.type == .stairwell) {
            result = true;
        }
    }

    return result;
}

fn handleOverlap(game_state: *GameState, mover: *Entity, region: *Entity, dt: f32, ground: *f32) void {
    _ = game_state;
    _ = dt;

    if (region.type == .stairwell) {
        ground.* = region.getStairGround(mover.getGroundPoint());
    }
}

fn canCollide(game_state: *GameState, a_: *Entity, b_: *Entity) bool {
    var result = false;

    if (a_ != b_) {
        const a: *Entity, const b: *Entity = if (a_.storage_index > b_.storage_index)
            .{ b_, a_ }
        else
            .{ a_, b_ };

        if (a.flags.collides and b.flags.collides) {
            if (!a.flags.non_spatial and !b.flags.non_spatial) {
                result = true;
            }

            const hash_bucket = a.storage_index & (game_state.collision_rule_hash.len - 1);
            var rule_opt: ?*PairwiseCollisionRule = game_state.collision_rule_hash[hash_bucket];

            while (rule_opt) |rule| : (rule_opt = rule.next_in_hash) {
                if (rule.storage_index_a == a.storage_index and
                    rule.storage_index_b == b.storage_index)
                {
                    result = rule.can_collide;
                    break;
                }
            }
        }
    }

    return result;
}

fn handleCollision(game_state: *GameState, a_: *Entity, b_: *Entity) bool {
    var stops_on_collision = false;

    if (a_.type == .sword) {
        _ = v10.addCollisionRule(game_state, a_.storage_index, b_.storage_index, false);
        stops_on_collision = false;
    } else {
        stops_on_collision = true;
    }

    const a: *Entity, const b: *Entity = if (@intFromEnum(a_.type) > @intFromEnum(b_.type))
        .{ b_, a_ }
    else
        .{ a_, b_ };

    if (a.type == .monster and b.type == .sword) {
        if (a.hitpoint_max > 0) {
            a.hitpoint_max -= 1;
        }
    }

    return stops_on_collision;
}

pub fn speculativeCollide(mover: *Entity, region: *Entity, test_p: V3) bool {
    var result = true;

    if (region.type == .stairwell) {
        const step_height: f32 = 0.1;

        _ = test_p;
        const mover_ground_point = mover.getGroundPoint();
        const ground = region.getStairGround(mover_ground_point);
        result = @abs(mover_ground_point.z - ground) > step_height;
    }

    return result;
}

pub fn EntitiesOverlapEpsilon(entity: *const Entity, test_entity: *const Entity, epsilon: V3) bool {
    var result = false;

    volume_loop: for (entity.collision.volumes) |*volume| {
        const entity_rect: Rect3 = .centerDim(entity.p.add(volume.offset), volume.dim.add(epsilon));

        for (test_entity.collision.volumes) |*test_volume| {
            const test_entity_rect: Rect3 = .centerDim(test_entity.p.add(test_volume.offset), test_volume.dim);

            if (entity_rect.intersects(test_entity_rect)) {
                result = true;
                break :volume_loop;
            }
        }
    }

    return result;
}

pub inline fn EntitiesOverlap(entity: *const Entity, test_entity: *const Entity) bool {
    const result = EntitiesOverlapEpsilon(entity, test_entity, .zero);
    return result;
}

pub fn moveEntity(this: *SimRegion, game_state: *GameState, entity: *Entity, dt: f32, move_spec: MoveSpec, raw_ddp: V3) void {
    assert(!entity.flags.non_spatial);

    if (entity.type == .hero and raw_ddp.lengthSquared() > 0) {
        const break_here = 5;
        _ = break_here;
    }

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

    var drag = entity.dp.mul(-move_spec.drag);
    drag.z = 0;
    ddp = ddp.add(drag);

    if (!entity.flags.z_supported) {
        ddp.z += -9.8;
    }

    var player_delta = V3.add(
        ddp.mul(0.5 * math.square(dt)),
        entity.dp.mul(dt),
    );
    entity.dp = entity.dp.add(ddp.mul(dt));

    assert(entity.dp.lengthSquared() <= math.square(this.max_entity_velocity));

    var distance_remaining = entity.distance_limit;
    if (distance_remaining == 0) {
        distance_remaining = 10000;
    }

    for (0..4) |_| {
        var t_min: f32 = 1;
        var t_max: f32 = 0;

        const player_delta_length = player_delta.length();
        if (player_delta_length > 0) {
            if (player_delta_length > distance_remaining) {
                t_min = distance_remaining / player_delta_length;
            }

            var wall_normal_min: V3 = .zero;
            var wall_normal_max: V3 = .zero;
            var hit_entity_min_opt: ?*Entity = null;
            var hit_entity_max_opt: ?*Entity = null;

            const desired_position = entity.p.add(player_delta);

            for (this.entities) |*test_entity| {
                const overlap_epsilon: V3 = .scalar(0.001);

                if ((test_entity.flags.traversable and EntitiesOverlapEpsilon(entity, test_entity, overlap_epsilon)) or
                    canCollide(game_state, entity, test_entity))
                {
                    for (entity.collision.volumes) |*volume| {
                        for (test_entity.collision.volumes) |*test_volume| {
                            const minkowski_diameter = test_volume.dim.add(volume.dim);

                            const min_corner: V3 = minkowski_diameter.mul(-0.5);
                            const max_corner: V3 = minkowski_diameter.mul(0.5);

                            const volume_p = entity.p.add(volume.offset);
                            const test_p = test_entity.p.add(test_volume.offset);
                            const rel = volume_p.sub(test_p);

                            const walls = [_]TestWall{
                                .init(min_corner.x, rel.x, rel.y, player_delta.x, player_delta.y, min_corner.y, max_corner.y, v3(-1, 0, 0)),
                                .init(max_corner.x, rel.x, rel.y, player_delta.x, player_delta.y, min_corner.y, max_corner.y, v3(1, 0, 0)),
                                .init(min_corner.y, rel.y, rel.x, player_delta.y, player_delta.x, min_corner.x, max_corner.x, v3(0, -1, 0)),
                                .init(max_corner.y, rel.y, rel.x, player_delta.y, player_delta.x, min_corner.x, max_corner.x, v3(0, 1, 0)),
                            };

                            const t_epsilon: f32 = 0.001;

                            if (rel.z >= min_corner.z and rel.z < max_corner.z) {
                                if (test_entity.flags.traversable) {
                                    var test_wall_normal: V3 = .zero;

                                    var t_max_test: f32 = t_max;
                                    var hit_this = false;

                                    for (&walls) |*wall| {
                                        if (wall.delta_x != 0) {
                                            const t_result = (wall.x - wall.rel_x) / wall.delta_x;

                                            if (t_result >= 0 and t_max_test < t_result) {
                                                const y = wall.rel_y + (t_result * wall.delta_y);
                                                if (y >= wall.min_y and y <= wall.max_y) {
                                                    t_max_test = @max(0, t_result - t_epsilon);
                                                    test_wall_normal = wall.normal;
                                                    hit_this = true;
                                                }
                                            }
                                        }
                                    }

                                    if (hit_this) {
                                        t_max = t_max_test;
                                        wall_normal_max = test_wall_normal;
                                        hit_entity_max_opt = test_entity;
                                    }
                                } else {
                                    var t_min_test: f32 = t_min;
                                    var hit_this = false;
                                    var test_wall_normal: V3 = .zero;

                                    for (&walls) |*wall| {
                                        if (wall.delta_x != 0) {
                                            const t_result = (wall.x - wall.rel_x) / wall.delta_x;

                                            if (t_result >= 0 and t_min_test > t_result) {
                                                const y = wall.rel_y + (t_result * wall.delta_y);
                                                if (y >= wall.min_y and y <= wall.max_y) {
                                                    t_min_test = @max(0, t_result - t_epsilon);
                                                    test_wall_normal = wall.normal;
                                                    hit_this = true;
                                                }
                                            }
                                        }
                                    }

                                    if (hit_this) {
                                        const spec_test_p = entity.p.add(player_delta.mul(t_min_test));
                                        if (speculativeCollide(entity, test_entity, spec_test_p)) {
                                            t_min = t_min_test;
                                            wall_normal_min = test_wall_normal;
                                            hit_entity_min_opt = test_entity;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            var t_stop: f32 = undefined;
            var hit_entity_opt: ?*Entity = null;
            var wall_normal: V3 = .zero;

            if (t_min < t_max) {
                t_stop = t_min;
                hit_entity_opt = hit_entity_min_opt;
                wall_normal = wall_normal_min;
            } else {
                t_stop = t_max;
                hit_entity_opt = hit_entity_max_opt;
                wall_normal = wall_normal_max;
            }

            entity.p = entity.p.add(player_delta.mul(t_stop));

            distance_remaining -= t_stop * player_delta_length;

            if (hit_entity_opt) |hit_entity| {
                player_delta = desired_position.sub(entity.p);

                const stops_on_collision = handleCollision(game_state, entity, hit_entity);

                if (stops_on_collision) {
                    player_delta = player_delta.sub(wall_normal.mul(player_delta.inner(wall_normal)));
                    entity.dp = entity.dp.sub(wall_normal.mul(entity.dp.inner(wall_normal)));
                }
            } else {
                break;
            }
        } else {
            break;
        }
    }

    var ground: f32 = 0;
    {
        for (this.entities) |*test_entity| {
            if (canOverlap(game_state, entity, test_entity) and EntitiesOverlap(entity, test_entity)) {
                handleOverlap(game_state, entity, test_entity, dt, &ground);
            }
        }
    }

    ground += entity.p.z - entity.getGroundPoint().z;

    if (entity.p.z <= ground or
        (entity.flags.z_supported and
            entity.dp.z == 0))
    {
        entity.p.z = ground;
        entity.dp.z = 0;
        entity.flags.z_supported = true;
    } else {
        entity.flags.z_supported = false;
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

fn testWall(
    wall_x: f32,
    test_x: f32,
    test_y: f32,
    delta_x: f32,
    delta_y: f32,
    t_min: *f32,
    wall_min_y: f32,
    wall_max_y: f32,
) bool {
    var hit = false;

    if (delta_x != 0) {
        const t_result = (wall_x - test_x) / delta_x;

        if (t_result >= 0 and t_min.* > t_result) {
            const y = test_y + (t_result * delta_y);
            if (y >= wall_min_y and y <= wall_max_y) {
                const t_epsilon: f32 = 0.0001;
                t_min.* = @max(0, t_result - t_epsilon);
                hit = true;
            }
        }
    }

    return hit;
}
