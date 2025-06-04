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

pub fn load(path: []const u8) !Model.Builder(u32) {
    return loadWithIndexType(path, u32);
}

pub fn loadWithIndexType(path: []const u8, comptime IndexType: type) !Model.Builder(IndexType) {
    var attribs: tol.tinyobj_attrib_t = undefined;
    var _shapes: [*]tol.tinyobj_shape_t = undefined;
    var num_shapes: usize = undefined;
    var materials: [*]tol.tinyobj_material_t = undefined;
    var num_materials: usize = undefined;

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

    var ta = mem.get_temp();
    defer ta.release();

    const vertices = try ta.allocator.alloc(Vertex, vertex_indices.len);

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
    _ = size;
    unreachable;
}

export fn tinyobj_calloc(num: usize, size: usize) ?*anyopaque {
    _ = num;
    _ = size;
    unreachable;
}

export fn tinyobj_free(ptr: ?*anyopaque) void {
    _ = ptr;
    unreachable;
}

export fn tinyobj_realloc(ptr: ?*anyopaque, new_size: usize) ?*anyopaque {
    _ = ptr;
    _ = new_size;
    unreachable;
}
