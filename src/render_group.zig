const std = @import("std");

const v10 = @import("v10.zig");
const LoadedBitmap = v10.LoadedBitmap;
const GameState = v10.GameState;

const MemoryArena = @import("arena.zig");

const common = @import("v10_common");
const intrinsics = @import("intrinsics.zig");

const math = @import("math");
const Color = math.Color;
const V2 = math.V2;
const v2 = V2.init;
const V3 = math.V3;
const V4 = math.V4;
const v4 = V4.init;

const RenderGroup = @This();

const push_buffer_align = 8;

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
        EntryRectangleOutline,
        EntryCoordinateSystem,
        // Names must match struct names!
    };

    type: Type align(push_buffer_align),
};

pub const EntryClear = extern struct {
    header: EntryHeader,

    color: Color,
};

pub const EntryCoordinateSystem = extern struct {
    header: EntryHeader,

    origin: V2,
    x_axis: V2,
    y_axis: V2,

    color: Color,
    texture: *const LoadedBitmap,
};

pub const EntryBitmap = extern struct {
    header: EntryHeader,

    entity_basis: EntityBasis,
    bitmap: *const LoadedBitmap,

    color: Color,
};

pub const EntryRectangle = extern struct {
    header: EntryHeader,
    entity_basis: EntityBasis,

    color: Color,
    dim: V2,
};

pub const EntryRectangleOutline = extern struct {
    header: EntryHeader,
    entity_basis: EntityBasis,

    color: Color,
    dim: V2,
    thickness: f32,
};

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

pub inline fn clear(this: *RenderGroup, color: Color) void {
    if (this.pushRenderElement(EntryClear)) |piece| {
        piece.color = color;
    }
}

pub inline fn coordinateSystem(this: *RenderGroup, origin: V2, x_axis: V2, y_axis: V2, color: Color, texture: *const LoadedBitmap) ?*EntryCoordinateSystem {
    var result: ?*EntryCoordinateSystem = null;

    if (this.pushRenderElement(EntryCoordinateSystem)) |entry| {
        entry.origin = origin;
        entry.x_axis = x_axis;
        entry.y_axis = y_axis;
        entry.color = color;
        entry.texture = texture;

        result = entry;
    }

    return result;
}

pub inline fn pushPiece(
    this: *RenderGroup,
    bitmap: *const LoadedBitmap,
    offset: V2,
    offset_z: f32,
    @"align": V2,
    entity_z_c: f32,
    color: Color,
) void {
    if (this.pushRenderElement(EntryBitmap)) |piece| {
        piece.entity_basis.basis = this.default_basis;
        piece.entity_basis.offset = v2(offset.x, -offset.y).mul(this.meters_to_pixels).sub(@"align");
        piece.entity_basis.offset_z = offset_z;
        piece.entity_basis.entity_z_c = entity_z_c;
        piece.bitmap = bitmap;
        piece.color = color;
    }
}

const PushBitmapOptions = struct {
    alpha: f32 = 1,
    entity_z_c: f32 = 1,
};

pub inline fn pushBitmap(this: *RenderGroup, bitmap: *const LoadedBitmap, offset: V2, offset_z: f32, @"align": V2, o: PushBitmapOptions) void {
    this.pushPiece(bitmap, offset, offset_z, @"align", o.entity_z_c, .rgba(1, 1, 1, o.alpha));
}

const PushRectOptions = struct {
    entity_z_c: f32 = 1,
};

pub inline fn pushRect(this: *RenderGroup, offset: V2, offset_z: f32, dim: V2, color: Color, o: PushRectOptions) void {
    if (this.pushRenderElement(EntryRectangle)) |piece| {
        const half_dim = dim.mul(this.meters_to_pixels * 0.5);

        piece.entity_basis.basis = this.default_basis;
        piece.entity_basis.offset = v2(offset.x, -offset.y).mul(this.meters_to_pixels).sub(half_dim);
        piece.entity_basis.offset_z = offset_z;
        piece.entity_basis.entity_z_c = o.entity_z_c;
        piece.color = color;
        piece.dim = dim.mul(this.meters_to_pixels);
    }
}

const PushRectOutlineOptions = struct {
    entity_z_c: f32 = 1,
    thickness: f32 = 0.1,
};

pub inline fn pushRectOutline(this: *RenderGroup, offset: V2, offset_z: f32, dim: V2, color: Color, o: PushRectOutlineOptions) void {
    const t: f32 = o.thickness;

    if (false) {
        this.pushRect(offset.sub(v2(0, 0.5 * dim.y)), offset_z, v2(dim.x + t, t), color, .{ .entity_z_c = o.entity_z_c });
        this.pushRect(offset.add(v2(0, 0.5 * dim.y)), offset_z, v2(dim.x + t, t), color, .{ .entity_z_c = o.entity_z_c });

        this.pushRect(offset.sub(v2(0.5 * dim.x, 0)), offset_z, v2(t, dim.y + t), color, .{ .entity_z_c = o.entity_z_c });
        this.pushRect(offset.add(v2(0.5 * dim.x, 0)), offset_z, v2(t, dim.y + t), color, .{ .entity_z_c = o.entity_z_c });
    } else {
        if (this.pushRenderElement(EntryRectangleOutline)) |piece| {
            const half_dim = dim.mul(this.meters_to_pixels * 0.5);

            piece.entity_basis.basis = this.default_basis;
            piece.entity_basis.offset = v2(offset.x, -offset.y).mul(this.meters_to_pixels).sub(half_dim);
            piece.entity_basis.offset_z = offset_z;
            piece.entity_basis.entity_z_c = o.entity_z_c;
            piece.color = color;
            piece.dim = dim.mul(this.meters_to_pixels);
            piece.thickness = t * this.meters_to_pixels;
        }
    }
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

                drawRectangle(output_target, .zero, .i(output_target.width, output_target.height), entry.color);

                base_address += @sizeOf(@TypeOf(entry.*));
            },

            .EntryBitmap => {
                const entry: *EntryBitmap = @alignCast(@fieldParentPtr("header", header));

                const p = this.GetEntityBasisP(&entry.entity_basis, output_center);

                drawBitmap(output_target, entry.bitmap, p.x, p.y, entry.color.a);

                base_address += @sizeOf(@TypeOf(entry.*));
            },

            .EntryRectangle => {
                const entry: *EntryRectangle = @alignCast(@fieldParentPtr("header", header));
                const p = this.GetEntityBasisP(&entry.entity_basis, output_center);

                drawRectangle(output_target, p, p.add(entry.dim), entry.color);

                base_address += @sizeOf(@TypeOf(entry.*));
            },

            .EntryRectangleOutline => {
                const entry: *EntryRectangleOutline = @alignCast(@fieldParentPtr("header", header));
                const p = this.GetEntityBasisP(&entry.entity_basis, output_center);

                const t = entry.thickness;
                const ht = entry.thickness / 2;

                const tl = p.add(v2(-ht, -ht));
                const tl_h_max = p.add(v2(entry.dim.x + ht, ht));
                const tl_v_max = tl.add(v2(t, entry.dim.y));

                drawRectangle(output_target, tl, tl_h_max, entry.color);
                drawRectangle(output_target, tl.add(v2(0, entry.dim.y)), tl_h_max.add(v2(0, entry.dim.y)), entry.color);

                drawRectangle(output_target, tl, tl_v_max, entry.color);
                drawRectangle(output_target, tl.add(v2(entry.dim.x, 0)), tl_v_max.add(v2(entry.dim.x, 0)), entry.color);

                _ = .{ tl, tl_h_max, tl_v_max };

                base_address += @sizeOf(@TypeOf(entry.*));
            },

            .EntryCoordinateSystem => {
                const entry: *EntryCoordinateSystem = @alignCast(@fieldParentPtr("header", header));

                drawRectangleSlowly(output_target, entry.origin, entry.x_axis, entry.y_axis, entry.color, entry.texture);

                const v_max = entry.origin.add(entry.x_axis).add(entry.y_axis);
                const color = Color.rgb(1, 1, 0);
                const op = entry.origin;
                const dim = v2(2, 2);

                drawRectangle(output_target, op.sub(dim), op.add(dim), color);

                const xp = entry.origin.add(entry.x_axis);
                drawRectangle(output_target, xp.sub(dim), xp.add(dim), color);

                const yp = entry.origin.add(entry.y_axis);
                drawRectangle(output_target, yp.sub(dim), yp.add(dim), color);

                drawRectangle(output_target, v_max.sub(dim), v_max.add(dim), color);

                base_address += @sizeOf(@TypeOf(entry.*));
            },
        }
    }
}

pub fn drawRectangle(buffer: *const LoadedBitmap, min: V2, max: V2, color: Color) void {
    const bpp = LoadedBitmap.bytes_per_pixel;

    var min_x: i32 = intrinsics.roundReal32ToInt32(min.x);
    var min_y: i32 = intrinsics.roundReal32ToInt32(min.y);
    var max_x: i32 = intrinsics.roundReal32ToInt32(max.x);
    var max_y: i32 = intrinsics.roundReal32ToInt32(max.y);

    if (min_x < 0) min_x = 0;
    if (min_y < 0) min_y = 0;
    if (max_x > buffer.width) max_x = buffer.width;
    if (max_y > buffer.height) max_y = buffer.height;

    const color_u32: u32 =
        (intrinsics.roundReal32ToUInt32(color.a * 255) << 24) |
        (intrinsics.roundReal32ToUInt32(color.r * 255) << 16) |
        (intrinsics.roundReal32ToUInt32(color.g * 255) << 8) |
        (intrinsics.roundReal32ToUInt32(color.b * 255) << 0);

    var row = intrinsics.ptrOffset(buffer.memory, (min_y * buffer.pitch) + (min_x * bpp));

    var y: i32 = min_y;
    while (y < max_y) : (y += 1) {
        var pixel: [*]u32 = @ptrCast(@alignCast(row));

        var x: i32 = min_x;
        while (x < max_x) : (x += 1) {
            pixel[0] = color_u32;
            pixel += 1;
        }

        row = intrinsics.ptrOffset(row, buffer.pitch);
    }
}

pub fn drawRectangleSlowly(buffer: *const LoadedBitmap, origin: V2, x_axis: V2, y_axis: V2, color: Color, texture: *const LoadedBitmap) void {
    const bpp = LoadedBitmap.bytes_per_pixel;

    const inv_x_axis_length_sq = 1 / x_axis.lengthSquared();
    const inv_y_axis_length_sq = 1 / y_axis.lengthSquared();

    const width_max = buffer.width - 1;
    const height_max = buffer.height - 1;

    var y_min: i32 = height_max;
    var y_max: i32 = 0;
    var x_min: i32 = width_max;
    var x_max: i32 = 0;

    const p: [4]V2 = .{ origin, origin.add(x_axis), origin.add(x_axis).add(y_axis), origin.add(y_axis) };
    inline for (p) |@"test"| {
        const floor_x: i32 = @floor(@"test".x);
        const ceil_x: i32 = @ceil(@"test".x);
        const floor_y: i32 = @floor(@"test".y);
        const ceil_y: i32 = @ceil(@"test".y);

        if (y_min > floor_y) y_min = floor_y;
        if (x_min > floor_x) x_min = floor_x;
        if (y_max < ceil_y) y_max = ceil_y;
        if (x_max < ceil_x) x_max = ceil_x;
    }

    if (x_min < 0) x_min = 0;
    if (y_min < 0) y_min = 0;
    if (x_max > width_max) x_max = width_max;
    if (y_max > height_max) y_max = height_max;

    var row = intrinsics.ptrOffset(buffer.memory, (x_min * bpp) + (y_min * buffer.pitch));

    var target_y: i32 = y_min;
    while (target_y < y_max) : (target_y += 1) {
        //
        var pixel: [*]u32 = @ptrCast(@alignCast(row));

        var target_x: i32 = x_min;
        while (target_x < x_max) : (target_x += 1) {
            //
            const pixel_p = V2.i(target_x, target_y);
            const d = pixel_p.sub(origin);

            const edge0 = d.inner(x_axis.perp().neg());
            const edge1 = d.sub(x_axis).inner(y_axis.perp().neg());
            const edge2 = d.sub(x_axis).sub(y_axis).inner(x_axis.perp());
            const edge3 = d.sub(y_axis).inner(y_axis.perp());

            if (edge0 < 0 and
                edge1 < 0 and
                edge2 < 0 and
                edge3 < 0)
            {
                const u = inv_x_axis_length_sq * d.inner(x_axis);
                const v = inv_y_axis_length_sq * d.inner(y_axis);

                assert(u >= 0 and u <= 1);
                assert(v >= 0 and v <= 1);

                const tx: f32 = u * @as(f32, @floatFromInt(texture.width - 2));
                const ty: f32 = v * @as(f32, @floatFromInt(texture.height - 2));

                const x: i32 = @trunc(tx);
                const y: i32 = @trunc(ty);

                const fx: f32 = tx - @as(f32, @floatFromInt(x));
                const fy: f32 = ty - @as(f32, @floatFromInt(y));

                assert(x >= 0 and x < texture.width);
                assert(y >= 0 and y < texture.height);

                const texel_ptr = intrinsics.ptrOffset(texture.memory, (y * texture.pitch) + (x * bpp));
                const texel_ptr_a = @as(*align(1) u32, @ptrCast(texel_ptr));
                const texel_ptr_b = intrinsics.ptrOffsetT(*align(1) u32, texel_ptr, bpp);
                const texel_ptr_c = intrinsics.ptrOffsetT(*align(1) u32, texel_ptr, texture.pitch);
                const texel_ptr_d = intrinsics.ptrOffsetT(*align(1) u32, texel_ptr, texture.pitch + bpp);

                const texel_a: Color = .rgba(
                    @as(f32, @floatFromInt((texel_ptr_a.* >> 16) & 0xff)),
                    @as(f32, @floatFromInt((texel_ptr_a.* >> 8) & 0xff)),
                    @as(f32, @floatFromInt((texel_ptr_a.* >> 0) & 0xff)),
                    @floatFromInt((texel_ptr_a.* >> 24) & 0xff),
                );
                const texel_b: Color = .rgba(
                    @as(f32, @floatFromInt((texel_ptr_b.* >> 16) & 0xff)),
                    @as(f32, @floatFromInt((texel_ptr_b.* >> 8) & 0xff)),
                    @as(f32, @floatFromInt((texel_ptr_b.* >> 0) & 0xff)),
                    @floatFromInt((texel_ptr_b.* >> 24) & 0xff),
                );
                const texel_c: Color = .rgba(
                    @as(f32, @floatFromInt((texel_ptr_c.* >> 16) & 0xff)),
                    @as(f32, @floatFromInt((texel_ptr_c.* >> 8) & 0xff)),
                    @as(f32, @floatFromInt((texel_ptr_c.* >> 0) & 0xff)),
                    @floatFromInt((texel_ptr_c.* >> 24) & 0xff),
                );
                const texel_d: Color = .rgba(
                    @as(f32, @floatFromInt((texel_ptr_d.* >> 16) & 0xff)),
                    @as(f32, @floatFromInt((texel_ptr_d.* >> 8) & 0xff)),
                    @as(f32, @floatFromInt((texel_ptr_d.* >> 0) & 0xff)),
                    @floatFromInt((texel_ptr_d.* >> 24) & 0xff),
                );

                const texel = Color.lerp(
                    Color.lerp(texel_a, fx, texel_b),
                    fy,
                    Color.lerp(texel_c, fx, texel_d),
                );

                const sa: f32 = texel.a;
                const sr: f32 = texel.r;
                const sg: f32 = texel.g;
                const sb: f32 = texel.b;

                const rsa: f32 = (sa / 255) * color.a;

                const da: f32 = @floatFromInt((pixel[0] >> 24) & 0xff);
                const dr: f32 = @floatFromInt((pixel[0] >> 16) & 0xff);
                const dg: f32 = @floatFromInt((pixel[0] >> 8) & 0xff);
                const db: f32 = @floatFromInt((pixel[0] >> 0) & 0xff);
                const rda: f32 = (da / 255);

                const inv_rsa: f32 = 1 - rsa;
                const a: f32 = 255 * (rsa + rda - (rsa * rda));
                const r: f32 = inv_rsa * dr + sr;
                const g: f32 = inv_rsa * dg + sg;
                const b: f32 = inv_rsa * db + sb;

                pixel[0] =
                    @as(u32, @bitCast(@as(i32, @intFromFloat(a + 0.5)))) << 24 |
                    @as(u32, @bitCast(@as(i32, @intFromFloat(r + 0.5)))) << 16 |
                    @as(u32, @bitCast(@as(i32, @intFromFloat(g + 0.5)))) << 8 |
                    @as(u32, @bitCast(@as(i32, @intFromFloat(b + 0.5)))) << 0;
            }

            pixel += 1;
        }

        row = intrinsics.ptrOffset(row, buffer.pitch);
    }
}

pub fn drawBitmap(buffer: *const LoadedBitmap, bitmap: *const LoadedBitmap, px: f32, py: f32, c_alpha: f32) void {
    const bpp = LoadedBitmap.bytes_per_pixel;

    const real_x: f32 = px;
    const real_y: f32 = py;

    var min_x: i32 = intrinsics.roundReal32ToInt32(real_x);
    var min_y: i32 = intrinsics.roundReal32ToInt32(real_y);
    var max_x: i32 = min_x + @as(i32, @intCast(bitmap.width));
    var max_y: i32 = min_y + @as(i32, @intCast(bitmap.height));

    var source_offset_x: i32 = 0;
    if (min_x < 0) {
        source_offset_x = -min_x;
        min_x = 0;
    }

    var source_offset_y: i32 = 0;
    if (min_y < 0) {
        source_offset_y = -min_y;
        min_y = 0;
    }

    if (max_x > buffer.width) {
        max_x = buffer.width;
    }

    if (max_y > buffer.height) {
        max_y = buffer.height;
    }

    max_x = @intCast(@max(0, max_x));
    max_y = @intCast(@max(0, max_y));

    var source_row = intrinsics.ptrOffset(bitmap.memory, (source_offset_y * bitmap.pitch) + (source_offset_x * bpp));
    var dest_row = intrinsics.ptrOffset(buffer.memory, (min_y * buffer.pitch) + (min_x * bpp));

    var y: usize = @intCast(min_y);
    while (y < max_y) : (y += 1) {
        var source: [*]align(1) u32 = @ptrCast(source_row);
        var dest: [*]align(1) u32 = @ptrCast(dest_row);

        var x: usize = @intCast(min_x);
        while (x < max_x) : (x += 1) {
            const sa: f32 = @floatFromInt((source[0] >> 24) & 0xff);
            const rsa: f32 = (sa / 255) * c_alpha;
            const sr: f32 = c_alpha * @as(f32, @floatFromInt((source[0] >> 16) & 0xff));
            const sg: f32 = c_alpha * @as(f32, @floatFromInt((source[0] >> 8) & 0xff));
            const sb: f32 = c_alpha * @as(f32, @floatFromInt((source[0] >> 0) & 0xff));

            const da: f32 = @floatFromInt((dest[0] >> 24) & 0xff);
            const dr: f32 = @floatFromInt((dest[0] >> 16) & 0xff);
            const dg: f32 = @floatFromInt((dest[0] >> 8) & 0xff);
            const db: f32 = @floatFromInt((dest[0] >> 0) & 0xff);
            const rda: f32 = (da / 255);

            const inv_rsa: f32 = 1 - rsa;
            const a: f32 = 255 * (rsa + rda - (rsa * rda));
            const r: f32 = inv_rsa * dr + sr;
            const g: f32 = inv_rsa * dg + sg;
            const b: f32 = inv_rsa * db + sb;

            dest[0] =
                @as(u32, @bitCast(@as(i32, @intFromFloat(a + 0.5)))) << 24 |
                @as(u32, @bitCast(@as(i32, @intFromFloat(r + 0.5)))) << 16 |
                @as(u32, @bitCast(@as(i32, @intFromFloat(g + 0.5)))) << 8 |
                @as(u32, @bitCast(@as(i32, @intFromFloat(b + 0.5)))) << 0;

            source += 1;
            dest += 1;
        }

        dest_row = intrinsics.ptrOffset(dest_row, buffer.pitch);
        source_row = intrinsics.ptrOffset(source_row, bitmap.pitch);
    }
}

pub fn assert(cond: bool) void {
    if (!cond) {
        @branchHint(.cold);
        std.debug.dumpCurrentStackTrace(.{ .first_address = @returnAddress() });
        @breakpoint();
    }
}
