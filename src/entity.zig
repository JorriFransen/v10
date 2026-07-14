const std = @import("std");
const assert = std.debug.assert;

const math = @import("math");
const V3 = math.V3;
const v3 = V3.init;
const Rect3 = math.Rect3;

const Entity = @This();

storage_index: Index = 0,
updatable: bool = false,

type: Type = .null,
flags: EntityFlags = .{},

p: V3 = .zero,
dp: V3 = .zero,

dim: V3 = .zero,

distance_limit: f32 = 0,

facing_direction: FacingDirection = .down,

t_bob: f32 = 0,

d_abs_tile_z: i32 = 0,

hitpoint_max: u32 = 0,
hitpoints: [16]HitPoint = @splat(.{}),

sword: Reference = .{ .index = 0 },

// stairs
walkable_height: f32 = 0,

pub const invalid_p: V3 = .{ .x = 100000, .y = 100000, .z = 100000 };

pub const Index = u32;

pub const Type = enum {
    null,
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

    __reserved_0: u26 = 0,

    in_sim: bool = false,

    __reserved_1: u1 = 0,
};

pub const Reference = union {
    ptr: ?*Entity,
    index: Index,
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
    const result = entity.p.add(v3(0, 0, -0.5 * entity.dim.z));
    return result;
}

pub fn getStairGround(entity: *const Entity, at_ground_point: V3) f32 {
    assert(entity.type == .stairwell);

    const region_rect = Rect3.centerDim(entity.p, entity.dim);
    const bary = region_rect.barycentric(at_ground_point).clamp01();

    const ground = region_rect.min.z + bary.y * entity.walkable_height;
    return ground;
}
