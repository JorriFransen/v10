const std = @import("std");
const vk = @import("vulkan");
const gfx = @import("../gfx.zig");
const stb = @import("../stb/stb.zig");
const mem = @import("memory");
const resource = @import("../resource.zig");

const Texture = @This();
const Device = gfx.Device;

const assert = std.debug.assert;

image: vk.Image = .null_handle,
image_memory: vk.DeviceMemory = .null_handle,

// TODO: Define error
pub fn load(device: *Device, name: []const u8) !Texture {
    const vkd = &device.device;

    var ta = mem.get_temp();
    defer ta.release();

    // const texture_file = try resource.load(ta.allocator(), name);
    // const cpu_texture = try resource.loadCpuTexture(ta.allocator(), .{ .from_resource = texture_file });
    const cpu_texture = try resource.loadCpuTexture(ta.allocator(), .{ .from_identifier = name });

    var staging_buffer_memory: vk.DeviceMemory = .null_handle;
    const staging_buffer = try device.createBuffer(
        cpu_texture.data.len,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        &staging_buffer_memory,
    );
    defer {
        vkd.destroyBuffer(staging_buffer, null);
        vkd.freeMemory(staging_buffer_memory, null);
    }

    const staging_data_opt = try vkd.mapMemory(staging_buffer_memory, 0, cpu_texture.data.len, .{});
    const staging_data = staging_data_opt orelse return error.VulkanMapMemory;
    const staging_mapped = @as([*]u8, @ptrCast(staging_data))[0..cpu_texture.data.len];
    @memcpy(staging_mapped, cpu_texture.data);
    vkd.unmapMemory(staging_buffer_memory);

    var image_mem: vk.DeviceMemory = .null_handle;
    const image = try device.createImageWithInfo(
        &.{
            .image_type = .@"2d",
            .extent = .{ .width = cpu_texture.size.x, .height = cpu_texture.size.y, .depth = 1 },
            .mip_levels = 1,
            .array_layers = 1,
            .format = .r8g8b8a8_srgb,
            .tiling = .optimal,
            .initial_layout = .undefined,
            .usage = .{ .transfer_dst_bit = true, .sampled_bit = true },
            .sharing_mode = .exclusive,
            .samples = .{ .@"1_bit" = true },
            .flags = .{},
        },
        .{ .device_local_bit = true },
        &image_mem,
    );

    const cb = device.beginSingleTimeCommands();
    device.transitionImageLayout(&cb, image, .r8g8b8a8_srgb, .undefined, .transfer_dst_optimal);
    device.copyBufferToImage(&cb, staging_buffer, image, cpu_texture.size.x, cpu_texture.size.y);
    device.transitionImageLayout(&cb, image, .r8g8b8a8_srgb, .transfer_dst_optimal, .shader_read_only_optimal);
    device.endSingleTimeCommands(cb);

    return .{
        .image = image,
        .image_memory = image_mem,
    };
}

pub fn deinit(this: *Texture, device: *Device) void {
    const vkd = &device.device;

    vkd.destroyImage(this.image, null);
    vkd.freeMemory(this.image_memory, null);
}
