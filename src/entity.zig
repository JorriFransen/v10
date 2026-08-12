const std = @import("std");
const assert = std.debug.assert;

const core = @import("core");
const math = core.math;
const V2 = math.V2;
const V3 = math.V3;
const v3 = V3.init;
const Rect = math.Rect;
const Rect3 = math.Rect3;

const v10 = @import("v10.zig");
const GameState = v10.GameState;

const Entity = @This();

storage_index: Index = 0,
updatable: bool = false,

type: Type = .null,
flags: EntityFlags = .{},

p: V3 = .zero,
dp: V3 = .zero,

collision: *CollisionGroup = undefined,

distance_limit: f32 = 0,

facing_direction: FacingDirection = .down,

t_bob: f32 = 0,

d_abs_tile_z: i32 = 0,

hitpoint_max: u32 = 0,
hitpoints: [16]HitPoint = @splat(.{}),

sword: Reference = .{ .index = 0 },

// stairs
walkable_dim: V2 = .zero,
walkable_height: f32 = 0,

pub const invalid_p: V3 = .{ .x = 100000, .y = 100000, .z = 100000 };

pub const Index = u32;

pub const Type = enum {
    null,

    space,
    hero,
    wall,
    familiar,
    monster,
    sword,
    stairwell,
};

pub const EntityFlags = packed struct(u32) {
    collides: bool = false,
    non_spatial: bool = false,
    moveable: bool = false,
    z_supported: bool = false,
    traversable: bool = false,

    __reserved_0: u25 = 0,

    in_sim: bool = false,

    __reserved_1: u1 = 0,
};

pub const Reference = union {
    ptr: ?*Entity,
    index: Index,
};

pub const CollisionVolume = struct {
    offset: V3,
    dim: V3,
};

pub const CollisionGroup = struct {
    total_volume: CollisionVolume,
    volumes: []CollisionVolume,

    pub fn @"null"(game_state: *GameState) *CollisionGroup {
        const group = game_state.world_arena.push(CollisionGroup);

        group.volumes = &.{};
        group.total_volume = .{ .offset = .zero, .dim = .zero };

        return group;
    }

    pub fn simpleGrounded(game_state: *GameState, x: f32, y: f32, z: f32) *CollisionGroup {
        const group = game_state.world_arena.push(CollisionGroup);

        const volume_count = 1;
        group.volumes = game_state.world_arena.pushArray(volume_count, CollisionVolume);
        group.total_volume = .{
            .offset = v3(0, 0, 0.5 * z),
            .dim = v3(x, y, z),
        };
        group.volumes[0] = group.total_volume;

        return group;
    }
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

pub fn getGroundPoint(entity: *const Entity) V3 {
    const result = getGroundPointForP(entity, entity.p);
    return result;
}

pub fn getGroundPointForP(entity: *const Entity, p: V3) V3 {
    _ = entity;

    const result = p;
    return result;
}

pub fn getStairGround(entity: *const Entity, at_ground_point: V3) f32 {
    assert(entity.type == .stairwell);

    const region_rect = Rect.centerDim(entity.p.xy(), entity.walkable_dim);
    const bary = region_rect.barycentric(at_ground_point.xy()).clamp01();

    const ground = entity.p.z + bary.y * entity.walkable_height;
    return ground;
}
