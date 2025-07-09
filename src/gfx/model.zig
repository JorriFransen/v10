const std = @import("std");
const vk = @import("vulkan");
const gfx = @import("../gfx.zig");
const math = @import("../math.zig");
const mem = @import("memory");
const resource = @import("../resource.zig");
const obj_parser = @import("../obj_parser.zig");

const log = std.log.scoped(.model);

const Device = gfx.Device;
const Model = @This();
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

pub const Vertex = extern struct {
    position: Vec3,
    color: Vec3 = Vec3.scalar(1),
    normal: Vec3 = .{},
    texcoord: Vec2 = .{},

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
};

pub const LoadModelError = error{UnsupportedFileType} ||
    resource.LoadResourceError ||
    obj_parser.ObjParseError ||
    CreateModelError;

// TODO: Move this to resource.zig
pub fn load(device: *Device, name: []const u8) LoadModelError!Model {
    var ta = mem.get_temp();
    defer ta.release();

    const model_res = try resource.load(ta.allocator(), name);
    const model_file = switch (model_res) {
        .model_file => model_res.model_file,
    };

    switch (model_file.kind) {
        // else => return error.UnsupportedFileType,
        .obj => {
            var mta = mem.get_scratch(ta.arena);
            defer mta.release();

            const model = try obj_parser.parse(mta.allocator(), .{
                .buffer = model_file.data,
                .name = name,
            });
            ta.release(); // Free content

            const mv = model.vertices;
            const mc = model.colors;
            const mn = model.normals;
            const mt = model.texcoords;

            const MapContext = struct {
                pub inline fn hash(_: @This(), v: Vertex) u64 {
                    return std.hash.Wyhash.hash(0, &raw(v));
                }
                pub inline fn eql(_: @This(), va: Vertex, vb: Vertex) bool {
                    return std.mem.eql(u8, &raw(va), &raw(vb));
                }
                pub inline fn raw(v: Vertex) [@sizeOf(Vertex)]u8 {
                    return @bitCast(v);
                }
            };

            var unique_vertices = std.HashMap(Vertex, u32, MapContext, std.hash_map.default_max_load_percentage).init(ta.allocator());
            defer unique_vertices.deinit();

            const white = Vec3.scalar(1);
            var vertices = try ta.allocator().alloc(Vertex, model.indices.len);
            var indices = try ta.allocator().alloc(u32, model.indices.len);
            var face_count: usize = 0;
            var vertex_count: u32 = 0;
            var index_count: usize = 0;

            for (model.objects) |obj| {
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

                        const vertex = Vertex{ .position = v, .color = c, .normal = n, .texcoord = t };
                        if (!unique_vertices.contains(vertex)) {
                            try unique_vertices.put(vertex, vertex_count);
                            vertices[vertex_count] = vertex;
                            vertex_count += 1;
                        }

                        const vidx = unique_vertices.get(vertex).?;
                        indices[index_count] = vidx;
                        index_count += 1;
                    }
                }
            }

            assert(model.faces.len == face_count);

            return try create(device, buildIndexed(vertices, indices));
        },
    }
}

inline fn validIndexType(T: type) bool {
    return T == u32 or T == u16 or T == u8;
}

pub fn build(vertices: []const Vertex) Builder(void) {
    return .{ .vertices = vertices };
}

pub fn buildIndexed(vertices: []const Vertex, indices: anytype) blk_returntype: {
    // @compileLog(std.fmt.comptimePrint("@TypeOf(indices): -->{}<--", .{@TypeOf(indices)}));
    const err_fmt = "indices must be a slice of u32, u16 or u8. Found: '{}'";
    const err_args = .{@TypeOf(indices)};

    const ptr_info = @typeInfo(@TypeOf(indices));
    if (ptr_info != .pointer) @compileError(std.fmt.comptimePrint(err_fmt, err_args));
    const ChildType = switch (ptr_info.pointer.size) {
        .one => blk: {
            const array_info = @typeInfo(ptr_info.pointer.child);
            if (array_info != .array) @compileError(std.fmt.comptimePrint(err_fmt, err_args));
            break :blk array_info.array.child;
        },
        .slice => ptr_info.pointer.child,
        .many, .c => @compileError(std.fmt.comptimePrint(err_fmt, err_args)),
    };

    const child_info = @typeInfo(ChildType);

    if (child_info != .int or !validIndexType(ChildType)) @compileError(std.fmt.comptimePrint(err_fmt, err_args));

    break :blk_returntype Builder(ChildType);
} {
    return .{ .vertices = vertices, .indices = indices };
}

pub fn Builder(comptime IT: type) type {
    return struct {
        pub const IndexType = IT;
        vertices: []const Vertex,
        indices: ?[]const IndexType = null,
    };
}

pub const CreateModelError = error{
    VulkanUnexpected,
    VulkanMapMemory,
};

pub fn create(device: *Device, builder: anytype) CreateModelError!Model {
    const IndexType = @TypeOf(builder).IndexType;
    assert(builder.vertices.len >= 3);

    const vkd = device.device;

    var this = Model{
        .device = device,
        .vertex_count = @intCast(builder.vertices.len),
    };

    const vertex_buffer_size: vk.DeviceSize = @sizeOf(@TypeOf(builder.vertices[0])) * builder.vertices.len;
    var vertex_staging_buffer_memory: vk.DeviceMemory = .null_handle;
    const vertex_staging_buffer = device.createBuffer(
        vertex_buffer_size,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        &vertex_staging_buffer_memory,
    ) catch return error.VulkanUnexpected;
    defer {
        vkd.destroyBuffer(vertex_staging_buffer, null);
        vkd.freeMemory(vertex_staging_buffer_memory, null);
    }

    const vertex_data_opt = vkd.mapMemory(vertex_staging_buffer_memory, 0, vertex_buffer_size, .{}) catch
        return error.VulkanMapMemory;
    const vertex_data = vertex_data_opt orelse return error.VulkanMapMemory;

    const vertices_mapped: [*]Vertex = @ptrCast(@alignCast(vertex_data));
    @memcpy(vertices_mapped, builder.vertices);
    vkd.unmapMemory(vertex_staging_buffer_memory);

    this.vertex_buffer = device.createBuffer(
        vertex_buffer_size,
        .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .{ .device_local_bit = true },
        &this.vertex_buffer_memory,
    ) catch return error.VulkanUnexpected;

    device.copyBuffer(vertex_staging_buffer, this.vertex_buffer, vertex_buffer_size);

    if (builder.indices) |indices| {
        assert(indices.len >= 3);

        this.index_count = @intCast(indices.len);
        this.index_type = switch (IndexType) {
            else => @panic(std.fmt.comptimePrint("Invalid type for vulkan vertex index '{}'", .{IndexType})),
            u8 => .uint8_khr,
            u16 => .uint16,
            u32 => .uint32,
        };

        const index_buffer_size: vk.DeviceSize = @sizeOf(IndexType) * indices.len;
        var index_staging_buffer_memory: vk.DeviceMemory = .null_handle;
        const index_staging_buffer = device.createBuffer(
            index_buffer_size,
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            &index_staging_buffer_memory,
        ) catch return error.VulkanUnexpected;
        defer {
            vkd.destroyBuffer(index_staging_buffer, null);
            vkd.freeMemory(index_staging_buffer_memory, null);
        }

        const index_data_opt = vkd.mapMemory(index_staging_buffer_memory, 0, index_buffer_size, .{}) catch return error.VulkanMapMemory;
        const index_data = index_data_opt orelse return error.VulkanMapMemory;

        const indices_mapped: [*]IndexType = @ptrCast(@alignCast(index_data));
        @memcpy(indices_mapped, indices);
        vkd.unmapMemory(index_staging_buffer_memory);

        this.index_buffer = device.createBuffer(
            index_buffer_size,
            .{ .transfer_dst_bit = true, .index_buffer_bit = true },
            .{ .device_local_bit = true },
            &this.index_buffer_memory,
        ) catch return error.VulkanUnexpected;

        device.copyBuffer(index_staging_buffer, this.index_buffer, index_buffer_size);
    } else {
        assert(IndexType == void);
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
