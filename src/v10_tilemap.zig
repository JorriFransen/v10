const std = @import("std");
const intrinsics = @import("intrinsics.zig");

const assert = std.debug.assert;

const MemoryArena = @import("v10_arena.zig");

const TileMap = @This();
pub const Tile = u32;

tile_size_in_meters: f32,
chunk_count_x: u32,
chunk_count_y: u32,
chunk_count_z: u32,
chunks: []Chunk,

const packed_tile_pos_bits = @bitSizeOf(@FieldType(PackedTilePosition, "tile"));
pub const chunk_dim = 1 << packed_tile_pos_bits;

pub const Position = struct {
    // Packed chunk.tile : 24.4
    abs_tile_x: u32,
    // Packed chunk.tile : 24.4
    abs_tile_y: u32,

    chunk_z: u32,

    /// In meters, from the bottom left
    tile_relative_x: f32,
    /// In meters, from the bottom left
    tile_relative_y: f32,

    pub fn recanonicalize(this: *Position, map: *const TileMap) void {
        map.recanonicalizeCoord(&this.abs_tile_x, &this.tile_relative_x);
        map.recanonicalizeCoord(&this.abs_tile_y, &this.tile_relative_y);
    }
};

pub const TileChunkPosition = struct {
    chunk_x: u32,
    chunk_y: u32,
    chunk_z: u32,

    rel_tile_x: u32,
    rel_tile_y: u32,
};

pub const PackedTilePosition = packed struct(u32) {
    tile: u4,
    chunk: u28,
};

pub const Chunk = struct {
    tiles: []Tile,

    pub fn getTileUnchecked(this: *const Chunk, x: u32, y: u32) Tile {
        assert(x < chunk_dim);
        assert(y < chunk_dim);

        return this.tiles[(y * chunk_dim) + (x)];
    }

    pub fn setTileUnchecked(this: *const Chunk, x: u32, y: u32, new_tile: Tile) void {
        assert(x < chunk_dim);
        assert(y < chunk_dim);

        this.tiles[(y * chunk_dim) + (x)] = new_tile;
    }
};

pub fn getChunkPositionFor(abs_tile_x: u32, abs_tile_y: u32, chunk_z: u32) TileChunkPosition {
    const packed_x: PackedTilePosition = @bitCast(abs_tile_x);
    const packed_y: PackedTilePosition = @bitCast(abs_tile_y);

    return .{
        .chunk_x = packed_x.chunk,
        .chunk_y = packed_y.chunk,
        .chunk_z = chunk_z,
        .rel_tile_x = packed_x.tile,
        .rel_tile_y = packed_y.tile,
    };
}

pub inline fn getChunk(this: *const TileMap, pos: TileChunkPosition) ?*Chunk {
    const x = pos.chunk_x;
    const y = pos.chunk_y;
    const z = pos.chunk_z;

    if (x < this.chunk_count_x and y < this.chunk_count_y and z < this.chunk_count_z) {
        return &this.chunks[
            z * this.chunk_count_y * this.chunk_count_x +
                (y * this.chunk_count_x) +
                (x)
        ];
    }

    return null;
}

pub fn getTile(map: *const TileMap, abs_tile_x: u32, abs_tile_y: u32, chunk_z: u32) Tile {
    const pos = getChunkPositionFor(abs_tile_x, abs_tile_y, chunk_z);
    const chunk_opt = map.getChunk(pos);
    return getChunkTile(chunk_opt, pos.rel_tile_x, pos.rel_tile_y);
}

pub fn setTile(map: *const TileMap, arena: *MemoryArena, abs_tile_x: u32, abs_tile_y: u32, chunk_z: u32, new_tile: Tile) void {
    const pos = getChunkPositionFor(abs_tile_x, abs_tile_y, chunk_z);
    const chunk_opt = map.getChunk(pos);

    assert(chunk_opt != null);
    const chunk = chunk_opt.?;

    if (chunk.tiles.len == 0) {
        chunk.tiles = arena.pushMemory([chunk_dim * chunk_dim]Tile);
        for (chunk.tiles) |*tile| {
            tile.* = 1;
        }
    }

    setChunkTile(chunk, pos.rel_tile_x, pos.rel_tile_y, new_tile);
}

pub fn isTileEmpty(map: *const TileMap, can_pos: Position) bool {
    var empty = false;

    const tile_value = map.getTile(can_pos.abs_tile_x, can_pos.abs_tile_y, can_pos.chunk_z);
    empty = tile_value == 1;

    return empty;
}

pub fn getChunkTile(chunk_opt: ?*const Chunk, x: u32, y: u32) Tile {
    var result: Tile = std.mem.zeroes(Tile);
    if (chunk_opt) |chunk| {
        if (chunk.tiles.len > 0) {
            result = chunk.getTileUnchecked(x, y);
        }
    }

    return result;
}

pub fn setChunkTile(chunk_opt: ?*const Chunk, x: u32, y: u32, new_tile: Tile) void {
    if (chunk_opt) |chunk| {
        chunk.setTileUnchecked(x, y, new_tile);
    }
}

pub fn recanonicalizeCoord(map: *const TileMap, tile: *u32, tile_rel: *f32) void {
    // const tile_offset: i32 = intrinsics.floorFloatToInt(i32, tile_rel.* / world.tile_size_in_meters);
    const tile_offset: i32 = intrinsics.roundFloatToInt(i32, tile_rel.* / map.tile_size_in_meters);
    tile.* +%= @as(u32, @bitCast(tile_offset));
    tile_rel.* -= @as(f32, @floatFromInt(tile_offset)) * map.tile_size_in_meters;

    assert(tile_rel.* >= -(0.5 * map.tile_size_in_meters));
    assert(tile_rel.* <= (0.5 * map.tile_size_in_meters));
}

pub fn recanonicalizePosition(map: *const TileMap, pos: Position) Position {
    var result = pos;
    result.recanonicalize(map);
    return result;
}
