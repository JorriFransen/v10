const std = @import("std");
const alloc = @import("../alloc.zig");
const gfx = @import("../gfx.zig");
const vk = @import("vulkan");

const Window = @import("../window.zig");
const Device = gfx.Device;
const Swapchain = gfx.Swapchain;

const assert = std.debug.assert;

window: *Window,
device: *Device,
swapchain: Swapchain,
command_buffers: []vk.CommandBuffer = &.{},
current_image_index: u32 = 0,
current_frame_index: usize = 0,

pub fn init(this: *@This(), window: *Window, device: *Device) !void {
    this.window = window;
    this.device = device;

    try this.swapchain.init(device, .{ .extent = window.getExtent() });
    try this.createCommandBuffers();
}

pub fn destroy(this: *@This()) void {
    this.freeCommandBuffers();
    this.swapchain.destroy(true);
}

pub fn createCommandBuffers(this: *@This()) !void {
    const vkd = this.device.device;

    assert(this.command_buffers.len == 0);
    this.command_buffers = try alloc.common_arena.allocator().alloc(vk.CommandBuffer, Swapchain.MAX_FRAMES_IN_FLIGHT);

    const alloc_info = vk.CommandBufferAllocateInfo{
        .level = .primary,
        .command_pool = this.device.command_pool,
        .command_buffer_count = @intCast(this.command_buffers.len),
    };

    try vkd.allocateCommandBuffers(&alloc_info, this.command_buffers.ptr);
}

pub fn freeCommandBuffers(this: *@This()) void {
    const vkd = this.device.device;
    vkd.freeCommandBuffers(this.device.command_pool, @intCast(this.command_buffers.len), this.command_buffers.ptr);
}

pub fn beginFrame(this: *@This()) !?vk.CommandBufferProxy {
    const result = try this.swapchain.acquireNextImage(&this.current_image_index);

    if (result == .error_out_of_date_khr) {
        try this.recreateSwapchain();
        return null;
    }

    if (result != .success and result != .suboptimal_khr) {
        return error.swapchainAcquireNextImageFailed;
    }

    const cb = vk.CommandBufferProxy.init(this.command_buffers[this.current_frame_index], this.device.device.wrapper);

    const begin_info = vk.CommandBufferBeginInfo{};
    try cb.beginCommandBuffer(&begin_info);

    return cb;
}

pub fn endFrame(this: *@This(), cb: vk.CommandBufferProxy) !void {
    try cb.endCommandBuffer();

    const result = try this.swapchain.submitCommandBuffers(cb.handle, &this.current_image_index);
    if (result == .error_out_of_date_khr or result == .suboptimal_khr or this.window.framebuffer_resized) {
        this.window.framebuffer_resized = false;
        try this.recreateSwapchain();
        return;
    } else if (result != .success) {
        return error.swapchainSubmitCommandBuffersFailed;
    }

    this.current_frame_index = @mod(this.current_frame_index + 1, Swapchain.MAX_FRAMES_IN_FLIGHT);
}

pub fn beginRenderpass(this: *@This(), cb: vk.CommandBufferProxy) void {
    const clear_values = [_]vk.ClearValue{
        .{ .color = .{ .float_32 = .{ 0.01, 0.01, 0.01, 1 } } },
        .{ .depth_stencil = .{ .depth = 1, .stencil = 0 } },
    };

    const extent = this.swapchain.swapchain_extent;
    const render_pass_info = vk.RenderPassBeginInfo{
        .render_pass = this.swapchain.render_pass,
        .framebuffer = this.swapchain.framebuffers[this.current_image_index],
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = extent },
        .clear_value_count = clear_values.len,
        .p_clear_values = &clear_values,
    };

    cb.beginRenderPass(&render_pass_info, .@"inline");

    const viewports = [1]vk.Viewport{.{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
        .min_depth = 0,
        .max_depth = 1,
    }};
    cb.setViewport(0, viewports.len, &viewports);

    const scissors = [1]vk.Rect2D{.{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    }};
    cb.setScissor(0, scissors.len, &scissors);
}

pub fn endRenderPass(_: *@This(), cb: vk.CommandBufferProxy) void {
    cb.endRenderPass();
}

pub fn recreateSwapchain(this: *@This()) !void {
    const vkd = this.device.device;

    var extent = this.window.getExtent();
    while (extent.width == 0 or extent.height == 0) {
        extent = this.window.getExtent();
        this.window.waitEvents();

        if (this.window.shouldClose()) {
            try vkd.deviceWaitIdle();
            return;
        }
    }

    try vkd.deviceWaitIdle();

    const old_chain = this.swapchain;
    var new_chain = this.swapchain;

    for (old_chain.depth_image_views) |div| vkd.destroyImageView(div, null);
    for (old_chain.depth_images) |dimg| vkd.destroyImage(dimg, null);
    for (old_chain.depth_image_memories) |dimm| vkd.freeMemory(dimm, null);
    for (old_chain.image_views) |iv| vkd.destroyImageView(iv, null);
    vkd.destroyRenderPass(old_chain.render_pass, null);
    for (old_chain.framebuffers) |fb| vkd.destroyFramebuffer(fb, null);

    new_chain.depth_image_views = &.{};
    new_chain.depth_images = &.{};
    new_chain.depth_image_memories = &.{};
    new_chain.image_views = &.{};
    new_chain.render_pass = .null_handle;
    new_chain.framebuffers = &.{};
    new_chain.images = &.{};

    for (old_chain.image_available_semaphores) |ias| vkd.destroySemaphore(ias, null);
    for (old_chain.render_finished_semaphores) |rfs| vkd.destroySemaphore(rfs, null);
    for (old_chain.in_flight_fences) |iff| vkd.destroyFence(iff, null);

    new_chain.image_available_semaphores = &.{};
    new_chain.render_finished_semaphores = &.{};
    new_chain.in_flight_fences = &.{};
    new_chain.images_in_flight = &.{};

    alloc.swapchain_arena.reset();

    try new_chain.init(this.device, .{ .extent = extent, .old_swapchain = old_chain.swapchain });

    if (!old_chain.compareSwapFormats(&new_chain)) {
        return error.swapchainImageOrDepthFormatChanged;
    }

    vkd.destroySwapchainKHR(old_chain.swapchain, null);

    this.swapchain = new_chain;
}
