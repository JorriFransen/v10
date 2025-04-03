const std = @import("std");
const alloc = @import("alloc.zig");
const glfw = @import("glfw");
const gfx = @import("gfx/gfx.zig");
const vk = @import("vulkan");
const vklog = std.log.scoped(.vulkan);

const Allocator = std.mem.Allocator;
const Window = @import("window.zig");

pub fn main() !void {
    try run();
    try alloc.deinit();
}

fn run() !void {
    const width = 800;
    const height = 600;

    var window = try Window.create(width, height, "v10game");
    defer window.destroy();

    try gfx.System.init();

    var device = try gfx.Device.create(&gfx.system, &window);
    defer device.destroy();

    var swapchain = try gfx.Swapchain.create(&device, window.getExtent());
    defer swapchain.destroy();

    const layout = try createPipelineLayout(&device);
    defer device.device.destroyPipelineLayout(layout, null);

    var pipeline = try createPipeline(&device, &swapchain, layout);
    defer pipeline.destroy();

    const ga = alloc.gfx_arena_data.allocator();

    const command_buffers = try createCommandBuffers(&swapchain, &pipeline, ga);

    while (!window.shouldClose()) {
        glfw.pollEvents();

        drawFrame(&swapchain, command_buffers) catch |err| {
            std.log.err("drawframe err: {}", .{err});
            break;
        };
    }

    try device.device.deviceWaitIdle();
}

fn createPipelineLayout(device: *const gfx.Device) !vk.PipelineLayout {
    const pipeline_layout_info = vk.PipelineLayoutCreateInfo{
        .set_layout_count = 0,
        .p_set_layouts = null,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = null,
    };

    return try device.device.createPipelineLayout(&pipeline_layout_info, null);
}

fn createPipeline(device: *gfx.Device, swapchain: *const gfx.Swapchain, layout: vk.PipelineLayout) !gfx.Pipeline {
    var pipeline_config = gfx.Pipeline.ConfigInfo.default(swapchain.swapchain_extent.width, swapchain.swapchain_extent.height);
    pipeline_config.render_pass = swapchain.render_pass;
    pipeline_config.pipeline_layout = layout;

    return try gfx.Pipeline.create(device, "shaders/simple.vert.spv", "shaders/simple.frag.spv", pipeline_config);
}

fn createCommandBuffers(swapchain: *gfx.Swapchain, pipeline: *gfx.Pipeline, allocator: Allocator) ![]vk.CommandBuffer {
    const vkd = swapchain.device.device;
    const handles = try allocator.alloc(vk.CommandBuffer, swapchain.images.len);

    const alloc_info = vk.CommandBufferAllocateInfo{
        .level = .primary,
        .command_pool = swapchain.device.command_pool,
        .command_buffer_count = @intCast(handles.len),
    };

    try vkd.allocateCommandBuffers(&alloc_info, handles.ptr);

    for (handles, 0..) |handle, i| {
        var cb = vk.CommandBufferProxy.init(handle, swapchain.device.device.wrapper);

        const begin_info = vk.CommandBufferBeginInfo{};
        try cb.beginCommandBuffer(&begin_info);

        const clear_values = [_]vk.ClearValue{
            .{ .color = .{ .float_32 = .{ 0.1, 0.1, 0.1, 1 } } },
            .{ .depth_stencil = .{ .depth = 1, .stencil = 0 } },
        };

        const render_pass_info = vk.RenderPassBeginInfo{
            .render_pass = swapchain.render_pass,
            .framebuffer = swapchain.framebuffers[i],
            .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = swapchain.swapchain_extent },
            .clear_value_count = clear_values.len,
            .p_clear_values = @ptrCast(&clear_values),
        };

        cb.beginRenderPass(&render_pass_info, .@"inline");
        cb.bindPipeline(.graphics, pipeline.graphics_pipeline);
        cb.draw(3, 1, 0, 0);

        cb.endRenderPass();
        try cb.endCommandBuffer();
    }

    return handles;
}

fn drawFrame(swapchain: *gfx.Swapchain, command_buffers: []vk.CommandBuffer) !void {
    var image_index: u32 = undefined;
    var result = try swapchain.acquireNextImage(&image_index);

    if (result != .success and result != .suboptimal_khr) {
        return error.acquireNextImageFailed;
    }

    result = try swapchain.submitCommandBuffers(command_buffers[image_index], &image_index);
    if (result != .success and result != .suboptimal_khr) {
        vklog.err("result: {}", .{result});
        return error.submitCommandBuffersFailed;
    }
}
