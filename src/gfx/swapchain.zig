const std = @import("std");
const vk = @import("vulkan");
const vklog = std.log.scoped(.vulkan);

const Allocator = std.mem.Allocator;
const Device = @import("device.zig");

const MAX_FRAMES_IN_FLIGHT = 2;

allocator: Allocator,
device: *Device,
window_extent: vk.Extent2D,

swapchain: vk.SwapchainKHR = undefined,
image_format: vk.Format = undefined,
depth_format: vk.Format = undefined,
extent: vk.Extent2D = undefined,

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

pub fn create(device: *Device, extent: vk.Extent2D, allocator: Allocator) !@This() {
    var this = @This(){
        .allocator = allocator,
        .device = device,
        .window_extent = extent,
    };

    try this.createSwapchain();
    try this.createImageViews();
    try this.createRenderPass();
    try this.createDepthResources();
    try this.createFramebuffers();
    try this.createSyncObjects();

    return this;
}

pub fn destroy(this: *@This()) void {
    _ = this;
    std.debug.assert(false);
}

fn createSwapchain(this: *@This()) !void {
    const vkd = this.device.device;

    const swapchain_support = this.device.device_info.swapchain_support;

    const surface_format = this.chooseSwapSurfaceFormat(swapchain_support.formats);
    const present_mode = this.chooseSwapPresentMode(swapchain_support.present_modes);
    vklog.debug("Using present mode: {s}", .{@tagName(present_mode)});
    const extent = this.chooseSwapExtent(swapchain_support.capabilities);

    var image_count = swapchain_support.capabilities.min_image_count + 1;
    if (swapchain_support.capabilities.max_image_count > 0 and
        image_count > swapchain_support.capabilities.max_image_count)
    {
        image_count = swapchain_support.capabilities.max_image_count;
    }

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
        .old_swapchain = .null_handle,
        .image_sharing_mode = if (same_queue) .exclusive else .concurrent,
        .queue_family_index_count = if (same_queue) queue_indices.len else 0,
        .p_queue_family_indices = if (same_queue) @ptrCast(&queue_indices) else null,
    };

    this.swapchain = try vkd.createSwapchainKHR(&create_info, null);

    if (try vkd.getSwapchainImagesKHR(this.swapchain, &image_count, null) != .success) {
        return error.vkGetSwapchainImagesKHRFailed;
    }
    std.debug.assert(this.images.len == 0);
    this.images = try this.allocator.alloc(vk.Image, image_count);
    if (try vkd.getSwapchainImagesKHR(this.swapchain, &image_count, this.images.ptr) != .success) {
        return error.vkGetSwapchainImagesKHRFailed;
    }

    this.image_format = surface_format.format;
    this.extent = extent;
}

fn createImageViews(this: *@This()) !void {
    std.debug.assert(this.images.len > 0);

    const vkd = this.device.device;

    this.image_views = try this.allocator.alloc(vk.ImageView, this.images.len);

    for (this.images, this.image_views) |image, *view| {
        const view_info = vk.ImageViewCreateInfo{
            .image = image,
            .view_type = .@"2d",
            .format = this.image_format,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        };

        view.* = try vkd.createImageView(&view_info, null);
    }
}

fn createRenderPass(this: *@This()) !void {
    const vkd = this.device.device;

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

fn createDepthResources(this: *@This()) !void {
    const vkd = this.device.device;

    this.depth_images = try this.allocator.alloc(vk.Image, this.images.len);
    this.depth_image_memories = try this.allocator.alloc(vk.DeviceMemory, this.images.len);
    this.depth_image_views = try this.allocator.alloc(vk.ImageView, this.images.len);

    for (
        this.depth_images,
        this.depth_image_memories,
        this.depth_image_views,
    ) |*depth_image, *image_memory, *image_view| {
        const image_info = vk.ImageCreateInfo{
            .image_type = .@"2d",
            .extent = .{ .width = this.extent.width, .height = this.extent.height, .depth = 1 },
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

fn createFramebuffers(this: *@This()) !void {
    const vkd = this.device.device;

    this.framebuffers = try this.allocator.alloc(vk.Framebuffer, this.images.len);

    for (this.framebuffers, 0..) |*fb, i| {
        const attachments = .{ this.image_views[i], this.depth_image_views[i] };

        const framebuffer_info = vk.FramebufferCreateInfo{
            .render_pass = this.render_pass,
            .attachment_count = attachments.len,
            .p_attachments = @ptrCast(&attachments),
            .width = this.extent.width,
            .height = this.extent.height,
            .layers = 1,
        };

        fb.* = try vkd.createFramebuffer(&framebuffer_info, null);
    }
}

fn createSyncObjects(this: *@This()) !void {
    this.image_available_semaphores = try this.allocator.alloc(vk.Semaphore, MAX_FRAMES_IN_FLIGHT);
    this.render_finished_semaphores = try this.allocator.alloc(vk.Semaphore, MAX_FRAMES_IN_FLIGHT);
    this.in_flight_fences = try this.allocator.alloc(vk.Fence, MAX_FRAMES_IN_FLIGHT);

    this.images_in_flight = try this.allocator.alloc(vk.Fence, this.images.len);
    @memset(this.images_in_flight, .null_handle);
}

fn chooseSwapSurfaceFormat(this: *@This(), formats: []vk.SurfaceFormatKHR) vk.SurfaceFormatKHR {
    _ = this;
    std.debug.assert(formats.len > 0);

    for (formats) |format| {
        if (format.format == .b8g8r8a8_unorm and format.color_space == .srgb_nonlinear_khr)
            return format;
    }

    return formats[0];
}

fn chooseSwapPresentMode(this: *@This(), pmodes: []vk.PresentModeKHR) vk.PresentModeKHR {
    _ = this;
    std.debug.assert(pmodes.len > 0);

    for (pmodes) |pm| vklog.debug("Available present mode: {s}", .{@tagName(pm)});

    for (pmodes) |present_mode| {
        if (present_mode == .mailbox_khr) {
            return present_mode;
        }
    }

    // for (pmodes) |present_mode| {
    //     if (present_mode == .immediate_khr)
    //         vklog.debug("Using present mode: {}", .{.immediate_khr});
    //     return present_mode;
    // }

    return .fifo_khr;
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
