const std = @import("std");
const vk = @import("vulkan");
const gfx = @import("../gfx.zig");
const math = @import("../math.zig");
const tol = @import("../tinyobjloader/tiny_obj_loader.zig");
const mem = @import("../memory.zig");

const Model = @This();
const Device = gfx.Device;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

const assert = std.debug.assert;

device: *Device,
vertex_buffer: vk.Buffer = .null_handle,
vertex_buffer_memory: vk.DeviceMemory = .null_handle,
vertex_count: u32 = 0,

index_buffer: vk.Buffer = .null_handle,
index_buffer_memory: vk.DeviceMemory = .null_handle,
index_count: u32 = 0,
index_type: vk.IndexType = .none_khr,

pub const Vertex = struct {
    position: Vec3,
    color: Vec3,
    normal: Vec3 = Vec3.scalar(0),
    uv: Vec2 = Vec2.scalar(0),

    const field_count = @typeInfo(Vertex).@"struct".fields.len;
    pub const binding_description = vk.VertexInputBindingDescription{ .binding = 0, .stride = @sizeOf(Vertex), .input_rate = .vertex };
    pub const attribute_descriptions: [field_count]vk.VertexInputAttributeDescription = blk: {
        var result: [field_count]vk.VertexInputAttributeDescription = undefined;

        for (&result, 0..) |*desc, i| {
            const field_info = @typeInfo(Vertex).@"struct".fields[i];

            desc.* = .{
                .location = i,
                .binding = 0,
                .format = switch (field_info.type) {
                    else => @compileError(std.fmt.comptimePrint("Unhandled Vertex member type '{}'", .{field_info.type})),
                    Vec2 => .r32g32_sfloat,
                    Vec3 => .r32g32b32_sfloat,
                    Vec4 => .r32g32b32a32_sfloat,
                },
                .offset = @offsetOf(Vertex, field_info.name),
            };
        }
        break :blk result;
    };

    pub fn format(v: Vertex, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return writer.print("p({},{},{}), c({},{},{}), n({},{},{}), u({},{})", .{ v.position.x, v.position.y, v.position.z, v.color.x, v.color.y, v.color.z, v.normal.x, v.normal.y, v.normal.z, v.uv.x, v.uv.y });
    }
};

pub fn load(device: *Device, path: []const u8) !Model {
    const file_reader_callback = struct {
        pub fn f(ctx: ?*anyopaque, _file_name: [*c]const u8, is_mtl: c_int, _: [*c]const u8, out_buf: [*c][*c]u8, out_len: [*c]usize) callconv(.c) void {
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
    }.f;

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

    const shapes = _shapes[0..num_shapes];
    const vertex_indices = attribs.faces[0..attribs.num_faces];
    const vertices_per_face = attribs.face_num_verts[0..attribs.num_face_num_verts];
    const positions: []Vec3 = @as([*]Vec3, @ptrCast(attribs.vertices))[0..attribs.num_vertices];
    const normals: []Vec3 = @as([*]Vec3, @ptrCast(attribs.normals))[0..attribs.num_normals];
    const uvs: []Vec2 = @as([*]Vec2, @ptrCast(attribs.texcoords))[0..attribs.num_texcoords];

    var ta = mem.get_temp();
    defer ta.release();

    const num_faces: usize = attribs.num_face_num_verts;
    const num_vertices: usize = num_faces * 3;

    const vertices = try ta.allocator.alloc(Vertex, num_vertices);

    var total_faces: usize = 0;
    var total_vertices: usize = 0;

    std.log.debug("attribs: {}", .{attribs});

    for (shapes) |shape| {
        const shape_faces: usize = shape.length;

        for (0..shape_faces) |fi| {
            assert(shape.face_offset == total_faces);
            const face_vertices: usize = @intCast(vertices_per_face[shape.face_offset + fi]);
            assert(face_vertices == 3);

            const first_index = total_vertices;
            for (0..face_vertices) |vi| {
                const vertex_index = vertex_indices[first_index + vi];

                vertices[first_index + vi] = .{
                    .position = positions[@intCast(vertex_index.v_idx)],
                    .color = Vec3.scalar(1),
                    .normal = normals[@intCast(vertex_index.vn_idx)],
                    .uv = uvs[@intCast(vertex_index.vt_idx)],
                };
            }

            total_vertices += face_vertices;
        }
        total_faces += shape_faces;
    }

    assert(num_faces == total_faces);
    assert(num_vertices == total_vertices);

    return try create(device, vertices, void, null);
}

pub fn create(device: *Device, vertices: []const Vertex, comptime IndexType: type, indices_opt: ?[]const IndexType) !Model {
    const vkd = device.device;
    assert(vertices.len >= 3);

    var this = Model{
        .device = device,
        .vertex_count = @intCast(vertices.len),
    };

    const vertex_buffer_size: vk.DeviceSize = @sizeOf(@TypeOf(vertices[0])) * vertices.len;
    var vertex_staging_buffer_memory: vk.DeviceMemory = .null_handle;
    const vertex_staging_buffer = try device.createBuffer(
        vertex_buffer_size,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        &vertex_staging_buffer_memory,
    );
    defer {
        vkd.destroyBuffer(vertex_staging_buffer, null);
        vkd.freeMemory(vertex_staging_buffer_memory, null);
    }

    const vertex_data = try vkd.mapMemory(vertex_staging_buffer_memory, 0, vertex_buffer_size, .{}) orelse return error.vkMapMemoryFailed;
    const vertices_mapped: [*]Vertex = @ptrCast(@alignCast(vertex_data));
    @memcpy(vertices_mapped, vertices);
    vkd.unmapMemory(vertex_staging_buffer_memory);

    this.vertex_buffer = try device.createBuffer(
        vertex_buffer_size,
        .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .{ .device_local_bit = true },
        &this.vertex_buffer_memory,
    );

    device.copyBuffer(vertex_staging_buffer, this.vertex_buffer, vertex_buffer_size);

    if (IndexType != void) {
        const indices = indices_opt orelse @panic("Expected indices when IndexType is not void");
        assert(indices.len >= 3);

        this.index_count = @intCast(indices.len);
        this.index_type = switch (IndexType) {
            else => @compileError(std.fmt.comptimePrint("Invalid type for vulkan vertex index '{}'", .{IndexType})),
            u8 => .uint8_khr,
            u16 => .uint16,
            u32 => .uint32,
        };

        const index_buffer_size: vk.DeviceSize = @sizeOf(IndexType) * indices.len;
        var index_staging_buffer_memory: vk.DeviceMemory = .null_handle;
        const index_staging_buffer = try device.createBuffer(
            index_buffer_size,
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            &index_staging_buffer_memory,
        );
        defer {
            vkd.destroyBuffer(index_staging_buffer, null);
            vkd.freeMemory(index_staging_buffer_memory, null);
        }

        const index_data = try vkd.mapMemory(index_staging_buffer_memory, 0, index_buffer_size, .{}) orelse return error.vkMapMemoryFailed;
        const indices_mapped: [*]IndexType = @ptrCast(@alignCast(index_data));
        @memcpy(indices_mapped, indices);
        vkd.unmapMemory(index_staging_buffer_memory);

        this.index_buffer = try device.createBuffer(
            index_buffer_size,
            .{ .transfer_dst_bit = true, .index_buffer_bit = true },
            .{ .device_local_bit = true },
            &this.index_buffer_memory,
        );

        device.copyBuffer(index_staging_buffer, this.index_buffer, index_buffer_size);
    } else {
        assert(indices_opt == null or indices_opt.?.len == 0);
    }

    return this;
}

pub fn destroy(this: *Model) void {
    const vkd = this.device.device;

    vkd.destroyBuffer(this.vertex_buffer, null);
    vkd.freeMemory(this.vertex_buffer_memory, null);

    if (this.index_type != .none_khr) {
        vkd.destroyBuffer(this.index_buffer, null);
        vkd.freeMemory(this.index_buffer_memory, null);
    }
}

pub fn bind(this: *const Model, command_buffer: vk.CommandBuffer) void {
    const vkd = this.device.device;
    const offsets = [_]vk.DeviceSize{0};

    const vertex_buffers = [_]vk.Buffer{this.vertex_buffer};
    vkd.cmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffers, &offsets);

    if (this.index_type != .none_khr) {
        vkd.cmdBindIndexBuffer(command_buffer, this.index_buffer, 0, this.index_type);
    }
}

pub fn draw(this: *const Model, command_buffer: vk.CommandBuffer) void {
    const vkd = this.device.device;

    if (this.index_type != .none_khr) {
        vkd.cmdDrawIndexed(command_buffer, this.index_count, 1, 0, 0, 0);
    } else {
        vkd.cmdDraw(command_buffer, this.vertex_count, 1, 0, 0);
    }
}
