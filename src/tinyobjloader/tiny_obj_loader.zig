const std = @import("std");
const gfx = @import("../gfx.zig");
const math = @import("../math.zig");
const mem = @import("../memory.zig");

const Device = gfx.Device;
const Model = gfx.Model;
const Vertex = Model.Vertex;
const Builder = Model.Builder;
const Vec3 = math.Vec3;
const Vec2 = math.Vec2;

const assert = std.debug.assert;

const tol = @cImport({
    @cInclude("tiny_obj_loader.h");
});

var current_arena: ?*mem.Arena = null;

pub fn load(arena: *mem.Arena, path: []const u8) !Model.Builder(u32) {
    return loadWithIndexType(arena, path, u32);
}

pub fn loadWithIndexType(arena: *mem.Arena, path: []const u8, comptime IndexType: type) !Model.Builder(IndexType) {
    var attribs: tol.tinyobj_attrib_t = undefined;
    var _shapes: [*]tol.tinyobj_shape_t = undefined;
    var num_shapes: usize = undefined;
    var materials: [*]tol.tinyobj_material_t = undefined;
    var num_materials: usize = undefined;

    current_arena = arena;
    const parse_result = tol.tinyobj_parse_obj(
        &attribs,
        @ptrCast(&_shapes),
        &num_shapes,
        @ptrCast(&materials),
        &num_materials,
        path.ptr,
        file_reader_callback,
        null,
        tol.TINYOBJ_FLAG_TRIANGULATE,
    );
    assert(parse_result == tol.TINYOBJ_SUCCESS);

    const vertex_indices = attribs.faces[0..attribs.num_faces];
    const positions: []Vec3 = @as([*]Vec3, @ptrCast(attribs.vertices))[0..attribs.num_vertices];
    const normals: []Vec3 = @as([*]Vec3, @ptrCast(attribs.normals))[0..attribs.num_normals];
    const uvs: []Vec2 = @as([*]Vec2, @ptrCast(attribs.texcoords))[0..attribs.num_texcoords];

    const vertices = try arena.allocator().alloc(Vertex, vertex_indices.len);

    // This can't be done by shape(/face) since tol doesn't expose face count for triangulated shapes
    for (vertices, vertex_indices) |*vertex, vi| {
        vertex.* = .{
            .position = positions[@intCast(vi.v_idx)],
            .color = Vec3.scalar(1),
            .normal = normals[@intCast(vi.vn_idx)],
            .uv = uvs[@intCast(vi.vt_idx)],
        };
    }

    return Builder(IndexType){ .vertices = vertices, .indices = null };
}

pub fn file_reader_callback(ctx: ?*anyopaque, _file_name: [*c]const u8, is_mtl: c_int, _: [*c]const u8, out_buf: [*c][*c]u8, out_len: [*c]usize) callconv(.c) void {
    _ = ctx;

    const file_name = std.mem.span(_file_name);

    if (std.fs.cwd().openFile(file_name, .{})) |file| {
        defer file.close();
        const size = file.getEndPos() catch unreachable;
        const buflen = size + 1;

        // TODO: CLEANUP: Modify tinyobj to use a custom allocator (tinyobj_parse_obj calls free(c) on this buffer)
        const ptr = std.c.malloc(buflen).?;
        const buffer: []u8 = @as([*]u8, @ptrCast(ptr))[0..buflen];

        const read = file.readAll(buffer) catch unreachable;
        assert(size == read);
        buffer[read] = 0;

        out_buf.* = buffer.ptr;
        out_len.* = read;
    } else |_| {
        out_buf.* = null;
        out_len.* = 0;

        if (is_mtl == 1) {
            return; // Don't report error on missing mtl file
        }

        std.log.err("Unable to open file: '{s}'", .{file_name});
        @panic("Unable to open .obj file");
    }
}

export fn tinyobj_malloc(size: usize) ?*anyopaque {
    if (current_arena) |arena| {
        return arena.allocator().rawAlloc(size, .@"8", 0);
    } else {
        @panic("tinyobj_allocator null arena");
    }
}

export fn tinyobj_calloc(num: usize, size: usize) ?*anyopaque {
    if (current_arena) |arena| {
        const result = arena.allocator().rawAlloc(num * size, .@"8", 0);
        if (result) |r| @memset(r[0 .. num * size], 0);
        return result;
    } else {
        @panic("tinyobj_allocator null arena");
    }
}

export fn tinyobj_free(ptr: ?*anyopaque) void {
    if (current_arena) |arena| {
        const slice: []u8 = @as([*]u8, @ptrCast(ptr))[0..1];
        arena.allocator().rawFree(slice, .@"8", 0);
    } else {
        @panic("tinyobj_allocator null arena");
    }
}

export fn tinyobj_realloc(ptr_opt: ?*anyopaque, new_size: usize) ?*anyopaque {
    if (current_arena) |arena| {
        if (ptr_opt) |ptr| {
            const len = if (ptr == arena.last_allocation) arena.last_size else 1;
            const slice: []u8 = @as([*]u8, @ptrCast(ptr))[0..len];
            return arena.allocator().rawRemap(slice, .@"8", new_size, 0);
        } else {
            return arena.allocator().rawAlloc(new_size, .@"8", 0);
        }
    } else {
        @panic("tinyobj_allocator null arena");
    }
}
