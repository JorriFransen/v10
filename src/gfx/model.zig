const std = @import("std");
const vk = @import("vulkan");
const gfx = @import("../gfx.zig");
const math = @import("../math.zig");

const Device = gfx.Device;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const IndexType = u32;

const assert = std.debug.assert;

device: *Device,
vertex_buffer: vk.Buffer = .null_handle,
vertex_buffer_memory: vk.DeviceMemory = .null_handle,
vertex_count: u32 = 0,

use_index_buffer: bool = false,
index_buffer: vk.Buffer = .null_handle,
index_buffer_memory: vk.DeviceMemory = .null_handle,
index_count: u32 = 0,

pub const Vertex = struct {
    position: Vec3,
    color: Vec3,

    const field_count = @typeInfo(@This()).@"struct".fields.len;
    pub const binding_description = vk.VertexInputBindingDescription{ .binding = 0, .stride = @sizeOf(@This()), .input_rate = .vertex };
    pub const attribute_descriptions: [field_count]vk.VertexInputAttributeDescription = blk: {
        var result: [field_count]vk.VertexInputAttributeDescription = undefined;

        for (&result, 0..) |*desc, i| {
            const field_info = @typeInfo(@This()).@"struct".fields[i];

            desc.* = .{
                .location = i,
                .binding = 0,
                .format = switch (field_info.type) {
                    else => @compileError(std.fmt.comptimePrint("Unhandled Vertex member type '{}'", .{field_info.type})),
                    Vec2 => .r32g32_sfloat,
                    Vec3 => .r32g32b32_sfloat,
                    Vec4 => .r32g32b32a32_sfloat,
                },
                .offset = @offsetOf(@This(), field_info.name),
            };
        }
        break :blk result;
    };
};

pub fn create(device: *Device, vertices: []const Vertex, indices_opt: ?[]const IndexType) !@This() {
    const vkd = device.device;
    assert(vertices.len >= 3);

    var this = @This(){
        .device = device,
        .vertex_count = @intCast(vertices.len),
    };

    const vertex_buffer_size: vk.DeviceSize = @sizeOf(@TypeOf(vertices[0])) * vertices.len;
    this.vertex_buffer = try device.createBuffer(
        vertex_buffer_size,
        .{ .vertex_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        &this.vertex_buffer_memory,
    );
    const vertex_data = try vkd.mapMemory(this.vertex_buffer_memory, 0, vertex_buffer_size, .{}) orelse return error.vkMapMemoryFailed;
    const vertices_mapped: [*]Vertex = @ptrCast(@alignCast(vertex_data));
    @memcpy(vertices_mapped, vertices);
    vkd.unmapMemory(this.vertex_buffer_memory);

    if (indices_opt) |indices| {
        assert(indices.len >= 3);
        this.use_index_buffer = true;
        this.index_count = @intCast(indices.len);

        const index_buffer_size: vk.DeviceSize = @sizeOf(IndexType) * indices.len;
        this.index_buffer = try device.createBuffer(
            index_buffer_size,
            .{ .index_buffer_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            &this.index_buffer_memory,
        );
        const index_data = try vkd.mapMemory(this.index_buffer_memory, 0, index_buffer_size, .{}) orelse return error.vkMapMemoryFailed;
        const indices_mapped: [*]IndexType = @ptrCast(@alignCast(index_data));
        @memcpy(indices_mapped, indices);
        vkd.unmapMemory(this.index_buffer_memory);
    }

    return this;
}

pub fn destroy(this: *@This()) void {
    const vkd = this.device.device;

    vkd.destroyBuffer(this.vertex_buffer, null);
    vkd.freeMemory(this.vertex_buffer_memory, null);

    if (this.use_index_buffer) {
        vkd.destroyBuffer(this.index_buffer, null);
        vkd.freeMemory(this.index_buffer_memory, null);
    }
}

pub fn bind(this: *const @This(), command_buffer: vk.CommandBuffer) void {
    const vkd = this.device.device;
    const offsets = [_]vk.DeviceSize{0};

    const vertex_buffers = [_]vk.Buffer{this.vertex_buffer};
    vkd.cmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffers, &offsets);

    if (this.use_index_buffer) {
        // TODO: Don't hardcode .uint32
        vkd.cmdBindIndexBuffer(command_buffer, this.index_buffer, 0, .uint32);
    }
}

pub fn draw(this: *const @This(), command_buffer: vk.CommandBuffer) void {
    const vkd = this.device.device;

    if (this.use_index_buffer) {
        vkd.cmdDrawIndexed(command_buffer, this.index_count, 1, 0, 0, 0);
    } else {
        vkd.cmdDraw(command_buffer, this.vertex_count, 1, 0, 0);
    }
}
