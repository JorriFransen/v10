const std = @import("std");
const assert = std.debug.assert;

const MemoryArena = @import("arena.zig");
const intrinsics = @import("intrinsics.zig");
const v10 = @import("v10.zig");

const math = @import("math.zig");
const V2 = math.V2;
const v2 = V2.init;

const World = @This();

tile_size_in_meters: f32,
chunk_hash: [4096]Chunk,

const packed_tile_pos_bits = @bitSizeOf(@FieldType(PackedTilePosition, "tile"));
pub const chunk_dim = 1 << packed_tile_pos_bits;
const chunk_safe_margin = std.math.maxInt(@Int(.signed, @bitSizeOf(PackedTilePosition))) / 64;
const chunk_x_uninitialized = std.math.maxInt(@Int(.signed, @bitSizeOf(PackedTilePosition)));

pub fn init(this: *World, tile_size_in_meters: f32) void {
    this.* = .{
        .tile_size_in_meters = tile_size_in_meters,
        .chunk_hash = @splat(.{ .x = chunk_x_uninitialized }),
    };
}

pub const Position = struct {
    // Packed chunk.tile : 24.4
    abs_tile_x: i32,
    // Packed chunk.tile : 24.4
    abs_tile_y: i32,

    chunk_z: i32,

    /// In meters, from the tile center
    _offset: V2 = .{},

    pub const Delta = struct {
        xy: V2,
        z: f32,
    };

    pub inline fn offset(this: Position, world: *const World, offset_by: V2) Position {
        var result = this;

        result._offset = result._offset.add(offset_by);
        result = result.recanonicalize(world);

        return result;
    }

    pub inline fn recanonicalize(position: Position, world: *const World) Position {
        var result = position;
        world.recanonicalizeCoord(&result.abs_tile_x, &result._offset.x);
        world.recanonicalizeCoord(&result.abs_tile_y, &result._offset.y);
        return result;
    }
};

pub inline fn recanonicalizeCoord(this: *const World, tile: *i32, tile_rel: *f32) void {
    const offset: i32 = intrinsics.roundReal32ToInt32(tile_rel.* / this.tile_size_in_meters);
    tile.* +%= @bitCast(offset);
    tile_rel.* -= @as(f32, @floatFromInt(offset)) * this.tile_size_in_meters;

    assert(tile_rel.* >= -(0.5 * this.tile_size_in_meters));
    assert(tile_rel.* <= (0.5 * this.tile_size_in_meters));
}

pub const TilePositionUInt = i32;
pub const PackedTilePosition = packed struct(TilePositionUInt) {
    tile: u4,
    chunk: i28,
};

pub const ChunkEntityBlock = struct {
    entity_count: u32 = 0,
    entity_indices: [16]v10.EntityIndex = @splat(0),
    next: ?*ChunkEntityBlock = null,
};

pub const Chunk = struct {
    x: i32 = 0,
    y: i32 = 0,
    z: i32 = 0,

    first_entity_block: ChunkEntityBlock = .{},

    next_in_hash: ?*Chunk = null,
};

pub inline fn subtract(this: *const World, a: Position, b: Position) Position.Delta {
    var result: Position.Delta = undefined;

    // const diff_x = @as(f64, @floatFromInt(a.abs_tile_x)) - @as(f64, @floatFromInt(b.abs_tile_x));
    // const diff_y = @as(f64, @floatFromInt(a.abs_tile_y)) - @as(f64, @floatFromInt(b.abs_tile_y));
    // const d_tile_xy = v2(@floatCast(diff_x), @floatCast(diff_y));
    const d_tile_xy = v2(
        @as(f32, @floatFromInt(a.abs_tile_x)) - @as(f32, @floatFromInt(b.abs_tile_x)),
        @as(f32, @floatFromInt(a.abs_tile_y)) - @as(f32, @floatFromInt(b.abs_tile_y)),
    );

    const d_tile_z = @as(f32, @floatFromInt(a.chunk_z)) - @as(f32, @floatFromInt(b.chunk_z));

    result.xy = d_tile_xy.mul(this.tile_size_in_meters).add(a._offset.sub(b._offset));

    result.z = (this.tile_size_in_meters * d_tile_z);

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
