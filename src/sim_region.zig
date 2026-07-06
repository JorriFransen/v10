const std = @import("std");
const assert = std.debug.assert;

const MemoryArena = @import("arena.zig");

const v10 = @import("v10.zig");
const StoredEntity = v10.LowEntity;

const World = @import("world.zig");

const math = @import("math");
const V2 = math.V2;
const v2 = V2.init;
const Rect = math.Rect;

game_state: *v10.GameState,
origin: World.Position,
bounds: Rect,
entity_count: u32,
entities: []SimEntity,

const SimRegion = @This();

pub const SimEntity = struct {
    storage_index: v10.EntityIndex = 0,

    p: V2 = .zero,
    chunk_z: i32 = 0,

    z: f32 = 0,
    d_z: f32 = 0,
};

pub fn begin(sim_arena: *MemoryArena, game_state: *v10.GameState, region_origin: World.Position, region_bounds: Rect) *SimRegion {
    const world = game_state.world;

    const sim_region = sim_arena.pushMemory(SimRegion);
    sim_region.* = .{
        .game_state = game_state,
        .origin = region_origin,
        .bounds = region_bounds,
        .entity_count = 0,
        .entities = sim_arena.pushArray(4096, SimEntity),
    };

    const min_chunk_p = region_origin.offset(world, region_bounds.min);
    const max_chunk_p = region_origin.offset(world, region_bounds.max);

    var chunk_y: i32 = min_chunk_p.chunk_y;
    while (chunk_y <= max_chunk_p.chunk_y) : (chunk_y += 1) {
        var chunk_x: i32 = min_chunk_p.chunk_x;
        while (chunk_x <= max_chunk_p.chunk_x) : (chunk_x += 1) {
            if (world.getChunk(chunk_x, chunk_y, region_origin.chunk_z, .{})) |chunk| {
                var block_opt: ?*World.EntityBlock = &chunk.first_entity_block;

                while (block_opt) |block| : (block_opt = block.next) {
                    for (block.entity_indices[0..block.entity_count]) |low_index| {
                        const low = &game_state.low_entities[low_index];

                        const sim_space_p = sim_region.getSimSpaceP(low);
                        if (region_bounds.containsPoint(sim_space_p)) {
                            _ = addEntity(sim_region, low, sim_space_p);
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

        const new_p = this.origin.offset(world, entity.p);
        world.changeEntityLocation(&this.game_state.world_arena, entity.storage_index, stored, stored.p, new_p);

        if (v10.forceEntityIntoHigh(this.game_state, this.game_state.camera_following_entity_index)) |cam_following_entity| {
            const entity_p = cam_following_entity.high.p;

            var new_cam_p = this.game_state.camera_pos;
            new_cam_p.chunk_z = cam_following_entity.low.p.chunk_z;

            if (false) {
                const x_bound_offset: i32 = @round(@as(f32, v10.GameState.screen_tile_width) / 2);
                if (entity_p.x > (x_bound_offset) * world.tile_side_in_meters) {
                    new_cam_p.abs_tile_x += v10.GameState.screen_tile_width;
                } else if (entity_p.x < -(x_bound_offset) * world.tile_side_in_meters) {
                    new_cam_p.abs_tile_x -= v10.GameState.screen_tile_width;
                }

                const y_bound_offset: i32 = @round(@as(f32, v10.GameState.screen_tile_height) / 2);
                if (entity_p.y > (y_bound_offset) * world.tile_side_in_meters) {
                    new_cam_p.abs_tile_y += v10.GameState.screen_tile_height;
                } else if (entity_p.y < -(y_bound_offset) * world.tile_side_in_meters) {
                    new_cam_p.abs_tile_y -= v10.GameState.screen_tile_height;
                }
            } else {
                new_cam_p = cam_following_entity.low.p;
            }

            // setCamera(game_state, new_cam_p);
        }
    }
}

fn addEntityRaw(this: *SimRegion) ?*SimEntity {
    var entity: ?*SimEntity = null;

    if (this.entity_count < this.entities.len) {
        entity = &this.entities[this.entity_count];
        this.entity_count += 1;

        entity.?.* = .{};
    } else {
        // Out of entities
        unreachable;
    }

    return entity;
}

fn addEntity(this: *SimRegion, source: *StoredEntity, sim_p_opt: ?V2) ?*SimEntity {
    var entity: ?*SimEntity = null;

    if (this.addEntityRaw()) |dest| {
        entity = dest;
        if (sim_p_opt) |sim_p| {
            dest.p = sim_p;
        } else {
            dest.p = this.getSimSpaceP(source);
        }
    }

    return entity;
}

inline fn getSimSpaceP(this: *SimRegion, stored: *StoredEntity) V2 {
    const diff = this.world.subtract(stored.p, this.origin);
    const result = diff.xy;
    return result;
}
