const std = @import("std");
const assert = std.debug.assert;

const math = @import("math");
const V3 = math.V3;
const v3 = V3.init;
const Rect3 = math.Rect3;

const SimRegion = @import("sim_region.zig");
pub const Entity = SimRegion.Entity;
const EntityIndex = SimRegion.EntityIndex;
const MoveSpec = SimRegion.MoveSpec;

pub const invalid_p: V3 = .{ .x = 100000, .y = 100000, .z = 100000 };

pub fn getEntityGroundPoint(entity: *const Entity) V3 {
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
