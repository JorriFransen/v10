const std = @import("std");
const vk = @import("vulkan");
const gfx = @import("../gfx.zig");
const math = @import("../math.zig");

const Device = gfx.Device;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

device: *Device,
vertex_buffer: vk.Buffer = .null_handle,
vertex_buffer_memory: vk.DeviceMemory = .null_handle,
vertex_count: u32,

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

pub fn create(device: *Device, vertices: []const Vertex) !@This() {
    const vkd = device.device;

    std.debug.assert(vertices.len >= 3);

    var this = @This(){
        .device = device,
        .vertex_count = @intCast(vertices.len),
    };

    const buffer_size: vk.DeviceSize = @sizeOf(Vertex) * vertices.len;
    this.vertex_buffer = try device.createBuffer(
        buffer_size,
        .{ .vertex_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        &this.vertex_buffer_memory,
    );

    const data = try vkd.mapMemory(this.vertex_buffer_memory, 0, buffer_size, .{}) orelse return error.vkMapMemoryFailed;

    const mapped: [*]Vertex = @ptrCast(@alignCast(data));
    @memcpy(mapped, vertices);

    vkd.unmapMemory(this.vertex_buffer_memory);

    return this;
}

pub fn destroy(this: *@This()) void {
    const vkd = this.device.device;
    vkd.destroyBuffer(this.vertex_buffer, null);
    vkd.freeMemory(this.vertex_buffer_memory, null);
}

pub fn bind(this: *const @This(), command_buffer: vk.CommandBuffer) void {
    const vkd = this.device.device;
    const buffers = [_]vk.Buffer{this.vertex_buffer};
    const offsets = [_]vk.DeviceSize{0};
    vkd.cmdBindVertexBuffers(command_buffer, 0, 1, &buffers, &offsets);
}

pub fn draw(this: *const @This(), command_buffer: vk.CommandBuffer) void {
    const vkd = this.device.device;
    vkd.cmdDraw(command_buffer, this.vertex_count, 1, 0, 0);
}
