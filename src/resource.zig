const std = @import("std");
const log = std.log.scoped(.Resource);
const mem = @import("memory");
const obj_parser = @import("obj_parser.zig");
const math = @import("math.zig");

const GpuModel = @import("gfx/gpu_model.zig");
const Allocator = std.mem.Allocator;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

const assert = std.debug.assert;

pub const ResourceData = union(enum) {
    model_file: struct {
        pub const Kind = enum {
            obj,
        };

        kind: Kind,
        name: []const u8,
        data: []const u8,
    },
    cpu_model: struct {
        vertices: []GpuModel.Vertex,
        indices: []u32,
    },
};

pub const LoadResourceError = error{
    OutOfMemory,
    UnsupportedFileExtension,
    UnexpectedResourceKind,
} || std.fs.File.OpenError;

/// Load named resource into memory
pub fn load(allocator: Allocator, identifier: []const u8) LoadResourceError!ResourceData {
    const file = std.fs.cwd().openFile(identifier, .{}) catch |err| switch (err) {
        else => return err,
        error.FileNotFound => {
            log.err("Unable to open resource file: '{s}'", .{identifier});
            return error.FileNotFound;
        },
    };
    defer file.close();

    const file_size = file.getEndPos() catch return error.Unexpected;

    var file_buf = allocator.alloc(u8, file_size + 1) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };

    const read_size = file.readAll(file_buf) catch return error.Unexpected;
    assert(file_size == read_size);
    file_buf[read_size] = 0;
    file_buf = file_buf[0..file_size];

    const kind = if (std.mem.endsWith(u8, identifier, ".obj"))
        .obj
    else
        return error.UnsupportedFileExtension;

    return .{ .model_file = .{ .kind = kind, .name = identifier, .data = file_buf } };
}

pub const LoadModelError = error{UnsupportedFileType} ||
    LoadResourceError ||
    obj_parser.ObjParseError;

pub const LoadCpuModelOptions = union(enum) {
    from_identifier: []const u8,
    from_resource: ResourceData,
};

pub fn loadCpuModel(allocator: Allocator, options: LoadCpuModelOptions) LoadModelError!@FieldType(ResourceData, "cpu_model") {
    var ta = mem.get_scratch(@alignCast(@ptrCast(allocator.ptr)));
    defer ta.release();

    const model_file = mfb: switch (options) {
        .from_identifier => |identifier| {
            const model_file_res = try load(ta.allocator(), identifier);
            switch (model_file_res) {
                else => return error.UnexpectedResourceKind,
                .model_file => |mf| break :mfb mf,
            }
        },
        .from_resource => |res| switch (res) {
            else => return error.UnexpectedResourceKind,
            .model_file => |mf| break :mfb mf,
        },
    };

    switch (model_file.kind) {
        .obj => {
            var mta = mem.get_scratch(ta.arena);
            defer mta.release();

            const obj_model = try obj_parser.parse(mta.allocator(), .{
                .buffer = model_file.data,
                .name = model_file.name,
            });
            ta.release(); // Free content

            const mv = obj_model.vertices;
            const mc = obj_model.colors;
            const mn = obj_model.normals;
            const mt = obj_model.texcoords;

            const MapContext = struct {
                const Vertex = GpuModel.Vertex;
                pub inline fn hash(_: @This(), v: Vertex) u64 {
                    return std.hash.Wyhash.hash(0, &@as([@sizeOf(Vertex)]u8, @bitCast(v)));
                }
                pub inline fn eql(_: @This(), va: Vertex, vb: Vertex) bool {
                    return va.position.eql_eps(vb.position) and
                        va.color.eql_eps(vb.color) and
                        va.normal.eql_eps(vb.normal) and
                        va.texcoord.eql_eps(vb.texcoord);
                }
            };

            var unique_vertices = std.HashMap(GpuModel.Vertex, u32, MapContext, std.hash_map.default_max_load_percentage).init(ta.allocator());
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

                        const vertex = GpuModel.Vertex{ .position = v, .color = c, .normal = n, .texcoord = t };
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

            var vertices = try allocator.alloc(GpuModel.Vertex, unique_vertices.count());
            var it = unique_vertices.iterator();
            while (it.next()) |entry| {
                vertices[entry.value_ptr.*] = entry.key_ptr.*;
            }

            assert(indices.len == index_count);
            assert(vertices.len == vertex_count);
            return .{ .vertices = vertices, .indices = indices };
        },
    }
}
