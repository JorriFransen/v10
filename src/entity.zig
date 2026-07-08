const std = @import("std");
const assert = std.debug.assert;

const math = @import("math");
const V2 = math.V2;
const v2 = V2.init;

const SimRegion = @import("sim_region.zig");
pub const Entity = SimRegion.Entity;
const EntityIndex = SimRegion.EntityIndex;
const MoveSpec = SimRegion.MoveSpec;

pub const invalid_p: V2 = .{ .x = 100000, .y = 100000 };

pub fn updateFamiliar(sim_region: *SimRegion, entity: *Entity, dt: f32) void {
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

    var ddp = V2.zero;
    if (closest_hero_opt) |hero| {
        if (closest_hero_d_sq >= math.square(3)) {
            const acceleration = 0.5;
            const one_over_length = acceleration / math.sqrt(closest_hero_d_sq);
            ddp = hero.p.sub(entity.p).mul(one_over_length);
        }
    }

    const move_spec = MoveSpec{ .unit_max_ddp = false, .speed = 50, .drag = 8 };
    sim_region.moveEntity(entity, dt, move_spec, ddp);
}

pub fn updateMonster(sim_region: *SimRegion, entity: *Entity, dt: f32) void {
    _ = sim_region;
    _ = entity;
    _ = dt;
}

pub fn updateSword(sim_region: *SimRegion, entity: *Entity, dt: f32) void {
    if (entity.flags.non_spatial) {
        //
    } else {
        const move_spec = MoveSpec{ .speed = 0 };

        const old_p = entity.p;
        sim_region.moveEntity(entity, dt, move_spec, V2.zero);
        const distance_traveled = entity.p.sub(old_p).length();

        entity.distance_remaining -= distance_traveled;
        if (entity.distance_remaining < 0) {
            makeEntityNonSpatial(entity);
        }
    }
}

pub inline fn makeEntitySpatial(entity: *Entity, p: V2, d_p: V2) void {
    entity.flags.non_spatial = false;
    entity.p = p;
    entity.d_p = d_p;
}

pub inline fn makeEntityNonSpatial(entity: *Entity) void {
    entity.flags.non_spatial = true;
    entity.p = invalid_p;
}
