const std = @import("std");
const log = std.log.scoped(.v10);
const options = @import("options");
const platform = @import("v10_platform.zig");
const intrinsics = @import("intrinsics.zig");

const math = @import("math");
const V2 = math.V2;
const v2 = V2.init;
const v2i = V2.initSigned;
const v2u = V2.initUnsigned;
const V4 = math.V4;
const v4 = V4.init;
const Rect = math.Rect;

const assert = std.debug.assert;

const Random = @import("random.zig");
const MemoryArena = @import("arena.zig");
const World = @import("world.zig");

const ThreadContext = platform.ThreadContext;
const Memory = platform.Memory;
const Input = platform.Input;
const OffscreenBuffer = platform.OffscreenBuffer;
const AudioBuffer = platform.AudioBuffer;

const os = @import("builtin").os.tag;

const screen_tile_width: i32 = 17;
const screen_tile_height: i32 = 9;

pub const EntityIndex = u32;

pub const Entity = struct {
    low_index: EntityIndex,
    high: *HighEntity = undefined,
    low: *LowEntity = undefined,
};

pub const HighEntity = struct {
    p: V2 = .zero,
    d_p: V2 = .zero,
    chunk_z: i32 = 0,
    facing_direction: FacingDirection = .down,

    t_bob: f32 = 0,

    boost: bool = false,
    z: f32 = 0,
    d_z: f32 = 0,

    low_entity_index: EntityIndex = 0,
};

pub const EntityType = enum {
    null,
    hero,
    wall,
    familiar,
    monster,
};

pub const HitPoint = struct {
    pub const max_amount = 4;

    flags: u8 = 0,
    amount: u8 = 0,
};

pub const LowEntity = struct {
    type: EntityType = .null,

    p: World.Position = std.mem.zeroInit(World.Position, .{}),
    size: V2 = .zero,

    // for "stairs"
    collides: bool = false,
    d_abs_tile_z: i32 = 0,

    high_entity_index: EntityIndex = 0,

    hitpoint_max: u32 = 0,
    hitpoints: [16]HitPoint = @splat(.{}),
};

const FacingDirection = enum(u2) {
    right,
    up,
    left,
    down,
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

pub const GameState = struct {
    world_arena: MemoryArena = undefined,
    world: *World = undefined,

    meters_to_pixels: f32 = 0,

    camera_following_entity_index: EntityIndex = 0,
    camera_pos: World.Position = undefined,

    player_index_for_controller: [@typeInfo(@FieldType(Input, "controllers")).array.len]EntityIndex = @splat(0),

    low_entity_count: u32 = 0,
    low_entities: [100_000]LowEntity = @splat(.{}),

    high_entity_count: u32 = 0,
    high_entities: [256]HighEntity = @splat(.{}),

    backdrop: LoadedBitmap = .{},
    hero_shadow: LoadedBitmap = .{},
    hero_bitmaps: [4]HeroBitmaps = std.mem.zeroes([4]HeroBitmaps),

    tree: LoadedBitmap = .{},

    pub const AddLowEntityResult = struct {
        low: *LowEntity,
        low_index: EntityIndex,
    };

    pub fn addLowEntity(this: *GameState, entity_type: EntityType, pos_opt: ?World.Position) AddLowEntityResult {
        assert(this.low_entity_count < this.low_entities.len);

        const low_index = this.low_entity_count;
        this.low_entity_count += 1;

        const low = &this.low_entities[low_index];
        low.* = .{};
        low.type = entity_type;

        if (pos_opt) |p| {
            low.p = p;
            this.world.changeEntityLocation(&this.world_arena, low_index, null, p);
        }

        const result = AddLowEntityResult{
            .low = low,
            .low_index = low_index,
        };

        return result;
    }

    pub inline fn getLowEntity(this: *GameState, index: EntityIndex) ?*LowEntity {
        const result: ?*LowEntity = if (index > 0 and index < this.low_entities.len)
            &this.low_entities[index]
        else
            null;

        return result;
    }

    pub inline fn forceEntityIntoHigh(this: *GameState, low_index: EntityIndex) ?Entity {
        var result: ?Entity = null;

        if (low_index > 0 and low_index < this.low_entity_count) {
            result = .{
                .low_index = low_index,
                .high = this.makeEntityHighFrequency(low_index).?,
                .low = &this.low_entities[low_index],
            };
        }

        return result;
    }

    pub inline fn entityFromHighIndex(this: *GameState, high_index: EntityIndex) Entity {
        var result = Entity{ .low_index = 0 };

        if (high_index != 0) {
            assert(high_index < this.high_entity_count);

            const high = &this.high_entities[high_index];
            assert(high.low_entity_index != 0);
            assert(high.low_entity_index < this.low_entity_count);

            const low = &this.low_entities[high.low_entity_index];

            result = Entity{
                .low_index = high.low_entity_index,
                .high = high,
                .low = low,
            };
        }

        return result;
    }

    pub inline fn getCameraSpaceP(this: *GameState, low: *LowEntity) V2 {
        const diff = this.world.subtract(low.p, this.camera_pos);
        return diff.xy;
    }

    pub inline fn makeEntityHighFrequencyCamspace(this: *GameState, low: *LowEntity, low_index: EntityIndex, cam_space_p: V2) ?*HighEntity {
        assert(low_index < this.low_entities.len);

        var result: ?*HighEntity = null;

        assert(low.high_entity_index == 0);

        if (this.high_entity_count < this.high_entities.len) {
            const high_index = this.high_entity_count;
            this.high_entity_count += 1;
            const high = &this.high_entities[high_index];

            high.p = cam_space_p;
            high.d_p = V2.zero;
            high.chunk_z = low.p.chunk_z;
            high.facing_direction = .down;
            high.low_entity_index = low_index;

            low.high_entity_index = high_index;

            result = high;
        } else {
            // Out of high entities
            unreachable;
        }

        return result;
    }

    pub inline fn makeEntityHighFrequency(this: *GameState, low_index: EntityIndex) ?*HighEntity {
        assert(low_index < this.low_entities.len);

        var result: ?*HighEntity = null;

        const low = &this.low_entities[low_index];
        if (low.high_entity_index != 0) {
            result = &this.high_entities[low.high_entity_index];
        } else {
            const cam_space_p = this.getCameraSpaceP(low);
            result = this.makeEntityHighFrequencyCamspace(low, low_index, cam_space_p);
        }

        return result;
    }

    pub inline fn makeEntityLowFrequency(this: *GameState, low_index: EntityIndex) void {
        assert(low_index < this.low_entities.len);

        const low = &this.low_entities[low_index];
        const high_index = low.high_entity_index;

        if (high_index != 0) {
            const last_high_index = this.high_entity_count - 1;

            if (high_index != last_high_index) {
                const last_entity = &this.high_entities[last_high_index];
                const del_entity = &this.high_entities[high_index];
                del_entity.* = last_entity.*;
                this.low_entities[last_entity.low_entity_index].high_entity_index = high_index;
            }

            this.high_entity_count -= 1;
            low.high_entity_index = 0;
        }
    }

    pub inline fn validateEntityPairs(this: *GameState) bool {
        var valid = true;

        for (this.high_entities[0..this.high_entity_count], 0..) |*high, i| {
            valid = valid and this.low_entities[high.low_entity_index].high_entity_index == i;
        }

        return valid;
    }

    pub inline fn offsetAndCheckFrequencyByArea(this: *GameState, offset: V2, camera_bounds: Rect) void {
        var high_index: u32 = 1;
        while (high_index < this.high_entity_count) {
            const high = &this.high_entities[high_index];

            high.p = high.p.add(offset);

            if (camera_bounds.containsPoint(high.p)) {
                high_index += 1;
            } else {
                this.makeEntityLowFrequency(high.low_entity_index);
            }
        }
    }

    pub fn setCamera(this: *GameState, new_pos: World.Position) void {
        const world = this.world;

        assert(this.validateEntityPairs());

        const diff_cam_p = world.subtract(new_pos, this.camera_pos);
        this.camera_pos = new_pos;

        const tile_span_x = screen_tile_width * 3;
        const tile_span_y = screen_tile_height * 3;
        const bound_dim = v2(tile_span_x, tile_span_y).mul(world.tile_side_in_meters);
        const camera_in_bounds: Rect = .centerDim(V2.zero, bound_dim);

        const entity_offset_for_frame: V2 = diff_cam_p.xy.mul(-1);
        this.offsetAndCheckFrequencyByArea(entity_offset_for_frame, camera_in_bounds);

        assert(this.validateEntityPairs());

        const min_chunk_p = new_pos.offset(world, camera_in_bounds.min);
        const max_chunk_p = new_pos.offset(world, camera_in_bounds.max);

        var chunk_y: i32 = min_chunk_p.chunk_y;
        while (chunk_y <= max_chunk_p.chunk_y) : (chunk_y += 1) {
            var chunk_x: i32 = min_chunk_p.chunk_x;
            while (chunk_x <= max_chunk_p.chunk_x) : (chunk_x += 1) {
                if (world.getChunk(chunk_x, chunk_y, new_pos.chunk_z, .{})) |chunk| {
                    var block_opt: ?*World.EntityBlock = &chunk.first_entity_block;

                    while (block_opt) |block| : (block_opt = block.next) {
                        for (block.entity_indices[0..block.entity_count]) |low_index| {
                            const low = &this.low_entities[low_index];

                            if (low.high_entity_index == 0) {
                                const cam_space_p = this.getCameraSpaceP(low);

                                if (camera_in_bounds.containsPoint(cam_space_p)) {
                                    _ = this.makeEntityHighFrequencyCamspace(low, low_index, cam_space_p);
                                }
                            }
                        }
                    }
                }
            }
        }

        assert(this.validateEntityPairs());
    }

    fn moveEntity(this: *GameState, entity: Entity, dt: f32, direction: V2) void {
        const world = this.world;

        const ddp_length_sq = direction.lengthSquared();
        var ddp = if (ddp_length_sq > 1)
            direction.mul(1 / @sqrt(ddp_length_sq))
        else
            direction;

        var speed: f32 = 50; // ms/s^2
        if (entity.high.boost) speed *= 5;
        ddp = ddp.mul(speed);
        ddp = ddp.add(entity.high.d_p.mul(-8));

        var player_delta = V2.add(
            ddp.mul(0.5 * math.square(dt)),
            entity.high.d_p.mul(dt),
        );
        entity.high.d_p = entity.high.d_p.add(ddp.mul(dt));

        var it_count: usize = 0;
        while (it_count < 4) : (it_count += 1) {
            var t_min: f32 = 1;
            var wall_normal: V2 = .zero;
            var hit_high_index: usize = 0;

            const desired_position = entity.high.p.add(player_delta);

            for (1..this.high_entity_count) |test_high_index| {
                if (test_high_index != entity.low.high_entity_index) {
                    const high = &this.high_entities[test_high_index];
                    const test_entity = Entity{
                        .high = high,
                        .low = &this.low_entities[high.low_entity_index],
                        .low_index = high.low_entity_index,
                    };

                    if (test_entity.low.collides) {
                        const diameter = test_entity.low.size.add(entity.low.size);
                        const min_corner = diameter.mul(-0.5);
                        const max_corner = diameter.mul(0.5);

                        const rel = entity.high.p.sub(test_entity.high.p);

                        if (testWall(min_corner.x, rel.x, rel.y, player_delta.x, player_delta.y, &t_min, min_corner.y, max_corner.y)) {
                            wall_normal = v2(-1, 0);
                            hit_high_index = test_high_index;
                        }
                        if (testWall(max_corner.x, rel.x, rel.y, player_delta.x, player_delta.y, &t_min, min_corner.y, max_corner.y)) {
                            wall_normal = v2(1, 0);
                            hit_high_index = test_high_index;
                        }
                        if (testWall(min_corner.y, rel.y, rel.x, player_delta.y, player_delta.x, &t_min, min_corner.x, max_corner.x)) {
                            wall_normal = v2(0, -1);
                            hit_high_index = test_high_index;
                        }
                        if (testWall(max_corner.y, rel.y, rel.x, player_delta.y, player_delta.x, &t_min, min_corner.x, max_corner.x)) {
                            wall_normal = v2(0, 1);
                            hit_high_index = test_high_index;
                        }
                    }
                }
            }
            if (test_wall_hh) {

                // Current hh version, gets stuck on edges perpendicular to the one the player is sliding along.
                entity.high.p = entity.high.p.add(player_delta.mul(t_min));
            } else {
                const push_out: f32 = 0.0001;
                const delta = player_delta.mul(t_min).add(wall_normal.mul(push_out));
                entity.high.p = entity.high.p.add(delta);
            }

            if (hit_high_index != 0) {
                entity.high.d_p = entity.high.d_p.sub(wall_normal.mul(entity.high.d_p.inner(wall_normal)));
                player_delta = desired_position.sub(entity.high.p);
                player_delta = player_delta.sub(wall_normal.mul(player_delta.inner(wall_normal)));

                // const hit_high = &game_state.high_entities[hit_high_index];
                // const hit_low = &game_state.low_entities[hit_high.low_entity_index];
                // entity.high.abs_tile_z = @intCast(@as(i64, entity.high.abs_tile_z) + hit_low.d_abs_tile_z);
            } else {
                break;
            }
        }

        entity.high.facing_direction =
            if (entity.high.d_p.x == 0 and entity.high.d_p.y == 0)
                entity.high.facing_direction
            else if (@abs(entity.high.d_p.x) > @abs(entity.high.d_p.y))
                if (entity.high.d_p.x > 0) .right else .left
            else if (entity.high.d_p.y > 0) .up else .down;

        const new_p = this.camera_pos.offset(world, entity.high.p);
        world.changeEntityLocation(&this.world_arena, entity.low_index, entity.low.p, new_p);
        entity.low.p = new_p;
    }

    const test_wall_hh = false;
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

    pub fn updateFamiliar(this: *GameState, entity: Entity, dt: f32) void {
        var closest_hero_opt: ?Entity = null;
        var closest_hero_d_sq: f32 = math.square(10);

        for (1..this.high_entity_count) |high_index_| {
            const high_index: EntityIndex = @intCast(high_index_);

            const test_entity = this.entityFromHighIndex(high_index);
            if (test_entity.low.type == .hero and closest_hero_d_sq > 0) {
                const test_d_sq = test_entity.high.p.sub(entity.high.p).lengthSquared();
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
                ddp = hero.high.p.sub(entity.high.p).mul(one_over_length);
            }
        }
        this.moveEntity(entity, dt, ddp);
    }

    pub fn updateMonster(this: *GameState, entity: Entity, dt: f32) void {
        _ = this;
        _ = entity;
        _ = dt;
    }

    pub fn addWall(this: *GameState, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
        const p = this.world.chunkPositionFromTilePosition(abs_tile_x, abs_tile_y, abs_tile_z);
        const entity = this.addLowEntity(.wall, p);

        entity.low.size = V2.scalar(this.world.tile_side_in_meters);
        entity.low.collides = true;

        return entity;
    }

    pub fn addPlayer(this: *GameState) AddLowEntityResult {
        const entity = this.addLowEntity(.hero, this.camera_pos);

        entity.low.hitpoint_max = 3;
        @memset(
            entity.low.hitpoints[0..entity.low.hitpoint_max],
            .{ .amount = HitPoint.max_amount },
        );
        entity.low.size = v2(1, 0.5);
        entity.low.collides = true;

        if (this.camera_following_entity_index == 0) {
            this.camera_following_entity_index = entity.low_index;
        }

        return entity;
    }

    pub fn addMonster(this: *GameState, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
        const p = this.world.chunkPositionFromTilePosition(abs_tile_x, abs_tile_y, abs_tile_z);
        const entity = this.addLowEntity(.monster, p);

        entity.low.size = v2(1, 0.5);
        entity.low.collides = true;

        return entity;
    }

    pub fn addFamiliar(this: *GameState, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) AddLowEntityResult {
        const p = this.world.chunkPositionFromTilePosition(abs_tile_x, abs_tile_y, abs_tile_z);
        const entity = this.addLowEntity(.familiar, p);

        entity.low.size = v2(1, 0.5);
        entity.low.collides = false;

        return entity;
    }
};

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
            .a = 255,
        };
    }
};

pub fn drawRectangle(buffer: *OffscreenBuffer, min: V2, max: V2, r: f32, g: f32, b: f32) void {
    const pitch: usize = @intCast(buffer.pitch);
    const bpp: usize = @intCast(buffer.bytes_per_pixel);

    const buffer_width_f: f32 = @floatFromInt(buffer.width);
    const buffer_height_f: f32 = @floatFromInt(buffer.height);

    const minx: usize = @round(@min(@max(min.x, 0), buffer_width_f));
    const miny: usize = @round(@min(@max(min.y, 0), buffer_height_f));
    const maxx: usize = @round(@min(@max(max.x, 0), buffer_width_f));
    const maxy: usize = @round(@min(@max(max.y, 0), buffer_height_f));

    assert(bpp == @sizeOf(u32));

    const color = ColorU8ARGB.fromF32RGB(r, g, b);

    var row: [*]u8 = buffer.memory + (minx * bpp) + (miny * pitch);
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

pub fn drawBitmap(buffer: *OffscreenBuffer, bitmap: *const LoadedBitmap, px: f32, py: f32, c_alpha: f32) void {
    const pitch: usize = @intCast(buffer.pitch);
    const bpp: usize = @intCast(buffer.bytes_per_pixel);

    const real_x: f32 = px;
    const real_y: f32 = py;

    var min_x: i32 = @round(real_x);
    var min_y: i32 = @round(real_y);
    var max_x: i32 = min_x + @as(i32, @intCast(bitmap.width));
    var max_y: i32 = min_y + @as(i32, @intCast(bitmap.height));

    var source_offset_x: u32 = 0;
    if (min_x < 0) {
        source_offset_x = @intCast(-min_x);
        min_x = 0;
    }

    var source_offset_y: u32 = 0;
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

    const minx: u32 = @intCast(min_x);
    const miny: u32 = @intCast(min_y);
    const maxx: u32 = @intCast(@max(0, max_x));
    const maxy: u32 = @intCast(@max(0, max_y));

    // TEMPORARY
    if (bitmap.pixels.len == 0) return;
    // TEMPORARY

    var source_row: [*]align(1) u32 = bitmap.pixels.ptr + (bitmap.width * (bitmap.height - 1)) + source_offset_x - (bitmap.width * source_offset_y);
    var dest_row: [*]u8 = buffer.memory + (minx * bpp) + (miny * pitch);

    var y: usize = @intCast(miny);
    while (y < maxy) : (y += 1) {
        var source: [*]align(1) u32 = source_row;
        var dest: [*]u32 = @ptrCast(@alignCast(dest_row));

        var x: usize = @intCast(minx);
        while (x < maxx) : (x += 1) {
            const sc = ColorU8ARGB.fromU32(source[0]);
            const dc = ColorU8ARGB.fromU32(dest[0]);

            const a: f32 = (@as(f32, @floatFromInt(sc.a)) / 255 * c_alpha);

            const sr: f32 = sc.r;
            const sg: f32 = sc.g;
            const sb: f32 = sc.b;

            const dr: f32 = dc.r;
            const dg: f32 = dc.g;
            const db: f32 = dc.b;

            const r: f32 = (1 - a) * dr + a * sr;
            const g: f32 = (1 - a) * dg + a * sg;
            const b: f32 = (1 - a) * db + a * sb;

            dest[0] = (ColorU8ARGB{
                .r = @intFromFloat(r + 0.5),
                .g = @intFromFloat(g + 0.5),
                .b = @intFromFloat(b + 0.5),
                .a = 255,
            }).asU32();

            source += 1;
            dest += 1;
        }

        dest_row += @intCast(buffer.pitch);
        source_row -= bitmap.width;
    }
}

pub const LoadedBitmap = struct {
    width: u32 = 0,
    height: u32 = 0,
    pixels: []align(1) u32 = &.{},
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

    assert(buffer.frames_len >= 0);

    for (buffer.frames[0..buffer.frames_len]) |*frame| {
        // const sine_value: f32 = intrinsics.sin(game_state.t_sine);
        // const sample_value: i16 = @intFromFloat(@as(f32, @floatFromInt(tone_volume)) * sine_value);
        // sample_value = 0;
        const sample_value: i16 = 0;

        frame.* = .{ .left = sample_value, .right = sample_value };

        // game_state.t_sine += math.tau / wave_period;
        // if (game_state.t_sine > math.tau) game_state.t_sine -= math.tau;
    }
}

pub fn init(thread_context: *ThreadContext, game_memory: *Memory) void {
    assert(@sizeOf(GameState) <= game_memory.permanent_len);

    assert(@sizeOf(GameState) <= game_memory.transient_len);
    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent));

    game_state.* = .{};

    const game_state_size = @sizeOf(GameState);
    const world_arena_size = game_memory.permanent_len - game_state_size;

    game_state.world_arena = .init(game_memory.permanent[game_state_size .. game_state_size + world_arena_size]);

    game_state.world = game_state.world_arena.pushMemory(World);
    const world: *World = game_state.world;

    world.init(1.4);

    const tile_size_in_pixels = 60;
    game_state.meters_to_pixels = tile_size_in_pixels / world.tile_side_in_meters;

    _ = game_state.addLowEntity(.null, null);
    game_state.high_entity_count = 1;

    const asset_prefix = "../../hh_assets/";
    // const asset_prefix = "";

    game_state.backdrop = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_background.bmp");
    game_state.hero_shadow = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test/test_hero_shadow.bmp");
    game_state.tree = DEBUG.loadBMP(&game_memory.debug, thread_context, asset_prefix ++ "test2/tree00.bmp");

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

    var next_random_number_index: usize = 0;

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
        const random_number = Random.random_number_table[next_random_number_index];
        next_random_number_index += 1;

        const random_choice =
            // if (door_up or door_down)
            random_number % 2
        // else
        //     random_number % 3
        ;

        var created_ladder = false;

        if (random_choice == 2) {
            if (abs_tile_z == screen_base_z) {
                door_up = true;
                created_ladder = true;
            } else {
                door_down = true;
                created_ladder = true;
            }
        } else if (random_choice == 1) {
            door_right = true;
        } else {
            door_top = true;
        }

        for (0..screen_tile_height) |tile_y_| {
            const tile_y: i32 = @intCast(tile_y_);

            for (0..screen_tile_width) |tile_x_| {
                const tile_x: i32 = @intCast(tile_x_);

                const abs_tile_x: i32 = (screen_x * screen_tile_width) + tile_x;
                const abs_tile_y: i32 = (screen_y * screen_tile_height) + tile_y;

                var tile_value: u32 = 1;

                if ((tile_x == 0) and
                    (!door_left or (tile_y != (screen_tile_height / 2))))
                {
                    tile_value = 2;
                } else if ((tile_x == screen_tile_width - 1) and
                    (!door_right or (tile_y != (screen_tile_height / 2))))
                {
                    tile_value = 2;
                } else if ((tile_y == 0) and
                    (!door_bottom or (tile_x != (screen_tile_width / 2))))
                {
                    tile_value = 2;
                } else if ((tile_y == screen_tile_height - 1) and
                    (!door_top or (tile_x != (screen_tile_width / 2))))
                {
                    tile_value = 2;
                }

                if (tile_x == 10 and tile_y == 6) {
                    if (door_up) {
                        tile_value = 3;
                    } else if (door_down) {
                        tile_value = 4;
                    }
                }

                _ = world.getChunk(0, 0, 0, .{});

                if (tile_value == 2) {
                    _ = game_state.addWall(abs_tile_x, abs_tile_y, abs_tile_z);
                }
            }
        }

        if (random_choice == 2) {
            if (abs_tile_z == screen_base_z) {
                abs_tile_z = screen_base_z + 1;
            } else {
                abs_tile_z = screen_base_z;
            }
        } else if (random_choice == 1) {
            screen_x += 1;
        } else {
            screen_y += 1;
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
    }

    const cam_tile_x = (screen_base_x * screen_tile_width) + (screen_tile_width / 2);
    const cam_tile_y = (screen_base_y * screen_tile_height) + (screen_tile_height / 2);
    const cam_tile_z = screen_base_z;
    const cam_pos = game_state.world.chunkPositionFromTilePosition(cam_tile_x, cam_tile_y, cam_tile_z);

    _ = game_state.addMonster(cam_tile_x + 2, cam_tile_y + 2, cam_tile_z);

    _ = game_state.addFamiliar(cam_tile_x - 2, cam_tile_y + 2, cam_tile_z);

    _ = game_state.addWall(-1, -1, 0);

    game_state.setCamera(cam_pos);
}

pub export fn updateAndRender(thread_context: *ThreadContext, game_memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer) callconv(.c) void {
    assert(@sizeOf(GameState) <= game_memory.transient_len);
    const game_state: *GameState = @ptrCast(@alignCast(game_memory.permanent));

    if (!game_memory.initialized) {
        init(thread_context, game_memory);
        game_memory.initialized = true;
    }

    const world: *World = game_state.world;

    for (input.controllers, 0..) |controller, controller_index| {
        // TODO: Is controller.connected supposed to exist?

        const buttons = &controller.buttons.named;

        const controlling_low_index = game_state.player_index_for_controller[controller_index];
        if (controlling_low_index == 0) {
            if (buttons.start.ended_down) {
                const controlling_entity = game_state.addPlayer();
                game_state.player_index_for_controller[controller_index] = controlling_entity.low_index;
            }
        } else {
            if (game_state.forceEntityIntoHigh(controlling_low_index)) |controlling_entity| {
                var move_dir: V2 = .{};

                if (controller.is_analog) {
                    // game_state.tone_hz = 400 + (50 * controller.stick_average_y);

                    move_dir.x += controller.stick_average_x;
                    move_dir.y += controller.stick_average_y;
                } else {
                    if (buttons.move_up.ended_down) {
                        move_dir.y = 1;
                    }
                    if (buttons.move_down.ended_down) {
                        move_dir.y = -1;
                    }
                    if (buttons.move_left.ended_down) {
                        move_dir.x = -1;
                    }
                    if (buttons.move_right.ended_down) {
                        move_dir.x = 1;
                    }
                }

                if (buttons.action_up.ended_down) {
                    if (controlling_entity.high.z <= 0) {
                        controlling_entity.high.d_z = 3;
                    }
                }

                controlling_entity.high.boost = buttons.action_down.ended_down;

                game_state.moveEntity(controlling_entity, input.dt, move_dir);
            }
        }
    }

    if (game_state.forceEntityIntoHigh(game_state.camera_following_entity_index)) |cam_following_entity| {
        const entity_p = cam_following_entity.high.p;

        var new_cam_p = game_state.camera_pos;
        new_cam_p.chunk_z = cam_following_entity.low.p.chunk_z;

        if (false) {
            const x_bound_offset: i32 = @round(@as(f32, screen_tile_width) / 2);
            if (entity_p.x > (x_bound_offset) * world.tile_side_in_meters) {
                new_cam_p.abs_tile_x += screen_tile_width;
            } else if (entity_p.x < -(x_bound_offset) * world.tile_side_in_meters) {
                new_cam_p.abs_tile_x -= screen_tile_width;
            }

            const y_bound_offset: i32 = @round(@as(f32, screen_tile_height) / 2);
            if (entity_p.y > (y_bound_offset) * world.tile_side_in_meters) {
                new_cam_p.abs_tile_y += screen_tile_height;
            } else if (entity_p.y < -(y_bound_offset) * world.tile_side_in_meters) {
                new_cam_p.abs_tile_y -= screen_tile_height;
            }
        } else {
            new_cam_p = cam_following_entity.low.p;
        }

        game_state.setCamera(new_cam_p);
    }

    @memset(@as([]u32, @ptrCast(@alignCast(offscreen_buffer.memory[0..offscreen_buffer.memory_len]))), 0xff00ff);
    drawRectangle(offscreen_buffer, V2.zero, v2u(offscreen_buffer.width, offscreen_buffer.height), 0.5, 0.5, 0.5);
    // drawBitmap(offscreen_buffer, game_state.backdrop, 0, 0, .{});

    const screen_center = v2(
        @floatFromInt(@divTrunc(offscreen_buffer.width, 2)),
        @floatFromInt(@divTrunc(offscreen_buffer.height, 2)),
    );

    var piece_group: EntityVisiblePieceGroup = .{ .game_state = game_state };
    for (game_state.high_entities[1..game_state.high_entity_count]) |*high_entity| {
        const low_entity = &game_state.low_entities[high_entity.low_entity_index];
        const entity = Entity{ .low_index = high_entity.low_entity_index, .high = high_entity, .low = low_entity };

        piece_group.count = 0;

        const hero_bitmap = &game_state.hero_bitmaps[@intFromEnum(high_entity.facing_direction)];
        const shadow_alpha = @max(0, 1 - high_entity.z);

        switch (low_entity.type) {
            .null => unreachable,

            .hero => {
                pushBitmap(&piece_group, &game_state.hero_shadow, V2.zero, 0, hero_bitmap.alignment, .{ .alpha = shadow_alpha, .entity_z_c = 0 });
                pushBitmap(&piece_group, &hero_bitmap.torso, V2.zero, 0, hero_bitmap.alignment, .{});
                pushBitmap(&piece_group, &hero_bitmap.cape, V2.zero, 0, hero_bitmap.alignment, .{});
                pushBitmap(&piece_group, &hero_bitmap.head, V2.zero, 0, hero_bitmap.alignment, .{});

                if (low_entity.hitpoint_max >= 1) {
                    const health_dim = v2(0.2, 0.2);
                    const spacing_x = health_dim.x * 1.5;

                    var hit_p = v2(
                        -0.5 * @as(f32, @floatFromInt(low_entity.hitpoint_max - 1)) * spacing_x,
                        -0.25,
                    );

                    for (low_entity.hitpoints[0..low_entity.hitpoint_max]) |*hit_point| {
                        var color = v4(1, 0, 0, 1);
                        if (hit_point.amount == 0) {
                            color = v4(0.2, 0.2, 0.2, 1);
                        }

                        pushRect(&piece_group, hit_p, 0, health_dim, color, .{ .entity_z_c = 0 });
                        hit_p.x += spacing_x;
                    }
                }
            },

            .familiar => {
                game_state.updateFamiliar(entity, input.dt);

                entity.high.t_bob += input.dt;
                if (entity.high.t_bob > math.tau) entity.high.t_bob -= math.tau;

                const bob_sin = @sin(2 * entity.high.t_bob);

                pushBitmap(&piece_group, &game_state.hero_shadow, V2.zero, 0, hero_bitmap.alignment, .{
                    .alpha = (0.5 * shadow_alpha) + (0.2 * bob_sin),
                    .entity_z_c = 0,
                });
                pushBitmap(&piece_group, &hero_bitmap.head, V2.zero, 0.25 * bob_sin, hero_bitmap.alignment, .{});
            },

            .monster => {
                game_state.updateMonster(entity, input.dt);
                pushBitmap(&piece_group, &game_state.hero_shadow, V2.zero, 0, hero_bitmap.alignment, .{ .alpha = shadow_alpha, .entity_z_c = 0 });
                pushBitmap(&piece_group, &hero_bitmap.torso, V2.zero, 0, hero_bitmap.alignment, .{});
            },

            .wall => {
                pushBitmap(&piece_group, &game_state.tree, V2.zero, 0, v2(40, 80), .{});
            },
        }

        const ddz = -9.8;
        high_entity.z = @max(0, high_entity.z + (0.5 * ddz * math.square(input.dt)) + (high_entity.d_z * input.dt));
        high_entity.d_z = (ddz * input.dt) + high_entity.d_z;

        const entity_ground_point = v2(
            screen_center.x + (game_state.meters_to_pixels * high_entity.p.x),
            screen_center.y - (game_state.meters_to_pixels * high_entity.p.y),
        );
        const entity_z = game_state.meters_to_pixels * -high_entity.z;

        for (piece_group.pieces[0..piece_group.count]) |*piece| {
            const center = v2(
                entity_ground_point.x + piece.offset.x,
                entity_ground_point.y + piece.offset.y + piece.offset_z + (piece.entity_z_c * entity_z),
            );

            if (piece.bitmap) |bitmap| {
                drawBitmap(offscreen_buffer, bitmap, center.x, center.y, piece.a);
            } else {
                const dim = piece.dim.mul(game_state.meters_to_pixels);
                const half_dim = dim.mul(0.5);
                drawRectangle(
                    offscreen_buffer,
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
        .offset_z = offset_z * group.game_state.meters_to_pixels,
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

    pub fn loadBMP(pd: *const platform.DEBUG, thread_context: *ThreadContext, filename: [:0]const u8) LoadedBitmap {
        var result: LoadedBitmap = .{};

        const read_result = pd.readEntireFile(thread_context, filename, filename.len);
        if (read_result.size != 0) {
            const content = read_result.slice();

            assert(content.len >= @sizeOf(BitmapHeader));
            const header: *BitmapHeader = @ptrCast(@alignCast(content));
            assert(header.header_size >= 40); // Earlier types are not binary compatible
            assert(header.compression == 3);

            const magic: [2]u8 = @bitCast(header.file_type);
            assert(std.mem.eql(u8, magic[0..], "BM"));

            const pixel_count: u32 = @intCast(header.width * header.height);

            assert(header.bits_per_pixel == 32); // TODO: account for scan line alignment
            result.pixels = @as([*]align(1) u32, @ptrCast(content.ptr + header.bitmap_offset))[0..pixel_count];
            assert(result.pixels.len == pixel_count);
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

            if (red_scan.index != 16 or green_scan.index != 8 or
                blue_scan.index != 0 or alpha_scan.index != 24)
            {
                const red_shift = 16 - @as(i32, @intCast(red_scan.index));
                const green_shift = 8 - @as(i32, @intCast(green_scan.index));
                const blue_shift = 0 - @as(i32, @intCast(blue_scan.index));
                const alpha_shift = 24 - @as(i32, @intCast(alpha_scan.index));

                for (result.pixels) |*pixel| {
                    const c = pixel.*;

                    pixel.* =
                        intrinsics.rotateLeft(c & red_mask, @intCast(red_shift)) |
                        intrinsics.rotateLeft(c & green_mask, @intCast(green_shift)) |
                        intrinsics.rotateLeft(c & blue_mask, @intCast(blue_shift)) |
                        intrinsics.rotateLeft(c & alpha_mask, @intCast(alpha_shift));
                }
            }
        }

        log.debug("Loaded bmp: {s} ({},{})", .{ filename, result.width, result.height });

        return result;
    }
};
