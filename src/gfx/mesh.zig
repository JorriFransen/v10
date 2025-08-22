const std = @import("std");
const res = @import("../resource.zig");
const gfx = @import("../gfx.zig");
const mem = @import("memory");
const obj_parser = @import("../obj_parser.zig");
const math = @import("../math.zig");

/// CPU-side model
const Mesh = @This();
const Model = gfx.Model;
const Allocator = std.mem.Allocator;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;

const assert = std.debug.assert;
const log = std.log.scoped(.mesh);

vertices: []Model.Vertex,
indices: []u32,

pub const LoadError =
    res.LoadError ||
    obj_parser.ObjParseError ||
    error{OutOfMemory};

pub fn load(allocator: Allocator, name: []const u8) LoadError!Mesh {
    var tmp = mem.get_scratch(@ptrCast(@alignCast(allocator.ptr)));
    defer tmp.release();

    const resource = try res.load(tmp.allocator(), name);
    switch (resource.type) {
        .obj => {}, // ok
        else => {
            log.err("Invalid resource type for model: '{s}' ({s})", .{ name, @tagName(resource.type) });
            return error.UnsupportedType;
        },
    }

    var parse_tmp = mem.get_scratch(tmp.arena);
    defer parse_tmp.release();

    const obj_model = try obj_parser.parse(parse_tmp.allocator(), .{ .buffer = resource.data, .name = name });
    // Free the resource data
    tmp.release();

    const mv = obj_model.vertices;
    const mc = obj_model.colors;
    const mn = obj_model.normals;
    const mt = obj_model.texcoords;

    const MapContext = struct {
        const Vertex = Model.Vertex;
        pub inline fn hash(_: @This(), v: Vertex) u64 {
            return std.hash.Wyhash.hash(0, &@as([@sizeOf(Vertex)]u8, @bitCast(v)));
        }
        pub inline fn eql(_: @This(), va: Vertex, vb: Vertex) bool {
            return va.position.eqlEps(vb.position) and
                va.color.eqlEps(vb.color) and
                va.normal.eqlEps(vb.normal) and
                va.texcoord.eqlEps(vb.texcoord);
        }
    };

    const VertexMap = std.HashMap(Model.Vertex, u32, MapContext, std.hash_map.default_max_load_percentage);
    var unique_vertices = VertexMap.init(tmp.allocator());
    try unique_vertices.ensureTotalCapacity(@intCast(mv.len));
    defer unique_vertices.deinit();

    const white = Vec3.scalar(1);
    var indices = try allocator.alloc(u32, obj_model.indices.len);
    var face_count: usize = 0;
    var vertex_count: u32 = 0;
    var index_count: usize = 0;

    for (obj_model.objects) |obj| {
        for (obj.faces) |face| {
            face_count += 1;

            assert(face.indices.len == 3);
            inline for (face.indices[0..3]) |idx| {
                var v = Vec3.v(mv[idx.vertex]);

                // Transform from the default blender export coordinate system to v10
                v.z = -v.z;

                var n: Vec3 = if (idx.normal < mn.len) Vec3.v(mn[idx.normal]) else .{};

                // Transform from the default blender export coordinate system to v10
                n.z = -n.z;

                const c: Vec3 = if (idx.vertex < mc.len) Vec3.v(mc[idx.vertex]) else white;
                const t: Vec2 = if (idx.texcoord < mt.len) Vec2.v(mt[idx.texcoord]) else .{};

                const vertex = Model.Vertex{ .position = v, .color = c, .normal = n, .texcoord = t };
                if (!unique_vertices.contains(vertex)) {
                    try unique_vertices.put(vertex, vertex_count);
                    vertex_count += 1;
                }

                const vidx = unique_vertices.get(vertex).?;
                indices[index_count] = vidx;
                index_count += 1;
            }
        }
    }

    assert(obj_model.faces.len == face_count);
    assert(obj_model.indices.len == index_count);
    assert(obj_model.vertices.len <= vertex_count);
    assert(obj_model.indices.len >= vertex_count);

    var vertices = try allocator.alloc(Model.Vertex, unique_vertices.count());
    var it = unique_vertices.iterator();
    while (it.next()) |entry| {
        vertices[entry.value_ptr.*] = entry.key_ptr.*;
    }

    assert(indices.len == index_count);
    assert(vertices.len == vertex_count);
    return .{ .vertices = vertices, .indices = indices };
}
