const std = @import("std");
const vk = @import("vulkan");
const mem = @import("memory");
const log = std.log.scoped(.swapchain);
const gfx = @import("../gfx.zig");
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const Device = gfx.Device;
const Pipeline = gfx.Pipeline;

pub const MAX_FRAMES_IN_FLIGHT = 2;

device: *Device = undefined,
window_extent: vk.Extent2D = undefined,

swapchain: vk.SwapchainKHR = undefined,
image_format: vk.Format = undefined,
depth_format: vk.Format = undefined,
swapchain_extent: vk.Extent2D = undefined,

images: []vk.Image = &.{},
image_views: []vk.ImageView = &.{},
render_pass: vk.RenderPass = .null_handle,
depth_images: []vk.Image = &.{},
depth_image_memories: []vk.DeviceMemory = &.{},
depth_image_views: []vk.ImageView = &.{},
framebuffers: []vk.Framebuffer = &.{},

image_available_semaphores: []vk.Semaphore = &.{},
render_finished_semaphores: []vk.Semaphore = &.{},
in_flight_fences: []vk.Fence = &.{},
images_in_flight: []vk.Fence = &.{},

pub const SwapchainOptions = struct {
    extent: vk.Extent2D,
    old_swapchain: vk.SwapchainKHR = .null_handle,
};

pub fn init(this: *@This(), device: *Device, options: SwapchainOptions) !void {
    this.device = device;
    this.window_extent = options.extent;

    var arena = &mem.swapchain_arena;
    const allocator = arena.allocator();

    try this.createSwapchain(options, allocator);
    try this.createImageViews(allocator);
    try this.createRenderPass();
    try this.createDepthResources(allocator);
    try this.createFramebuffers(allocator);
    try this.createSyncObjects(allocator);
}

pub fn destroy(this: *@This(), destroy_sync_objects: bool) void {
    const vkd = &this.device.device;

    if (destroy_sync_objects) {
        for (this.image_available_semaphores) |ias| vkd.destroySemaphore(ias, null);
        for (this.render_finished_semaphores) |rfs| vkd.destroySemaphore(rfs, null);
        for (this.in_flight_fences) |iff| vkd.destroyFence(iff, null);
    }

    for (this.framebuffers) |fb| vkd.destroyFramebuffer(fb, null);

    for (this.depth_image_views) |div| vkd.destroyImageView(div, null);
    for (this.depth_image_memories) |dim| vkd.freeMemory(dim, null);
    for (this.depth_images) |di| vkd.destroyImage(di, null);

    vkd.destroyRenderPass(this.render_pass, null);

    for (this.image_views) |iv| vkd.destroyImageView(iv, null);

    vkd.destroySwapchainKHR(this.swapchain, null);
}

pub fn acquireNextImage(this: *@This(), image_index: *u32, current_frame_index: usize) !vk.Result {
    const vkd = &this.device.device;

    const R = vk.DeviceWrapper.AcquireNextImageKHRResult;
    const result = vkd.acquireNextImageKHR(this.swapchain, std.math.maxInt(u64), this.image_available_semaphores[current_frame_index], .null_handle) catch |err| switch (err) {
        error.OutOfDateKHR => R{ .result = .error_out_of_date_khr, .image_index = image_index.* },
        else => return err,
    };

    image_index.* = result.image_index;
    return result.result;
}

// TODO: Does image_index still need to be a pointer here?
pub fn submitCommandBuffers(this: *@This(), buffer: vk.CommandBuffer, image_index: *u32, frame_index: usize) !vk.Result {
    const vkd = &this.device.device;

    const wait_semaphores = [_]vk.Semaphore{this.image_available_semaphores[frame_index]};
    const wait_stage = vk.PipelineStageFlags{ .color_attachment_output_bit = true };
    const signal_semaphores = [_]vk.Semaphore{this.render_finished_semaphores[image_index.*]};

    const buffers = [_]vk.CommandBuffer{buffer};
    const submit_info = vk.SubmitInfo{
        .wait_semaphore_count = @intCast(wait_semaphores.len),
        .p_wait_semaphores = &wait_semaphores,
        .p_wait_dst_stage_mask = @ptrCast(&wait_stage),
        .command_buffer_count = @intCast(buffers.len),
        .p_command_buffers = &buffers,
        .signal_semaphore_count = @intCast(signal_semaphores.len),
        .p_signal_semaphores = &signal_semaphores,
    };

    try vkd.resetFences(1, @ptrCast(&this.in_flight_fences[frame_index]));

    try this.device.graphics_queue.submit(1, @ptrCast(&submit_info), this.in_flight_fences[frame_index]);

    this.images_in_flight[image_index.*] = this.in_flight_fences[frame_index];

    const present_info = vk.PresentInfoKHR{
        .wait_semaphore_count = @intCast(signal_semaphores.len),
        .p_wait_semaphores = &signal_semaphores,
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&this.swapchain),
        .p_image_indices = @ptrCast(image_index),
    };

    const result = this.device.present_queue.presentKHR(&present_info) catch |err| switch (err) {
        error.OutOfDateKHR => vk.Result.error_out_of_date_khr,
        else => return err,
    };

    return result;
}

fn createSwapchain(this: *@This(), options: SwapchainOptions, allocator: Allocator) !void {
    const vkd = &this.device.device;

    const swapchain_support = &this.device.device_info.swapchain_support;
    swapchain_support.capabilities =
        try this.device.vki.getPhysicalDeviceSurfaceCapabilitiesKHR(
            this.device.device_info.physical_device,
            this.device.surface,
        );

    const surface_format = this.chooseSwapSurfaceFormat(swapchain_support.formats);
    // log.info("Using surface format: {}", .{surface_format});
    const present_mode = this.chooseSwapPresentMode(swapchain_support.present_modes);
    log.info("Using present mode: {s}", .{@tagName(present_mode)});
    const extent = this.chooseSwapExtent(swapchain_support.capabilities);
    // log.info("Swapchain extent: {}", .{extent});

    var image_count = swapchain_support.capabilities.min_image_count + 1;
    if (swapchain_support.capabilities.max_image_count > 0 and
        image_count > swapchain_support.capabilities.max_image_count)
    {
        image_count = swapchain_support.capabilities.max_image_count;
    }

    // log.info("Swapchain image count: {}", .{image_count});

    const indices = this.device.device_info.queue_family_indices;
    const queue_indices = .{ indices.graphics_family.?, indices.present_family.? };
    const same_queue = queue_indices[0] == queue_indices[1];

    const create_info = vk.SwapchainCreateInfoKHR{
        .surface = this.device.surface,
        .min_image_count = image_count,
        .image_format = surface_format.format,
        .image_color_space = surface_format.color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .pre_transform = swapchain_support.capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = present_mode,
        .clipped = vk.TRUE,
        .image_sharing_mode = if (same_queue) .exclusive else .concurrent,
        .queue_family_index_count = if (same_queue) queue_indices.len else 0,
        .p_queue_family_indices = if (same_queue) @ptrCast(&queue_indices) else null,
        .old_swapchain = options.old_swapchain,
    };

    this.swapchain = try vkd.createSwapchainKHR(&create_info, null);

    if (try vkd.getSwapchainImagesKHR(this.swapchain, &image_count, null) != .success) {
        return error.vkGetSwapchainImagesKHRFailed;
    }

    assert(this.images.len == 0);
    this.images = try allocator.alloc(vk.Image, image_count);

    if (try vkd.getSwapchainImagesKHR(this.swapchain, &image_count, this.images.ptr) != .success) {
        return error.vkGetSwapchainImagesKHRFailed;
    }

    this.image_format = surface_format.format;
    this.swapchain_extent = extent;
}

fn createImageViews(this: *@This(), allocator: Allocator) !void {
    assert(this.images.len > 0);

    assert(this.image_views.len == 0);
    this.image_views = try allocator.alloc(vk.ImageView, this.images.len);

    for (this.images, this.image_views) |image, *view| {
        view.* = try this.device.createImageView(image, this.image_format);
    }
}

fn createRenderPass(this: *@This()) !void {
    const vkd = &this.device.device;

    const color_attachment = vk.AttachmentDescription{
        .format = this.image_format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_store_op = .dont_care,
        .stencil_load_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    this.depth_format = try this.findDepthFormat();

    const depth_attachment = vk.AttachmentDescription{
        .format = this.depth_format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .dont_care,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .depth_stencil_attachment_optimal,
    };

    const depth_attachment_ref = vk.AttachmentReference{
        .attachment = 1,
        .layout = .depth_stencil_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment_ref),
        .p_depth_stencil_attachment = @ptrCast(&depth_attachment_ref),
    };

    const dependency = vk.SubpassDependency{
        .src_subpass = vk.SUBPASS_EXTERNAL,
        .src_access_mask = .{},
        .src_stage_mask = .{ .color_attachment_output_bit = true, .early_fragment_tests_bit = true },
        .dst_subpass = 0,
        .dst_stage_mask = .{ .color_attachment_output_bit = true, .early_fragment_tests_bit = true },
        .dst_access_mask = .{ .color_attachment_write_bit = true, .depth_stencil_attachment_write_bit = true },
    };

    const attachments = .{ color_attachment, depth_attachment };

    const render_pass_info = vk.RenderPassCreateInfo{
        .attachment_count = attachments.len,
        .p_attachments = @ptrCast(&attachments),
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
        .dependency_count = 1,
        .p_dependencies = @ptrCast(&dependency),
    };

    this.render_pass = try vkd.createRenderPass(&render_pass_info, null);
}

fn createDepthResources(this: *@This(), allocator: Allocator) !void {
    const vkd = &this.device.device;

    assert(this.depth_images.len == 0);
    assert(this.depth_image_memories.len == 0);
    assert(this.depth_image_views.len == 0);

    this.depth_images = try allocator.alloc(vk.Image, this.images.len);
    this.depth_image_memories = try allocator.alloc(vk.DeviceMemory, this.images.len);
    this.depth_image_views = try allocator.alloc(vk.ImageView, this.images.len);

    for (
        this.depth_images,
        this.depth_image_memories,
        this.depth_image_views,
    ) |*depth_image, *image_memory, *image_view| {
        const image_info = vk.ImageCreateInfo{
            .image_type = .@"2d",
            .extent = .{ .width = this.swapchain_extent.width, .height = this.swapchain_extent.height, .depth = 1 },
            .mip_levels = 1,
            .array_layers = 1,
            .format = this.depth_format,
            .tiling = .optimal,
            .initial_layout = .undefined,
            .usage = .{ .depth_stencil_attachment_bit = true },
            .samples = .{ .@"1_bit" = true },
            .sharing_mode = .exclusive,
            .flags = vk.ImageCreateFlags.fromInt(0),
        };

        depth_image.* = try this.device.createImageWithInfo(
            &image_info,
            .{ .device_local_bit = true },
            image_memory,
        );

        const view_info = vk.ImageViewCreateInfo{
            .image = depth_image.*,
            .view_type = .@"2d",
            .format = this.depth_format,
            .subresource_range = .{ .aspect_mask = .{ .depth_bit = true }, .base_mip_level = 0, .level_count = 1, .base_array_layer = 0, .layer_count = 1 },
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        };

        image_view.* = try vkd.createImageView(&view_info, null);
    }
}

fn createFramebuffers(this: *@This(), allocator: Allocator) !void {
    const vkd = &this.device.device;

    assert(this.framebuffers.len == 0);
    this.framebuffers = try allocator.alloc(vk.Framebuffer, this.images.len);

    for (this.framebuffers, 0..) |*fb, i| {
        const attachments = .{ this.image_views[i], this.depth_image_views[i] };

        const framebuffer_info = vk.FramebufferCreateInfo{
            .render_pass = this.render_pass,
            .attachment_count = attachments.len,
            .p_attachments = @ptrCast(&attachments),
            .width = this.swapchain_extent.width,
            .height = this.swapchain_extent.height,
            .layers = 1,
        };

        fb.* = try vkd.createFramebuffer(&framebuffer_info, null);
    }
}

fn createSyncObjects(this: *@This(), allocator: Allocator) !void {
    const vkd = &this.device.device;

    const semaphore_info = vk.SemaphoreCreateInfo{};
    const fence_info = vk.FenceCreateInfo{ .flags = .{ .signaled_bit = true } };

    assert(this.image_available_semaphores.len == 0);
    assert(this.render_finished_semaphores.len == 0);
    assert(this.in_flight_fences.len == 0);
    assert(this.images_in_flight.len == 0);

    this.image_available_semaphores = try allocator.alloc(vk.Semaphore, MAX_FRAMES_IN_FLIGHT);
    this.render_finished_semaphores = try allocator.alloc(vk.Semaphore, this.images.len);
    this.in_flight_fences = try allocator.alloc(vk.Fence, MAX_FRAMES_IN_FLIGHT);

    for (this.image_available_semaphores) |*ias| {
        ias.* = try vkd.createSemaphore(&semaphore_info, null);
    }

    for (this.render_finished_semaphores) |*rfs| {
        rfs.* = try vkd.createSemaphore(&semaphore_info, null);
    }

    for (this.in_flight_fences) |*iff| {
        iff.* = try vkd.createFence(&fence_info, null);
    }

    this.images_in_flight = try allocator.alloc(vk.Fence, this.images.len);
    @memset(this.images_in_flight, .null_handle);
}

fn chooseSwapSurfaceFormat(this: *@This(), formats: []vk.SurfaceFormatKHR) vk.SurfaceFormatKHR {
    _ = this;
    assert(formats.len > 0);

    for (formats) |format| {
        if (format.format == .b8g8r8a8_srgb and format.color_space == .srgb_nonlinear_khr)
            return format;
    }

    log.warn("Preferred swapchain surface format not found, using first available", .{});

    return formats[0];
}

fn tagName(v: anytype) ?[]const u8 {
    const E = @TypeOf(v);

    return inline for (@typeInfo(E).@"enum".fields) |f| {
        if (@intFromEnum(v) == f.value) break f.name;
    } else return null;
}

fn chooseSwapPresentMode(this: *@This(), pmodes: []vk.PresentModeKHR) vk.PresentModeKHR {
    _ = this;
    assert(pmodes.len > 0);

    // for (pmodes) |pm| log.debug("Available present mode: {?s}({})", .{ tagName(pm), @intFromEnum(pm) });
    var result = vk.PresentModeKHR.fifo_khr;

    for (pmodes) |present_mode| {
        if (present_mode == .mailbox_khr) {
            result = present_mode;
            break;
        }
    }

    var immediate_khr_available = false;
    for (pmodes) |present_mode| {
        if (present_mode == .immediate_khr) {
            immediate_khr_available = true;
            break;
        }
    }

    return result;
}

fn chooseSwapExtent(this: *@This(), caps: vk.SurfaceCapabilitiesKHR) vk.Extent2D {
    if (caps.current_extent.width != std.math.maxInt(u32)) {
        return caps.current_extent;
    }

    var actual_extent = this.window_extent;
    actual_extent.width = @max(caps.min_image_extent.width, @min(caps.max_image_extent.width, actual_extent.width));
    actual_extent.height = @max(caps.min_image_extent.height, @min(caps.max_image_extent.height, actual_extent.height));
    return actual_extent;
}

fn findDepthFormat(this: *@This()) !vk.Format {
    return try this.device.findSupportedFormat(
        &.{
            .d32_sfloat,
            .d32_sfloat_s8_uint,
            .d24_unorm_s8_uint,
        },
        .optimal,
        .{ .depth_stencil_attachment_bit = true },
    );
}

pub fn compareSwapFormats(a: *const @This(), b: *const @This()) bool {
    return a.image_format == b.image_format and a.depth_format == b.depth_format;
}

pub fn extentSwapchainRatio(this: *const @This()) f32 {
    const w: f32 = @floatFromInt(this.swapchain_extent.width);
    const h: f32 = @floatFromInt(this.swapchain_extent.height);
    return w / h;
}
