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
