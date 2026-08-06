const std = @import("std");
const assert = std.debug.assert;

const v10 = @import("v10.zig");
const LoadedBitmap = v10.LoadedBitmap;
const GameState = v10.GameState;

const MemoryArena = @import("arena.zig");

const math = @import("math");
const V2 = math.V2;
const v2 = V2.init;
const V3 = math.V3;
const V4 = math.V4;
const v4 = V4.init;

const RenderGroup = @This();

pub const Basis = struct {
    p: V3,
};

pub const EntityVisiblePiece = struct {
    basis: *Basis,
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

default_basis: *Basis,
meters_to_pixels: f32,
count: u32 = 0,
push_buffer_size: usize = 0,
push_buffer: []u8 = &.{},

pub fn init(arena: *MemoryArena, max_push_buffer_size: usize, meters_to_pixels: f32) *RenderGroup {
    const result = arena.pushMemory(RenderGroup);
    const buffer_memory = arena.pushArray(max_push_buffer_size, u8);
    const default_basis = arena.pushMemory(Basis);

    default_basis.* = .{ .p = .zero };

    result.* = .{
        .meters_to_pixels = meters_to_pixels,
        .default_basis = default_basis,

        .count = 0,
        .push_buffer = buffer_memory,
        .push_buffer_size = 0,
    };

    return result;
}

pub inline fn pushRenderElement(this: *RenderGroup, size: usize) *anyopaque {
    var result: *anyopaque = undefined;

    if ((this.push_buffer_size + size) < this.push_buffer.len) {
        result = &this.push_buffer[this.push_buffer_size];
        this.push_buffer_size += size;
    } else {
        unreachable;
    }

    return result;
}

pub inline fn pushPiece(
    this: *RenderGroup,
    bitmap: ?*const LoadedBitmap,
    offset: V2,
    offset_z: f32,
    dim: V2,
    @"align": V2,
    entity_z_c: f32,
    color: V4,
) void {
    const piece: *EntityVisiblePiece = @ptrCast(@alignCast(this.pushRenderElement(@sizeOf(EntityVisiblePiece))));

    const c = color.color();

    piece.* = .{
        .basis = this.default_basis,
        .bitmap = bitmap,
        .offset = v2(offset.x, -offset.y).mul(this.meters_to_pixels).sub(@"align"),
        .offset_z = offset_z,
        .entity_z_c = entity_z_c,
        .r = c.r,
        .g = c.g,
        .b = c.b,
        .a = c.a,
        .dim = dim,
    };
    this.count += 1;
}

const PushBitmapOptions = struct {
    alpha: f32 = 1,
    entity_z_c: f32 = 1,
};

pub inline fn pushBitmap(this: *RenderGroup, bitmap: *const LoadedBitmap, offset: V2, offset_z: f32, @"align": V2, o: PushBitmapOptions) void {
    pushPiece(this, bitmap, offset, offset_z, V2.zero, @"align", o.entity_z_c, v4(1, 1, 1, o.alpha));
}

const PushRectOptions = struct {
    entity_z_c: f32 = 1,
};

pub inline fn pushRect(this: *RenderGroup, offset: V2, offset_z: f32, dim: V2, color: V4, o: PushRectOptions) void {
    pushPiece(
        this,
        null,
        offset,
        offset_z,
        dim,
        V2.zero,
        o.entity_z_c,
        color,
    );
}

pub inline fn pushRectOutline(this: *RenderGroup, offset: V2, offset_z: f32, dim: V2, color: V4, o: PushRectOptions) void {
    const t: f32 = 0.1;

    pushPiece(this, null, offset.sub(v2(0, 0.5 * dim.y)), offset_z, v2(dim.x + t, t), .zero, o.entity_z_c, color);
    pushPiece(this, null, offset.add(v2(0, 0.5 * dim.y)), offset_z, v2(dim.x + t, t), .zero, o.entity_z_c, color);

    pushPiece(this, null, offset.sub(v2(0.5 * dim.x, 0)), offset_z, v2(t, dim.y + t), .zero, o.entity_z_c, color);
    pushPiece(this, null, offset.add(v2(0.5 * dim.x, 0)), offset_z, v2(t, dim.y + t), .zero, o.entity_z_c, color);
}
