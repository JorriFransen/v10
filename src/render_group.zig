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

pub const Basis = extern struct {
    p: V3,
};

pub const EntityBasis = extern struct {
    basis: *Basis,

    offset: V2,
    offset_z: f32,
    entity_z_c: f32,
};

pub const EntryHeader = extern struct {
    const Type = enum(u32) {
        // Names must match struct names!
        EntryClear,
        EntryBitmap,
        EntryRectangle,
        // Names must match struct names!
    };

    type: @This().Type,
};

pub const EntryClear = extern struct {
    header: EntryHeader,

    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const EntryBitmap = extern struct {
    header: EntryHeader,

    entity_basis: EntityBasis,
    bitmap: *const LoadedBitmap,

    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const EntryRectangle = extern struct {
    header: EntryHeader,

    entity_basis: EntityBasis,

    r: f32,
    g: f32,
    b: f32,
    a: f32,

    dim: V2,
};

const push_buffer_align = 8;

default_basis: *Basis,
meters_to_pixels: f32,
push_buffer_size: usize = 0,
push_buffer: []u8 = &.{},

pub fn init(arena: *MemoryArena, max_push_buffer_size: usize, meters_to_pixels: f32) *RenderGroup {
    const result = arena.push(RenderGroup);
    const buffer_memory = arena.pushArray(max_push_buffer_size, u8);
    const default_basis = arena.push(Basis);

    default_basis.* = .{ .p = .zero };

    result.* = .{
        .meters_to_pixels = meters_to_pixels,
        .default_basis = default_basis,

        .push_buffer = buffer_memory,
        .push_buffer_size = 0,
    };

    return result;
}

pub inline fn pushRenderElement(this: *RenderGroup, comptime T: type) ?*T {
    const size = @sizeOf(T);

    var result: ?*EntryHeader = null;

    if ((this.push_buffer_size + size) < this.push_buffer.len) {
        result = @ptrCast(@alignCast(&this.push_buffer[this.push_buffer_size]));
        const header = result.?;
        assert(std.mem.isAligned(@intFromPtr(header), push_buffer_align));

        header.type = comptime blk: {
            const full_type_str = @typeName(T);
            const type_str = if (std.mem.lastIndexOfScalar(u8, full_type_str, '.')) |dot_idx| full_type_str[dot_idx + 1 ..] else full_type_str;
            break :blk @field(EntryHeader.Type, type_str);
        };

        this.push_buffer_size += size;
    } else {
        unreachable;
    }

    return @ptrCast(@alignCast(result));
}

pub inline fn pushPiece(
    this: *RenderGroup,
    bitmap: *const LoadedBitmap,
    offset: V2,
    offset_z: f32,
    @"align": V2,
    entity_z_c: f32,
    color: V4,
) void {
    if (this.pushRenderElement(EntryBitmap)) |piece| {
        const c = color.color();

        piece.entity_basis.basis = this.default_basis;
        piece.entity_basis.offset = v2(offset.x, -offset.y).mul(this.meters_to_pixels).sub(@"align");
        piece.entity_basis.offset_z = offset_z;
        piece.entity_basis.entity_z_c = entity_z_c;
        piece.bitmap = bitmap;
        piece.r = c.r;
        piece.g = c.g;
        piece.b = c.b;
        piece.a = c.a;
    }
}

const PushBitmapOptions = struct {
    alpha: f32 = 1,
    entity_z_c: f32 = 1,
};

pub inline fn pushBitmap(this: *RenderGroup, bitmap: *const LoadedBitmap, offset: V2, offset_z: f32, @"align": V2, o: PushBitmapOptions) void {
    this.pushPiece(bitmap, offset, offset_z, @"align", o.entity_z_c, v4(1, 1, 1, o.alpha));
}

const PushRectOptions = struct {
    entity_z_c: f32 = 1,
};

pub inline fn pushRect(this: *RenderGroup, offset: V2, offset_z: f32, dim: V2, color: V4, o: PushRectOptions) void {
    if (this.pushRenderElement(EntryRectangle)) |piece| {
        const c = color.color();

        const half_dim = dim.mul(this.meters_to_pixels * 0.5);

        piece.entity_basis.basis = this.default_basis;
        piece.entity_basis.offset = v2(offset.x, -offset.y).mul(this.meters_to_pixels).sub(half_dim);
        piece.entity_basis.offset_z = offset_z;
        piece.entity_basis.entity_z_c = o.entity_z_c;
        piece.r = c.r;
        piece.g = c.g;
        piece.b = c.b;
        piece.a = c.a;
        piece.dim = dim.mul(this.meters_to_pixels);
    }
}

pub inline fn pushRectOutline(this: *RenderGroup, offset: V2, offset_z: f32, dim: V2, color: V4, o: PushRectOptions) void {
    const t: f32 = 0.1;

    this.pushRect(offset.sub(v2(0, 0.5 * dim.y)), offset_z, v2(dim.x + t, t), color, o);
    this.pushRect(offset.add(v2(0, 0.5 * dim.y)), offset_z, v2(dim.x + t, t), color, o);

    this.pushRect(offset.sub(v2(0.5 * dim.x, 0)), offset_z, v2(t, dim.y + t), color, o);
    this.pushRect(offset.add(v2(0.5 * dim.x, 0)), offset_z, v2(t, dim.y + t), color, o);

    // pushPiece(this, null, offset.sub(v2(0, 0.5 * dim.y)), offset_z, v2(dim.x + t, t), .zero, o.entity_z_c, color);
    // pushPiece(this, null, offset.add(v2(0, 0.5 * dim.y)), offset_z, v2(dim.x + t, t), .zero, o.entity_z_c, color);
    //
    // pushPiece(this, null, offset.sub(v2(0.5 * dim.x, 0)), offset_z, v2(t, dim.y + t), .zero, o.entity_z_c, color);
    // pushPiece(this, null, offset.add(v2(0.5 * dim.x, 0)), offset_z, v2(t, dim.y + t), .zero, o.entity_z_c, color);
}

pub fn GetEntityBasisP(this: *const RenderGroup, entity_basis: *const EntityBasis, screen_center: V2) V2 {
    const entity_base_p = entity_basis.basis.p;

    const z_fudge = 1 + (0.1 * (entity_base_p.z + entity_basis.offset_z));

    const entity_ground_point = v2(
        screen_center.x + (this.meters_to_pixels * entity_base_p.x * z_fudge),
        screen_center.y - (this.meters_to_pixels * entity_base_p.y * z_fudge),
    );

    const entity_z = this.meters_to_pixels * -entity_base_p.z;
    // const entity_z = 0;

    const center = v2(
        entity_ground_point.x + entity_basis.offset.x,
        entity_ground_point.y + entity_basis.offset.y + (entity_basis.entity_z_c * entity_z),
    );

    return center;
}

pub fn toOutput(this: *RenderGroup, output_target: *const LoadedBitmap) void {
    const output_center = v2(
        @floatFromInt(@divTrunc(output_target.width, 2)),
        @floatFromInt(@divTrunc(output_target.height, 2)),
    );

    var base_address: usize = 0;
    while (base_address < this.push_buffer_size) {
        const header: *RenderGroup.EntryHeader = @ptrCast(@alignCast(&this.push_buffer[base_address]));

        switch (header.type) {
            .EntryClear => {
                const entry: *EntryClear = @alignCast(@fieldParentPtr("header", header));

                base_address += @sizeOf(@TypeOf(entry.*));
            },

            .EntryBitmap => {
                const entry: *EntryBitmap = @alignCast(@fieldParentPtr("header", header));
                const p = this.GetEntityBasisP(&entry.entity_basis, output_center);

                drawBitmap(output_target, entry.bitmap, p.x, p.y, entry.a);

                base_address += @sizeOf(@TypeOf(entry.*));
            },

            .EntryRectangle => {
                const entry: *EntryRectangle = @alignCast(@fieldParentPtr("header", header));
                const p = this.GetEntityBasisP(&entry.entity_basis, output_center);

                drawRectangle(
                    output_target,
                    p,
                    p.add(entry.dim),
                    entry.r,
                    entry.g,
                    entry.b,
                );

                base_address += @sizeOf(@TypeOf(entry.*));
            },
        }
    }
}

pub fn drawRectangle(buffer: *const LoadedBitmap, min: V2, max: V2, r: f32, g: f32, b: f32) void {
    const pitch: usize = @intCast(buffer.pitch);
    const bpp: usize = @intCast(LoadedBitmap.bytes_per_pixel);

    const buffer_width_f: f32 = @floatFromInt(buffer.width);
    const buffer_height_f: f32 = @floatFromInt(buffer.height);

    const minx: usize = @round(@min(@max(min.x, 0), buffer_width_f));
    const miny: usize = @round(@min(@max(min.y, 0), buffer_height_f));
    const maxx: usize = @round(@min(@max(max.x, 0), buffer_width_f));
    const maxy: usize = @round(@min(@max(max.y, 0), buffer_height_f));

    assert(bpp == @sizeOf(u32));

    const color = ColorU8ARGB.fromF32RGB(r, g, b);

    var row: [*]u8 = @as([*]u8, @ptrCast(buffer.memory)) + (minx * bpp) + (miny * pitch);
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

pub fn drawBitmap(buffer: *const LoadedBitmap, bitmap: *const LoadedBitmap, px: f32, py: f32, c_alpha: f32) void {
    const bpp = LoadedBitmap.bytes_per_pixel;

    const real_x: f32 = px;
    const real_y: f32 = py;

    var min_x: i32 = @round(real_x);
    var min_y: i32 = @round(real_y);
    var max_x: i32 = min_x + @as(i32, @intCast(bitmap.width));
    var max_y: i32 = min_y + @as(i32, @intCast(bitmap.height));

    var source_offset_x: i32 = 0;
    if (min_x < 0) {
        source_offset_x = @intCast(-min_x);
        min_x = 0;
    }

    var source_offset_y: i32 = 0;
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

    max_x = @intCast(@max(0, max_x));
    max_y = @intCast(@max(0, max_y));

    // TEMPORARY
    if (bitmap.width == 0 or bitmap.height == 0) return;
    // TEMPORARY

    const source_offset: usize = @bitCast(@as(isize, @intCast(source_offset_y * bitmap.pitch + bpp * source_offset_x)));
    var source_row: [*]u8 = @as([*]u8, @ptrCast(bitmap.memory)) + source_offset;

    const dest_offset: usize = @bitCast(@as(isize, @intCast((min_x * bpp) + (min_y * buffer.pitch))));
    var dest_row: [*]u8 = @as([*]u8, @ptrCast(buffer.memory)) + dest_offset;

    var y: usize = @intCast(min_y);
    while (y < max_y) : (y += 1) {
        var source: [*]align(1) u32 = @ptrCast(source_row);
        var dest: [*]align(1) u32 = @ptrCast(dest_row);

        var x: usize = @intCast(min_x);
        while (x < max_x) : (x += 1) {
            const sc = ColorU8ARGB.fromU32(source[0]);
            const dc = ColorU8ARGB.fromU32(dest[0]);

            const sa: f32 = sc.a;
            const rsa: f32 = (sa / 255) * c_alpha;
            const sr: f32 = c_alpha * sc.r;
            const sg: f32 = c_alpha * sc.g;
            const sb: f32 = c_alpha * sc.b;

            const da: f32 = dc.a;
            const dr: f32 = dc.r;
            const dg: f32 = dc.g;
            const db: f32 = dc.b;
            const rda: f32 = (da / 255);

            const inv_rsa: f32 = 1 - rsa;
            const a: f32 = 255 * (rsa + rda - (rsa * rda));
            const r: f32 = inv_rsa * dr + sr;
            const g: f32 = inv_rsa * dg + sg;
            const b: f32 = inv_rsa * db + sb;

            // dest[0] = (ColorU8ARGB{
            //     .r = @intFromFloat(r + 0.5),
            //     .g = @intFromFloat(g + 0.5),
            //     .b = @intFromFloat(b + 0.5),
            //     .a = @intFromFloat(a + 0.5),
            // }).asU32();

            dest[0] =
                @as(u32, @bitCast(@as(i32, @intFromFloat(a + 0.5)))) << 24 |
                @as(u32, @bitCast(@as(i32, @intFromFloat(r + 0.5)))) << 16 |
                @as(u32, @bitCast(@as(i32, @intFromFloat(g + 0.5)))) << 8 |
                @as(u32, @bitCast(@as(i32, @intFromFloat(b + 0.5)))) << 0;

            source += 1;
            dest += 1;
        }

        dest_row += @bitCast(@as(isize, @intCast(buffer.pitch)));
        source_row += @bitCast(@as(isize, @intCast(bitmap.pitch)));
    }
}

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
            .a = 0,
        };
    }
};
