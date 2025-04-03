const std = @import("std");
const alloc = @import("alloc.zig");
const glfw = @import("glfw");
const gfx = @import("gfx/gfx.zig");
const vk = @import("vulkan");
const vklog = std.log.scoped(.vulkan);

const Allocator = std.mem.Allocator;
const Window = @import("window.zig");
const Vertex = gfx.Model.Vertex;

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

    const initial_triangle = Triangle{ .pos = .{ .x = 0, .y = 0 }, .size = 1.8 };
    var sierpinski = try Sierpinski.init(initial_triangle, 1);

    const vertices = try sierpinski.vertices(alloc.gpa);
    var model = try gfx.Model.create(&device, vertices);
    defer model.destroy();

    const command_buffers = try swapchain.createCommandBuffers();
    try recordCommandBuffers(&swapchain, &pipeline, command_buffers, model);

    while (!window.shouldClose()) {
        glfw.pollEvents();

        drawFrame(&swapchain, command_buffers) catch |err| {
            std.log.err("drawframe err: {}", .{err});
            break;
        };
    }

    try device.device.deviceWaitIdle();
}

const Triangle = struct {
    pos: gfx.Vec2,
    size: f32,

    pub fn vertices(this: @This()) [3]Vertex {
        const half = this.size / 2;
        return .{
            .{ .position = .{ .x = 0, .y = -half } },
            .{ .position = .{ .x = half, .y = half } },
            .{ .position = .{ .x = -half, .y = half } },
        };
    }
};

const Sierpinski = struct {
    triangles: std.ArrayList(Triangle),

    pub fn init(initial_triangle: Triangle, iterations: usize) !@This() {
        var result = @This(){
            .triangles = try std.ArrayList(Triangle).initCapacity(alloc.gpa, std.math.pow(usize, 3, iterations)),
        };

        try result.triangles.append(initial_triangle);
        std.debug.assert(result.triangles.items.len == 1);

        return result;
    }

    pub fn vertices(this: *@This(), allocator: Allocator) ![]Vertex {
        const result = try allocator.alloc(Vertex, this.triangles.items.len * 3);

        var vi: usize = 0;
        for (this.triangles.items) |triangle| {
            const tvertices = triangle.vertices();
            result[vi + 0] = tvertices[0];
            result[vi + 1] = tvertices[1];
            result[vi + 2] = tvertices[2];

            vi += 3;
        }

        return result;
    }
};

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

fn recordCommandBuffers(swapchain: *gfx.Swapchain, pipeline: *gfx.Pipeline, buffers: []vk.CommandBuffer, model: gfx.Model) !void {
    for (buffers, 0..) |handle, i| {
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

        model.bind(handle);
        model.draw(handle);

        cb.endRenderPass();
        try cb.endCommandBuffer();
    }
}
