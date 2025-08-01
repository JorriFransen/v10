const std = @import("std");
const vk = @import("vulkan");
const gfx = @import("../gfx.zig");
const stb = @import("../stb/stb.zig");
const mem = @import("memory");
const resource = @import("../resource.zig");
const math = @import("../math.zig");

const Texture = @This();
const Device = gfx.Device;
const Vec2 = math.Vec2;

const log = std.log.scoped(.gpu_texture);
const assert = std.debug.assert;

image: vk.Image,
image_memory: vk.DeviceMemory,
image_view: vk.ImageView,
descriptor_set: vk.DescriptorSet,

width: u32,
height: u32,

// TODO: Define error
pub fn load(device: *Device, name: []const u8) !Texture {
    var ta = mem.get_temp();
    defer ta.release();

    // const texture_file = try resource.load(ta.allocator(), name);
    // const cpu_texture = try resource.loadCpuTexture(ta.allocator(), .{ .from_resource = texture_file });
    const cpu_texture = try resource.loadCpuTexture(ta.allocator(), .{ .from_identifier = name });
    log.info("Loaded cpu texture: '{s}' - {}x{}", .{ name, cpu_texture.size.x, cpu_texture.size.y });

    return try init(device, cpu_texture);
}

// TODO: Define error
pub fn init(device: *Device, cpu_texture: resource.CpuTexture) !Texture {
    const vkd = &device.device;

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

    const format = vk.Format.r8g8b8a8_srgb;

    var image_mem: vk.DeviceMemory = .null_handle;
    const image = try device.createImageWithInfo(
        &.{
            .image_type = .@"2d",
            .extent = .{ .width = cpu_texture.size.x, .height = cpu_texture.size.y, .depth = 1 },
            .mip_levels = 1,
            .array_layers = 1,
            .format = format,
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
    device.transitionImageLayout(cb, image, .r8g8b8a8_srgb, .undefined, .transfer_dst_optimal);
    device.copyBufferToImage(cb, staging_buffer, image, cpu_texture.size.x, cpu_texture.size.y);
    device.transitionImageLayout(cb, image, .r8g8b8a8_srgb, .transfer_dst_optimal, .shader_read_only_optimal);
    device.endSingleTimeCommands(cb);

    const image_view = try device.createImageView(image, format);

    const descriptor_set = try createDescriptorSet(device, image_view);

    return .{
        .image = image,
        .image_memory = image_mem,
        .image_view = image_view,
        .descriptor_set = descriptor_set,
        .width = cpu_texture.size.x,
        .height = cpu_texture.size.y,
    };
}

pub fn deinit(this: *Texture, device: *Device) void {
    const vkd = &device.device;

    vkd.destroyImage(this.image, null);
    vkd.freeMemory(this.image_memory, null);
    vkd.destroyImageView(this.image_view, null);
}

fn createDescriptorSet(device: *Device, image_view: vk.ImageView) !vk.DescriptorSet {
    const vkd = &device.device;

    const alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = device.descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast(&device.linear_sampler_layout),
    };

    var result: vk.DescriptorSet = .null_handle;
    try vkd.allocateDescriptorSets(&alloc_info, @ptrCast(&result));

    const image_info = vk.DescriptorImageInfo{
        .image_layout = .shader_read_only_optimal,
        .image_view = image_view,
        .sampler = device.linear_sampler,
    };

    const descriptor_writes = vk.WriteDescriptorSet{
        .dst_set = result,
        .dst_binding = 0,
        .dst_array_element = 0,
        .descriptor_type = .combined_image_sampler,
        .descriptor_count = 1,
        .p_image_info = @ptrCast(&image_info),
        .p_buffer_info = undefined,
        .p_texel_buffer_view = undefined,
    };

    vkd.updateDescriptorSets(1, @ptrCast(&descriptor_writes), 0, null);

    return result;
}

pub fn bind(this: *const Texture, cb: vk.CommandBufferProxy, layout: vk.PipelineLayout) void {
    cb.bindDescriptorSets(.graphics, layout, 0, 1, @ptrCast(&this.descriptor_set), 0, null);
}

pub inline fn getSize(this: *const Texture) Vec2 {
    return .{ .x = @floatFromInt(this.width), .y = @floatFromInt(this.height) };
}

// TODO: Define error
pub fn initDefaultWhite(device: *Device) !Texture {
    const cpu_texture = resource.CpuTexture{
        .size = .{ .x = 1, .y = 1 },
        .data = &[_]u8{ 255, 255, 255, 255 },
    };

    return init(device, cpu_texture);
}
