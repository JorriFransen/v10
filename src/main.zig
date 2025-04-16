const std = @import("std");
const alloc = @import("alloc.zig");
const glfw = @import("glfw");
const gfx = @import("gfx/gfx.zig");
const vk = @import("vulkan");
const vklog = std.log.scoped(.vulkan);

const Allocator = std.mem.Allocator;
const Window = @import("window.zig");
const Device = gfx.Device;
const Swapchain = gfx.Swapchain;
const Pipeline = gfx.Pipeline;
const Entity = @import("entity.zig");
const Model = gfx.Model;
const Vec2 = gfx.Vec2;
const Vec3 = gfx.Vec3;
const Mat2 = gfx.math.Mat(2, 2, f32);

pub fn main() !void {
    try run();
    try alloc.deinit();

    std.log.debug("Clean exit", .{});
}

// TODO: Seperate arena for swapchain/pipeline (resizing).
var window: Window = undefined;
var device: Device = undefined;
var swapchain: Swapchain = undefined;
var layout: vk.PipelineLayout = .null_handle;
var pipeline: Pipeline = undefined;

var entities: []Entity = undefined;

const PushConstantData = extern struct {
    transform: Mat2 align(8),
    offset: Vec2 align(8),
    color: Vec3 align(16),
};

fn run() !void {
    const width = 1920;
    const height = 1080;

    try window.init(width, height, "v10game");
    defer window.destroy();

    try gfx.System.init();

    device = try Device.create(&gfx.system, &window);
    defer device.destroy();

    layout = try createPipelineLayout();
    defer device.device.destroyPipelineLayout(layout, null);

    try Swapchain.init(&swapchain, &device, .{ .extent = .{ .width = width, .height = height } });
    defer swapchain.destroy(true);

    pipeline = try createPipeline();
    defer pipeline.destroy();

    var model = try Model.create(&device, &.{
        .{ .position = Vec2.new(0, -0.5), .color = Vec3.new(1, 0, 0) },
        .{ .position = Vec2.new(0.5, 0.5), .color = Vec3.new(0, 1, 0) },
        .{ .position = Vec2.new(-0.5, 0.5), .color = Vec3.new(0, 0, 1) },
    });
    defer model.destroy();

    var _entities = [_]Entity{
        Entity.new(),
    };
    const triangle = &_entities[0];
    triangle.model = &model;
    triangle.color = Vec3.v(.{ 0.1, 0.8, 0.1 });
    triangle.transform.translation = .{ .x = 0.2, .y = 0 };
    triangle.transform.scale = .{ .x = 2, .y = 0.5 };
    triangle.transform.rotation = 0.25 * std.math.tau;

    entities = &_entities;

    try swapchain.createCommandBuffers();

    _ = glfw.setKeyCallback(window.window, keyCallback);

    if (window.platform != .WAYLAND) {
        // The drawFrame() call in refreshCallback() makes window resizing laggy.
        // This is meant to redraw during resize, to make resizing smoother, but wayland
        //  doesn't have this problem to start with.
        _ = glfw.setWindowRefreshCallback(window.window, refreshCallback);
    }

    while (!window.shouldClose()) {
        glfw.pollEvents();
        drawFrame() catch unreachable;
    }

    try device.device.deviceWaitIdle();
}

fn keyCallback(glfw_window: glfw.Window, key: c_int, scancode: c_int, action: glfw.Action, mods: c_int) callconv(.C) void {
    _ = scancode;
    _ = mods;

    if (key == glfw.c.GLFW_KEY_ESCAPE and action == .press) {
        glfw.setWindowShouldClose(glfw_window, glfw.TRUE);
    }
}

fn refreshCallback(glfw_window: glfw.Window) callconv(.c) void {
    _ = glfw_window;
    drawFrame() catch unreachable;
}

fn createPipelineLayout() !vk.PipelineLayout {
    const push_constant_range = vk.PushConstantRange{
        .offset = 0,
        .size = @sizeOf(PushConstantData),
        .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
    };

    const pipeline_layout_info = vk.PipelineLayoutCreateInfo{
        .set_layout_count = 0,
        .p_set_layouts = null,
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_constant_range),
    };

    return try device.device.createPipelineLayout(&pipeline_layout_info, null);
}

fn createPipeline() !Pipeline {
    var pipeline_config = Pipeline.ConfigInfo.default();
    pipeline_config.render_pass = swapchain.render_pass;
    pipeline_config.pipeline_layout = layout;

    return try Pipeline.create(&device, "shaders/simple.vert.spv", "shaders/simple.frag.spv", pipeline_config);
}

fn drawFrame() !void {
    var image_index: u32 = undefined;
    var result = try swapchain.acquireNextImage(&image_index);

    if (result == .error_out_of_date_khr) {
        try recreateSwapchain();
        return;
    }

    if (result != .success and result != .suboptimal_khr) {
        return error.swapchainAcquireNextImageFailed;
    }

    try recordCommandBuffer(image_index);

    result = try swapchain.submitCommandBuffers(swapchain.command_buffers[image_index], &image_index);
    if (result == .error_out_of_date_khr or result == .suboptimal_khr or window.framebuffer_resized) {
        window.framebuffer_resized = false;
        try recreateSwapchain();
    } else if (result != .success) {
        return error.swapchainSubmitCommandBuffersFailed;
    }
}

fn recreateSwapchain() !void {
    const vkd = device.device;

    var extent = window.getExtent();
    while (extent.width == 0 or extent.height == 0) {
        extent = window.getExtent();
        window.waitEvents();

        if (window.shouldClose()) return;
    }

    try vkd.deviceWaitIdle();

    var old_chain = swapchain;
    var new_chain = swapchain;

    for (old_chain.depth_image_views) |div| vkd.destroyImageView(div, null);
    for (old_chain.depth_images) |dimg| vkd.destroyImage(dimg, null);
    for (old_chain.depth_image_memories) |dimm| vkd.freeMemory(dimm, null);
    for (old_chain.image_views) |iv| vkd.destroyImageView(iv, null);
    vkd.destroyRenderPass(old_chain.render_pass, null);
    for (old_chain.framebuffers) |fb| vkd.destroyFramebuffer(fb, null);

    try Swapchain.init(&new_chain, &device, .{ .extent = extent, .old_swapchain = swapchain.swapchain });

    vkd.destroySwapchainKHR(old_chain.swapchain, null);

    if (old_chain.command_buffers.len != new_chain.images.len) {
        old_chain.freeCommandBuffers();
        try new_chain.createCommandBuffers();
    }

    swapchain = new_chain;

    // TODO: This can be omitted if the new renderpass is compatible with the old one
    pipeline.destroy();
    pipeline = try createPipeline();
}

fn recordCommandBuffer(image_index: usize) !void {
    std.debug.assert(image_index < swapchain.command_buffers.len);
    const handle = swapchain.command_buffers[image_index];

    var cb = vk.CommandBufferProxy.init(handle, swapchain.device.device.wrapper);
    const begin_info = vk.CommandBufferBeginInfo{};
    try cb.beginCommandBuffer(&begin_info);

    const clear_values = [_]vk.ClearValue{
        .{ .color = .{ .float_32 = .{ 0.01, 0.01, 0.01, 1 } } },
        .{ .depth_stencil = .{ .depth = 1, .stencil = 0 } },
    };

    const extent = swapchain.swapchain_extent;
    const render_pass_info = vk.RenderPassBeginInfo{
        .render_pass = swapchain.render_pass,
        .framebuffer = swapchain.framebuffers[image_index],
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

    drawEntities(&cb);

    cb.endRenderPass();
    try cb.endCommandBuffer();
}

fn drawEntities(cb: *const vk.CommandBufferProxy) void {
    cb.bindPipeline(.graphics, pipeline.graphics_pipeline);

    for (entities) |*entity| {
        entity.transform.rotation = @mod(entity.transform.rotation + 0.001, std.math.tau);
        var pcd = PushConstantData{
            .offset = entity.transform.translation,
            .color = entity.color,
            .transform = entity.transform.mat2(),
        };
        cb.pushConstants(layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, @sizeOf(PushConstantData), &pcd);

        entity.model.bind(cb.handle);
        entity.model.draw(cb.handle);
    }
}
