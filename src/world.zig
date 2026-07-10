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
const V3 = math.V3;
const v3 = V3.init;
const v3i = V3.initSigned;

const World = @This();

tile_side_in_meters: f32,
tile_depth_in_meters: f32,
chunk_dim_in_meters: V3,

first_free_entity_block: ?*EntityBlock = null,
chunk_hash: [4096]Chunk = undefined,

const chunk_safe_margin = math.maxInt(i32) / 64;
const chunk_x_uninitialized = math.maxInt(i32);
pub const tiles_per_chunk_side = 16;

pub fn init(this: *World, tile_side_in_meters: f32) void {
    this.* = .{
        .tile_side_in_meters = tile_side_in_meters,
        .tile_depth_in_meters = tile_side_in_meters,
        .chunk_dim_in_meters = v3(
            tiles_per_chunk_side * tile_side_in_meters,
            tiles_per_chunk_side * tile_side_in_meters,
            tile_side_in_meters,
        ),
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
    _offset: V3 = .{},

    pub const zero: Position = .{ .chunk_x = 0, .chunk_y = 0, .chunk_z = 0, ._offset = .zero };
    pub const @"null": Position = .{ .chunk_x = chunk_x_uninitialized, .chunk_y = 0, .chunk_z = 0, ._offset = .zero };

    pub inline fn isValid(this: Position) bool {
        return this.chunk_x != @"null".chunk_x;
    }

    pub fn offset(this: Position, world: *const World, offset_by: V3) Position {
        var result = this;

        result._offset = result._offset.add(offset_by);
        result = result.recanonicalize(world);

        return result;
    }

    pub inline fn recanonicalize(position: Position, world: *const World) Position {
        var result = position;
        recanonicalizeCoord(&result.chunk_x, &result._offset.x, world.chunk_dim_in_meters.x);
        recanonicalizeCoord(&result.chunk_y, &result._offset.y, world.chunk_dim_in_meters.y);
        recanonicalizeCoord(&result.chunk_z, &result._offset.z, world.chunk_dim_in_meters.z);
        return result;
    }
};

pub inline fn recanonicalizeCoord(chunk: *i32, chunk_rel: *f32, chunk_size: f32) void {
    const offset: i32 = intrinsics.roundReal32ToInt32(chunk_rel.* / chunk_size);
    chunk.* +%= @bitCast(offset);
    chunk_rel.* -= @as(f32, @floatFromInt(offset)) * chunk_size;

    assert(isCanonical(chunk_rel.*, chunk_size));
}

pub inline fn isCanonical(chunk_rel: f32, chunk_size: f32) bool {
    const epsilon = 0.0001;

    const result =
        chunk_rel >= -(0.5 * chunk_size + epsilon) and
        chunk_rel <= (0.5 * chunk_size + epsilon);
    return result;
}

pub inline fn isCanonicalOffset(this: *const World, offset: V3) bool {
    const result =
        isCanonical(offset.x, this.chunk_dim_in_meters.x) and
        isCanonical(offset.y, this.chunk_dim_in_meters.y) and
        isCanonical(offset.z, this.chunk_dim_in_meters.z);
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

pub inline fn subtract(this: *const World, a: Position, b: Position) V3 {
    var result: V3 = undefined;

    const d_tile = v3(
        @as(f32, @floatFromInt(a.chunk_x)) - @as(f32, @floatFromInt(b.chunk_x)),
        @as(f32, @floatFromInt(a.chunk_y)) - @as(f32, @floatFromInt(b.chunk_y)),
        @as(f32, @floatFromInt(a.chunk_z)) - @as(f32, @floatFromInt(b.chunk_z)),
    );

    result = this.chunk_dim_in_meters.hadamard(d_tile).add(a._offset.sub(b._offset));

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
    const result: ?*Chunk = blk: while (chunk_opt) |chunk_| {
        var chunk = chunk_;

        if ((chunk_x == chunk.x) and
            (chunk_y == chunk.y) and
            (chunk_z == chunk.z))
        {
            break :blk chunk;
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

                break :blk chunk;
            }
        }

        chunk_opt = chunk.next_in_hash;
    } else null;

    return result;
}

pub inline fn areInSameChunk(this: *World, a: Position, b: Position) bool {
    assert(this.isCanonicalOffset(a._offset));
    assert(this.isCanonicalOffset(b._offset));

    const result = a.chunk_x == b.chunk_x and
        a.chunk_y == b.chunk_y and
        a.chunk_z == b.chunk_z;
    return result;
}
pub fn changeEntityLocation(this: *World, arena: *MemoryArena, low_index: EntityIndex, low_entity: *LowEntity, new_p_in: Position) void {
    var old_p_opt: ?Position = null;
    var new_p_opt: ?Position = null;

    if (!low_entity.sim.flags.non_spatial and low_entity.p.isValid()) {
        old_p_opt = low_entity.p;
    }

    if (new_p_in.isValid()) {
        new_p_opt = new_p_in;
    }

    this.changeEntityLocationRaw(arena, low_index, old_p_opt, new_p_opt);

    if (new_p_opt) |new_p| {
        low_entity.p = new_p;
        low_entity.sim.flags.non_spatial = false;
    } else {
        low_entity.p = .null;
        low_entity.sim.flags.non_spatial = true;
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

pub fn chunkPositionFromTilePosition(this: *const World, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) Position {
    const offset: V3 = v3i(abs_tile_x, abs_tile_y, abs_tile_z).hadamard(this.chunk_dim_in_meters);
    const result = Position.zero.offset(this, offset);

    assert(isCanonicalOffset(this, result._offset));

    return result;
}
