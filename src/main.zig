const std = @import("std");
const alloc = @import("alloc.zig");
const glfw = @import("glfw");
const gfx = @import("gfx/gfx.zig");
const vk = @import("vulkan");

const Window = @import("window.zig");

pub fn main() !void {
    try run();
    try alloc.reportLeaks();
}

fn run() !void {
    const width = 800;
    const height = 600;

    var window = try Window.create(width, height, "v10game");
    defer window.destroy();

    try gfx.System.init();

    var device = try gfx.Device.create(&gfx.system, &window);
    defer device.destroy();

    var swapchain = try gfx.Swapchain.create(&device, window.getExtent(), alloc.gpa);
    defer swapchain.destroy();

    const layout = try createPipelineLayout(&device);
    const pipeline = try createPipeline(&device, &swapchain, layout);
    defer pipeline.destroy();

    while (!window.shouldClose()) {
        glfw.pollEvents();
        glfw.swapBuffers(window.window.?);
    }
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
    var pipeline_config = gfx.Pipeline.ConfigInfo.default(swapchain.extent.width, swapchain.extent.height);
    pipeline_config.render_pass = swapchain.render_pass;
    pipeline_config.pipeline_layout = layout;

    return try gfx.Pipeline.create(device, "shaders/simple.vert.spv", "shaders/simple.frag.spv", pipeline_config);
}
