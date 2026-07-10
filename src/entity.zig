const std = @import("std");
const assert = std.debug.assert;

const math = @import("math");
const V3 = math.V3;

const SimRegion = @import("sim_region.zig");
pub const Entity = SimRegion.Entity;
const EntityIndex = SimRegion.EntityIndex;
const MoveSpec = SimRegion.MoveSpec;

pub const invalid_p: V3 = .{ .x = 100000, .y = 100000, .z = 100000 };
