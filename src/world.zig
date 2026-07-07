const std = @import("std");
const assert = std.debug.assert;

const MemoryArena = @import("arena.zig");
const intrinsics = @import("intrinsics.zig");

const v10 = @import("v10.zig");
const EntityIndex = v10.EntityIndex;
const LowEntity = v10.LowEntity;

const math = @import("math");
const V2 = math.V2;
const v2 = V2.init;

const World = @This();

tile_side_in_meters: f32,
chunk_side_in_meters: f32,
first_free_entity_block: ?*EntityBlock = null,
chunk_hash: [4096]Chunk = undefined,

const chunk_safe_margin = math.maxInt(i32) / 64;
const chunk_x_uninitialized = math.maxInt(i32);
pub const tiles_per_chunk_side = 16;

pub fn init(this: *World, tile_side_in_meters: f32) void {
    this.* = .{
        .tile_side_in_meters = tile_side_in_meters,
        .chunk_side_in_meters = tiles_per_chunk_side * tile_side_in_meters,
        .first_free_entity_block = null,
    };

    for (&this.chunk_hash) |*chunk| {
        chunk.x = chunk_x_uninitialized;
        chunk.first_entity_block.entity_count = 0;
        chunk.first_entity_block.next = null;
    }
}

pub const Position = struct {
    chunk_x: i32,
    chunk_y: i32,
    chunk_z: i32,

    /// In meters, from the chunk center
    _offset: V2 = .{},

    pub const zero: Position = .{ .chunk_x = 0, .chunk_y = 0, .chunk_z = 0, ._offset = .zero };
    pub const @"null": Position = .{ .chunk_x = chunk_x_uninitialized, .chunk_y = 0, .chunk_z = 0, ._offset = .zero };

    pub const Delta = struct {
        xy: V2,
        z: f32,
    };

    pub inline fn isValid(this: Position) bool {
        return this.chunk_x != @"null".chunk_x;
    }

    pub fn offset(this: Position, world: *const World, offset_by: V2) Position {
        var result = this;

        result._offset = result._offset.add(offset_by);
        result = result.recanonicalize(world);

        return result;
    }

    pub inline fn recanonicalize(position: Position, world: *const World) Position {
        var result = position;
        world.recanonicalizeCoord(&result.chunk_x, &result._offset.x);
        world.recanonicalizeCoord(&result.chunk_y, &result._offset.y);
        return result;
    }
};

pub inline fn recanonicalizeCoord(this: *const World, chunk: *i32, chunk_rel: *f32) void {
    const offset: i32 = intrinsics.roundReal32ToInt32(chunk_rel.* / this.chunk_side_in_meters);
    chunk.* +%= @bitCast(offset);
    chunk_rel.* -= @as(f32, @floatFromInt(offset)) * this.chunk_side_in_meters;

    assert(this.isCanonical(chunk_rel.*));
}

pub inline fn isCanonical(this: *const World, chunk_rel: f32) bool {
    const epsilon = 0.0001;

    const result =
        chunk_rel >= -(0.5 * this.chunk_side_in_meters + epsilon) and
        chunk_rel <= (0.5 * this.chunk_side_in_meters + epsilon);
    return result;
}

pub inline fn isCanonicalOffset(this: *const World, offset: V2) bool {
    const result = this.isCanonical(offset.x) and this.isCanonical(offset.x);
    return result;
}

pub const EntityBlock = struct {
    entity_count: u32 = 0,
    entity_indices: [16]EntityIndex = undefined,
    next: ?*EntityBlock = null,
};

pub const Chunk = struct {
    x: i32 = 0,
    y: i32 = 0,
    z: i32 = 0,

    first_entity_block: EntityBlock = .{},

    next_in_hash: ?*Chunk = null,
};

pub inline fn subtract(this: *const World, a: Position, b: Position) Position.Delta {
    var result: Position.Delta = undefined;

    // const diff_x = @as(f64, @floatFromInt(a.chunk_x)) - @as(f64, @floatFromInt(b.chunk_x));
    // const diff_y = @as(f64, @floatFromInt(a.chunk_y)) - @as(f64, @floatFromInt(b.chunk_y));
    // const d_chunk_xy = v2(@floatCast(diff_x), @floatCast(diff_y));
    const d_chunk_xy = v2(
        @as(f32, @floatFromInt(a.chunk_x)) - @as(f32, @floatFromInt(b.chunk_x)),
        @as(f32, @floatFromInt(a.chunk_y)) - @as(f32, @floatFromInt(b.chunk_y)),
    );

    const d_chunk_z = @as(f32, @floatFromInt(a.chunk_z)) - @as(f32, @floatFromInt(b.chunk_z));

    result.xy = d_chunk_xy.mul(this.chunk_side_in_meters).add(a._offset.sub(b._offset));

    result.z = (this.chunk_side_in_meters * d_chunk_z);

    return result;
}

pub const GetChunkOptions = struct {
    arena: ?*MemoryArena = null,
};

pub fn getChunk(this: *World, chunk_x: i32, chunk_y: i32, chunk_z: i32, options: GetChunkOptions) ?*Chunk {
    assert(chunk_x > -chunk_safe_margin);
    assert(chunk_y > -chunk_safe_margin);
    assert(chunk_z > -chunk_safe_margin);
    assert(chunk_x < chunk_safe_margin);
    assert(chunk_y < chunk_safe_margin);
    assert(chunk_z < chunk_safe_margin);

    const hash_value: u32 = @bitCast(19 *% chunk_x +% 7 *% chunk_y +% 3 *% chunk_z);
    const hash_slot = hash_value & (this.chunk_hash.len - 1);
    assert(hash_slot < this.chunk_hash.len);

    var chunk_opt: ?*Chunk = &this.chunk_hash[hash_slot];
    while (chunk_opt) |chunk_| {
        var chunk = chunk_;

        if ((chunk_x == chunk.x) and
            (chunk_y == chunk.y) and
            (chunk_z == chunk.z))
        {
            break;
        }

        if (options.arena) |arena| {
            if (chunk.x != chunk_x_uninitialized and chunk.next_in_hash == null) {
                const new_chunk = arena.pushMemory(Chunk);
                new_chunk.x = chunk_x_uninitialized;
                chunk.next_in_hash = new_chunk;
                chunk = new_chunk;
            }

            if (chunk.x == chunk_x_uninitialized) {
                chunk.* = .{
                    .x = chunk_x,
                    .y = chunk_y,
                    .z = chunk_z,
                    .next_in_hash = null,
                };

                break;
            }
        }

        chunk_opt = chunk.next_in_hash;
    }

    return chunk_opt;
}

pub inline fn areInSameChunk(this: *World, a: Position, b: Position) bool {
    assert(this.isCanonicalOffset(a._offset));
    assert(this.isCanonicalOffset(b._offset));

    const result = a.chunk_x == b.chunk_x and
        a.chunk_y == b.chunk_y and
        a.chunk_z == b.chunk_z;
    return result;
}
pub fn changeEntityLocation(
    this: *World,
    arena: *MemoryArena,
    low_index: EntityIndex,
    low_entity: *LowEntity,
    old_p_opt: ?Position,
    new_p_opt: ?Position,
) void {
    this.changeEntityLocationRaw(arena, low_index, old_p_opt, new_p_opt);

    if (new_p_opt) |new_p| {
        low_entity.p = new_p;
    } else {
        low_entity.p = .null;
    }
}

pub fn changeEntityLocationRaw(this: *World, arena: *MemoryArena, low_index: EntityIndex, old_p_opt: ?Position, new_p_opt: ?Position) void {
    assert(old_p_opt == null or old_p_opt.?.isValid());
    assert(new_p_opt == null or new_p_opt.?.isValid());

    if (old_p_opt != null and new_p_opt != null and this.areInSameChunk(old_p_opt.?, new_p_opt.?)) {
        // ok
    } else {
        if (old_p_opt) |old_p| {
            const chunk_opt = this.getChunk(old_p.chunk_x, old_p.chunk_y, old_p.chunk_z, .{});
            assert(chunk_opt != null);

            if (chunk_opt) |chunk| {
                const first_block = &chunk.first_entity_block;
                var block_opt: ?*EntityBlock = first_block;

                block_loop: while (block_opt) |block| : (block_opt = block.next) {
                    for (block.entity_indices[0..block.entity_count]) |*entity_index_ptr| {
                        if (low_index == entity_index_ptr.*) {
                            first_block.entity_count -= 1;
                            entity_index_ptr.* = first_block.entity_indices[first_block.entity_count];

                            if (first_block.entity_count == 0) {
                                if (first_block.next) |next| {
                                    first_block.* = next.*;

                                    next.next = this.first_free_entity_block;
                                    this.first_free_entity_block = next;
                                }
                            }

                            break :block_loop;
                        }
                    }
                }
            }
        }

        if (new_p_opt) |new_p| {
            // insert
            const chunk = this.getChunk(new_p.chunk_x, new_p.chunk_y, new_p.chunk_z, .{ .arena = arena }).?;
            const block = &chunk.first_entity_block;

            if (block.entity_count >= block.entity_indices.len) {
                var old_block_opt = this.first_free_entity_block;

                if (old_block_opt) |old_block| {
                    this.first_free_entity_block = old_block.next;
                } else {
                    old_block_opt = arena.pushMemory(EntityBlock);
                }
                const old_block = old_block_opt.?;

                old_block.* = block.*;
                block.next = old_block;
                block.entity_count = 0;
            }

            assert(block.entity_count < block.entity_indices.len);
            block.entity_indices[block.entity_count] = low_index;
            block.entity_count += 1;
        }
    }
}

pub fn chunkPositionFromTilePosition(this: *const World, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) World.Position {
    if (false) {
        // Exact hh macth
        var result: Position = .zero;

        result.chunk_x = @divTrunc(abs_tile_x, World.tiles_per_chunk_side);
        result.chunk_y = @divTrunc(abs_tile_y, World.tiles_per_chunk_side);
        result.chunk_z = @divTrunc(abs_tile_z, World.tiles_per_chunk_side);

        if (abs_tile_x < 0) result.chunk_x -= 1;
        if (abs_tile_y < 0) result.chunk_y -= 1;
        if (abs_tile_z < 0) result.chunk_z -= 1;

        const chunk_tiles = World.tiles_per_chunk_side;
        const x_tiles: f32 = @floatFromInt((abs_tile_x - (chunk_tiles / 2)) - (result.chunk_x * chunk_tiles));
        const y_tiles: f32 = @floatFromInt((abs_tile_y - (chunk_tiles / 2)) - (result.chunk_y * chunk_tiles));
        result._offset = v2(x_tiles, y_tiles).mul(this.tile_side_in_meters);

        assert(this.isCanonicalOffset(result._offset));

        return result;
    } else {
        const chunk_x = @divFloor(abs_tile_x, World.tiles_per_chunk_side);
        const chunk_y = @divFloor(abs_tile_y, World.tiles_per_chunk_side);

        const chunk_tiles = World.tiles_per_chunk_side;
        const x_tiles: f32 = @floatFromInt((abs_tile_x - (chunk_tiles / 2)) - (chunk_x * chunk_tiles));
        const y_tiles: f32 = @floatFromInt((abs_tile_y - (chunk_tiles / 2)) - (chunk_y * chunk_tiles));
        const offset = v2(x_tiles, y_tiles).mul(this.tile_side_in_meters);

        const result = World.Position{
            .chunk_x = chunk_x,
            .chunk_y = chunk_y,
            .chunk_z = abs_tile_z,
            ._offset = offset,
        };

        assert(this.isCanonicalOffset(result._offset));

        return result;
    }
}
