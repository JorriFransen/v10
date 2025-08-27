const std = @import("std");
const vk = @import("vulkan");
const gfx = @import("../gfx.zig");
const stb = @import("../stb/stb.zig");
const mem = @import("memory");
const res = @import("../resource.zig");
const math = @import("../math.zig");

/// GPU-side texture
const Texture = @This();

const Bitmap = gfx.Bitmap;
const Vec2 = math.Vec2;

const log = std.log.scoped(.gpu_texture);
const assert = std.debug.assert;

image: vk.Image,
image_memory: vk.DeviceMemory,
image_view: vk.ImageView,
descriptor_set: vk.DescriptorSet,
format: Format,
filter: Filter,

width: u32,
height: u32,

pub const Format = enum {
    u8_s_rgba,
    u8_u_r,

    pub fn toVulkan(this: Format) vk.Format {
        switch (this) {
            .u8_s_rgba => return .r8g8b8a8_srgb,
            .u8_u_r => return .r8_unorm,
        }
    }
};

pub const Filter = enum {
    nearest,
    linear,
};

pub const InitOptions = struct {
    filter: Filter = .nearest,
    debug_name: ?[]const u8 = null,
};

pub const LoadError =
    res.LoadError ||
    Bitmap.LoadError ||
    InitError;

// TODO: Should this return a pointer?
pub fn load(name: []const u8, options_: InitOptions) LoadError!*Texture {
    if (res.cache.get(name)) |ptr| {
        const texture: *Texture = @ptrCast(@alignCast(ptr));
        const size = texture.getSize();
        log.info("Loading cached texture: '{s}' - {}x{} - {} - {}", .{ name, size.x, size.y, texture.format, texture.filter });
        return texture;
    }

    var tmp = mem.get_temp();
    defer tmp.release();

    const cpu_texture = try Bitmap.load(tmp.allocator(), name, .{});

    var options = options_;
    if (options.debug_name == null) options.debug_name = name;
    const result = try init(cpu_texture, options);

    try res.cache.put(name, result);

    return result;
}

pub const InitError = error{VulkanMapMemory} ||
    gfx.Device.CreateBufferError ||
    gfx.Device.CreateImageError ||
    CreateDescriptorSetError ||
    vk.DeviceProxy.MapMemoryError ||
    error{OutOfMemory};

pub fn init(bitmap: Bitmap, options: InitOptions) InitError!*Texture {
    const vkd = &gfx.device.device;

    log.info("Creating texture: '{s}' - {}x{} - {} - {}", .{
        options.debug_name orelse "",
        bitmap.size.x,
        bitmap.size.y,
        bitmap.format,
        options.filter,
    });

    var staging_buffer_memory: vk.DeviceMemory = .null_handle;
    const staging_buffer = try gfx.device.createBuffer(
        bitmap.data.len,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        &staging_buffer_memory,
    );
    defer {
        vkd.destroyBuffer(staging_buffer, null);
        vkd.freeMemory(staging_buffer_memory, null);
    }

    const staging_data_opt = try vkd.mapMemory(staging_buffer_memory, 0, bitmap.data.len, .{});
    const staging_data = staging_data_opt orelse return error.VulkanMapMemory;
    const staging_mapped = @as([*]u8, @ptrCast(staging_data))[0..bitmap.data.len];
    @memcpy(staging_mapped, bitmap.data);
    vkd.unmapMemory(staging_buffer_memory);

    const format = bitmap.format.toVulkan();

    var image_mem: vk.DeviceMemory = .null_handle;
    const image = try gfx.device.createImageWithInfo(
        &.{
            .image_type = .@"2d",
            .extent = .{ .width = bitmap.size.x, .height = bitmap.size.y, .depth = 1 },
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

    const cb = gfx.device.beginSingleTimeCommands();
    gfx.device.transitionImageLayout(cb, image, format, .undefined, .transfer_dst_optimal);
    gfx.device.copyBufferToImage(cb, staging_buffer, image, bitmap.size.x, bitmap.size.y);
    gfx.device.transitionImageLayout(cb, image, format, .transfer_dst_optimal, .shader_read_only_optimal);
    gfx.device.endSingleTimeCommands(cb);

    const image_view = try gfx.device.createImageView(image, format);

    const descriptor_set = try createDescriptorSet(image_view, options.filter);

    const result = try mem.texture_arena.allocator().create(Texture);
    result.* = .{
        .image = image,
        .image_memory = image_mem,
        .image_view = image_view,
        .descriptor_set = descriptor_set,
        .format = bitmap.format,
        .filter = options.filter,
        .width = bitmap.size.x,
        .height = bitmap.size.y,
    };
    return result;
}

pub const UpdateError = gfx.Device.CreateBufferError ||
    vk.DeviceProxy.MapMemoryError ||
    error{VulkanMapMemory};

pub fn update(this: *Texture, bitmap: Bitmap, options: InitOptions) UpdateError!void {
    const vkd = &gfx.device.device;

    log.info("Updating texture: '{s}' - {}x{} - {} - {}", .{
        options.debug_name orelse "",
        bitmap.size.x,
        bitmap.size.y,
        bitmap.format,
        this.filter,
    });

    var staging_buffer_memory: vk.DeviceMemory = .null_handle;
    const staging_buffer = try gfx.device.createBuffer(
        bitmap.data.len,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        &staging_buffer_memory,
    );
    defer {
        vkd.destroyBuffer(staging_buffer, null);
        vkd.freeMemory(staging_buffer_memory, null);
    }

    const staging_data_opt = try vkd.mapMemory(staging_buffer_memory, 0, bitmap.data.len, .{});
    const staging_data = staging_data_opt orelse return error.VulkanMapMemory;
    const staging_mapped = @as([*]u8, @ptrCast(staging_data))[0..bitmap.data.len];
    @memcpy(staging_mapped, bitmap.data);
    vkd.unmapMemory(staging_buffer_memory);

    assert(this.format == bitmap.format);
    const format = bitmap.format.toVulkan();
    this.format = bitmap.format;

    const cb = gfx.device.beginSingleTimeCommands();
    gfx.device.transitionImageLayout(cb, this.image, format, .shader_read_only_optimal, .transfer_dst_optimal);
    gfx.device.copyBufferToImage(cb, staging_buffer, this.image, bitmap.size.x, bitmap.size.y);
    gfx.device.transitionImageLayout(cb, this.image, format, .transfer_dst_optimal, .shader_read_only_optimal);
    gfx.device.endSingleTimeCommands(cb);
}

pub fn deinit(this: *Texture) void {
    const vkd = &gfx.device.device;

    if (this.image != .null_handle) {
        vkd.destroyImage(this.image, null);
        vkd.freeMemory(this.image_memory, null);
        vkd.destroyImageView(this.image_view, null);

        this.image = .null_handle;
        this.image_memory = .null_handle;
        this.image_view = .null_handle;
    }
}

pub const CreateDescriptorSetError = error{} ||
    vk.DeviceProxy.AllocateDescriptorSetsError;

fn createDescriptorSet(image_view: vk.ImageView, filter: Filter) CreateDescriptorSetError!vk.DescriptorSet {
    const vkd = &gfx.device.device;

    const alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = gfx.device.descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast(&gfx.device.texture_sampler_set_layout),
    };

    var result: vk.DescriptorSet = .null_handle;
    try vkd.allocateDescriptorSets(&alloc_info, @ptrCast(&result));

    const image_info = vk.DescriptorImageInfo{
        .image_layout = .shader_read_only_optimal,
        .image_view = image_view,
        .sampler = switch (filter) {
            .nearest => gfx.device.nearest_sampler,
            .linear => gfx.device.linear_sampler,
        },
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

pub fn initDefaultWhite() InitError!*Texture {
    const bitmap = Bitmap{
        .format = .u8_s_rgba,
        .size = .{ .x = 1, .y = 1 },
        .data = &[_]u8{ 255, 255, 255, 255 },
    };
    return init(bitmap, .{ .filter = .nearest, .debug_name = "default_white" });
}
