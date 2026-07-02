const std = @import("std");
const intrinsics = @import("intrinsics.zig");

const assert = std.debug.assert;

const math = @import("math.zig");
const V2 = math.V2;
const v2 = V2.init;

const MemoryArena = @import("arena.zig");

const TileMap = @This();
pub const Tile = u32;

tile_size_in_meters: f32,
chunk_hash: [4096]Chunk,

const packed_tile_pos_bits = @bitSizeOf(@FieldType(PackedTilePosition, "tile"));
pub const chunk_dim = 1 << packed_tile_pos_bits;
const chunk_safe_margin = std.math.maxInt(@Int(.signed, @bitSizeOf(PackedTilePosition))) / 64;
const chunk_x_uninitialized = std.math.maxInt(@Int(.signed, @bitSizeOf(PackedTilePosition)));

pub fn init(this: *TileMap, tile_size_in_meters: f32) void {
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

    pub inline fn mapIntoTileSpace(this: Position, map: *const TileMap, offset: V2) Position {
        var result = this;

        result._offset = result._offset.add(offset);
        result = result.recanonicalize(map);

        return result;
    }

    pub inline fn recanonicalize(position: Position, map: *const TileMap) Position {
        var result = position;
        map.recanonicalizeCoord(&result.abs_tile_x, &result._offset.x);
        map.recanonicalizeCoord(&result.abs_tile_y, &result._offset.y);
        return result;
    }
};

pub inline fn recanonicalizeCoord(map: *const TileMap, tile: *i32, tile_rel: *f32) void {
    const offset: i32 = intrinsics.roundReal32ToInt32(tile_rel.* / map.tile_size_in_meters);
    tile.* +%= @bitCast(offset);
    tile_rel.* -= @as(f32, @floatFromInt(offset)) * map.tile_size_in_meters;

    assert(tile_rel.* >= -(0.5 * map.tile_size_in_meters));
    assert(tile_rel.* <= (0.5 * map.tile_size_in_meters));
}

pub const TileChunkPosition = struct {
    chunk_x: i32,
    chunk_y: i32,
    chunk_z: i32,

    rel_tile_x: i32,
    rel_tile_y: i32,
};

pub const TilePositionUInt = i32;
pub const PackedTilePosition = packed struct(TilePositionUInt) {
    tile: u4,
    chunk: i28,
};

pub const Chunk = struct {
    x: i32 = 0,
    y: i32 = 0,
    z: i32 = 0,

    tiles: []Tile = undefined,

    next_in_hash: ?*Chunk = null,

    pub inline fn getTileUnchecked(this: *const Chunk, x: u32, y: u32) Tile {
        assert(x < chunk_dim);
        assert(y < chunk_dim);

        return this.tiles[(y * chunk_dim) + x];
    }

    pub fn setTileUnchecked(this: *const Chunk, x: i32, y: i32, new_tile: Tile) void {
        assert(@abs(x) < chunk_dim);
        assert(@abs(y) < chunk_dim);

        const index: usize = @intCast(@as(u32, @bitCast((y * chunk_dim) + x)));
        this.tiles[index] = new_tile;
    }
};

pub inline fn subtract(map: *const TileMap, a: Position, b: Position) Position.Delta {
    var result: Position.Delta = undefined;

    // const diff_x = @as(f64, @floatFromInt(a.abs_tile_x)) - @as(f64, @floatFromInt(b.abs_tile_x));
    // const diff_y = @as(f64, @floatFromInt(a.abs_tile_y)) - @as(f64, @floatFromInt(b.abs_tile_y));
    // const d_tile_xy = v2(@floatCast(diff_x), @floatCast(diff_y));
    const d_tile_xy = v2(
        @as(f32, @floatFromInt(a.abs_tile_x)) - @as(f32, @floatFromInt(b.abs_tile_x)),
        @as(f32, @floatFromInt(a.abs_tile_y)) - @as(f32, @floatFromInt(b.abs_tile_y)),
    );

    const d_tile_z = @as(f32, @floatFromInt(a.chunk_z)) - @as(f32, @floatFromInt(b.chunk_z));

    result.xy = d_tile_xy.mul(map.tile_size_in_meters).add(a._offset.sub(b._offset));

    result.z = (map.tile_size_in_meters * d_tile_z);

    return result;
}

pub inline fn getChunkPositionFor(abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32) TileChunkPosition {
    const packed_x: PackedTilePosition = @bitCast(abs_tile_x);
    const packed_y: PackedTilePosition = @bitCast(abs_tile_y);

    return .{
        .chunk_x = packed_x.chunk,
        .chunk_y = packed_y.chunk,
        .chunk_z = abs_tile_z,
        .rel_tile_x = packed_x.tile,
        .rel_tile_y = packed_y.tile,
    };
}

pub const GetChunkOptions = struct {
    arena: ?*MemoryArena = null,
};

pub fn getChunk(this: *TileMap, chunk_x: i32, chunk_y: i32, chunk_z: i32, options: GetChunkOptions) ?*Chunk {
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
                    .tiles = arena.pushArray(chunk_dim * chunk_dim, Tile),
                    .x = chunk_x,
                    .y = chunk_y,
                    .z = chunk_z,
                    .next_in_hash = null,
                };
                for (chunk.tiles) |*tile| tile.* = 1;

                break;
            }
        }

        chunk_opt = chunk.next_in_hash;
    }

    return chunk_opt.?;
}

pub inline fn getTile(map: *const TileMap, pos: Position) Tile {
    return map.getTileXYZ(pos.abs_tile_x, pos.abs_tile_y, pos.chunk_z);
}

pub inline fn getTileXYZ(map: *const TileMap, abs_tile_x: u32, abs_tile_y: u32, abs_tile_z: u32) Tile {
    const pos = getChunkPositionFor(abs_tile_x, abs_tile_y, abs_tile_z);
    const chunk_opt = map.getChunk(pos.chunk_x, pos.chunk_y, pos.chunk_z);
    return getChunkTile(chunk_opt, pos.rel_tile_x, pos.rel_tile_y);
}

pub fn setTile(map: *TileMap, arena: *MemoryArena, abs_tile_x: i32, abs_tile_y: i32, abs_tile_z: i32, new_tile: Tile) void {
    const pos = getChunkPositionFor(abs_tile_x, abs_tile_y, abs_tile_z);
    const chunk_opt = map.getChunk(pos.chunk_x, pos.chunk_y, pos.chunk_z, .{ .arena = arena });

    if (chunk_opt) |chunk| {
        setChunkTile(chunk, pos.rel_tile_x, pos.rel_tile_y, new_tile);
    }
}

pub inline fn isTileValueEmpty(tile: Tile) bool {
    return tile == 1 or tile == 3 or tile == 4;
}

pub inline fn isTileEmpty(map: *const TileMap, abs_tile_x: u32, abs_tile_y: u32, chunk_z: u32) bool {
    return map.isTilePosEmpty(.{ .abs_tile_x = abs_tile_x, .abs_tile_y = abs_tile_y, .chunk_z = chunk_z });
}

pub inline fn isTilePosEmpty(map: *const TileMap, can_pos: Position) bool {
    var empty = false;

    const tile_value = map.getTileXYZ(can_pos.abs_tile_x, can_pos.abs_tile_y, can_pos.chunk_z);
    empty = isTileValueEmpty(tile_value);

    return empty;
}

pub inline fn getChunkTile(chunk_opt: ?*const Chunk, x: u32, y: u32) Tile {
    var result: Tile = std.mem.zeroes(Tile);
    if (chunk_opt) |chunk| {
        if (chunk.tiles.len > 0) {
            result = chunk.getTileUnchecked(x, y);
        }
    }

    return result;
}

pub fn setChunkTile(chunk_opt: ?*const Chunk, x: i32, y: i32, new_tile: Tile) void {
    if (chunk_opt) |chunk| {
        chunk.setTileUnchecked(x, y, new_tile);
    }
}

pub inline fn inSameTile(p1: Position, p2: Position) bool {
    return p1.abs_tile_x == p2.abs_tile_x and p1.abs_tile_y == p2.abs_tile_y and p1.chunk_z == p2.chunk_z;
}

pub inline fn centerTilePoint(abs_tile_x: u32, abs_tile_y: u32, chunk_z: u32) Position {
    return .{
        .abs_tile_x = abs_tile_x,
        .abs_tile_y = abs_tile_y,
        .chunk_z = chunk_z,
    };
}
