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
};

pub fn Builder(comptime IndexType_: type) type {
    return struct {
        pub const IndexType = IndexType_;
        vertices: []Vertex,
        indices: ?[]IndexType,
    };
}

pub fn load(device: *Device, path: []const u8) !Model {
    var ta = mem.get_temp();
    defer ta.release();

    const builder = try tol.load(ta.arena, path);
    return create(device, @TypeOf(builder).IndexType, builder);
}

pub fn create(device: *Device, comptime IndexType: type, builder: Builder(IndexType)) !Model {
    const vkd = device.device;
    assert(builder.vertices.len >= 3);

    var this = Model{
        .device = device,
        .vertex_count = @intCast(builder.vertices.len),
    };

    const vertex_buffer_size: vk.DeviceSize = @sizeOf(@TypeOf(builder.vertices[0])) * builder.vertices.len;
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
    @memcpy(vertices_mapped, builder.vertices);
    vkd.unmapMemory(vertex_staging_buffer_memory);

    this.vertex_buffer = try device.createBuffer(
        vertex_buffer_size,
        .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .{ .device_local_bit = true },
        &this.vertex_buffer_memory,
    );

    device.copyBuffer(vertex_staging_buffer, this.vertex_buffer, vertex_buffer_size);

    if (builder.indices) |indices| {
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
