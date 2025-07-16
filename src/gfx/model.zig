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

    // TODO: Make this external to enable reuse on different vertex structs
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

pub const LoadModelError =
    CreateModelError ||
    resource.LoadModelError;

pub fn load(device: *Device, name: []const u8) LoadModelError!Model {
    var ta = mem.get_temp();
    defer ta.release();

    const cpu_model = try resource.loadCpuModel(ta.allocator(), .{ .from_identifier = name });
    // const model_file = try resource.load(ta.allocator(), name);
    // const cpu_model = try resource.loadCpuModel(ta.allocator(), .{ .from_resource = model_file });
    return create(device, buildIndexed(cpu_model.vertices, cpu_model.indices));
    // return create(device, build(cpu_model.vertices));
}

pub fn deinit(this: *Model, device: *Device) void {
    const vkd = &device.device;

    vkd.destroyBuffer(this.vertex_buffer, null);
    vkd.freeMemory(this.vertex_buffer_memory, null);

    if (this.index_type != .none_khr) {
        vkd.destroyBuffer(this.index_buffer, null);
        vkd.freeMemory(this.index_buffer_memory, null);
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

    const vkd = &device.device;

    var this = Model{
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

    const cb = device.beginSingleTimeCommands();
    device.copyBuffer(cb, vertex_staging_buffer, this.vertex_buffer, vertex_buffer_size);

    var index_staging_buffer: vk.Buffer = .null_handle;
    var index_staging_buffer_memory: vk.DeviceMemory = .null_handle;

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
        index_staging_buffer = device.createBuffer(
            index_buffer_size,
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            &index_staging_buffer_memory,
        ) catch return error.VulkanUnexpected;

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

        device.copyBuffer(cb, index_staging_buffer, this.index_buffer, index_buffer_size);
    } else {
        assert(IndexType == void);
    }

    device.endSingleTimeCommands(cb);
    if (builder.indices != null) {
        vkd.destroyBuffer(index_staging_buffer, null);
        vkd.freeMemory(index_staging_buffer_memory, null);
    }

    return this;
}

pub fn bind(this: *const Model, cb: vk.CommandBufferProxy) void {
    const offsets = [_]vk.DeviceSize{0};

    const vertex_buffers = [_]vk.Buffer{this.vertex_buffer};
    cb.bindVertexBuffers(0, 1, &vertex_buffers, &offsets);

    if (this.index_type != .none_khr) {
        cb.bindIndexBuffer(this.index_buffer, 0, this.index_type);
    }
}

pub fn draw(this: *const Model, cb: vk.CommandBufferProxy) void {
    if (this.index_type != .none_khr) {
        cb.drawIndexed(this.index_count, 1, 0, 0, 0);
    } else {
        cb.draw(this.vertex_count, 1, 0, 0);
    }
}
