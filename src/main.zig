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
    var sierpinski = try Sierpinski.init(initial_triangle, 7);
    defer sierpinski.deinit();

    const vertices = try sierpinski.vertices();
    defer alloc.gpa.free(vertices);

    var model = try gfx.Model.create(&device, vertices);
    defer model.destroy();

    const command_buffers = try swapchain.createCommandBuffers();
    try recordCommandBuffers(&swapchain, &pipeline, command_buffers, model);

    _ = glfw.setKeyCallback(window.window, keyCallback);

    while (!window.shouldClose()) {
        glfw.pollEvents();

        try drawFrame(&swapchain, command_buffers);
    }

    try device.device.deviceWaitIdle();
}

fn keyCallback(window: glfw.Window, key: c_int, scancode: c_int, action: glfw.Action, mods: c_int) callconv(.C) void {
    _ = scancode;
    _ = mods;

    if (key == glfw.c.GLFW_KEY_ESCAPE and action == .press) {
        glfw.setWindowShouldClose(window, glfw.TRUE);
    }
}

const Triangle = struct {
    pos: gfx.Vec2,
    size: f32,

    pub fn vertices(this: @This()) [3]Vertex {
        const half = this.size / 2;
        return .{
            .{ .position = this.pos.add(.{ .x = 0, .y = -half }) },
            .{ .position = this.pos.add(.{ .x = half, .y = half }) },
            .{ .position = this.pos.add(.{ .x = -half, .y = half }) },
        };
    }
};

const Sierpinski = struct {
    triangles: std.ArrayList(Triangle),

    pub fn init(initial_triangle: Triangle, iterations: usize) !@This() {
        const tri_count = std.math.pow(usize, 3, iterations);
        var result = @This(){
            .triangles = try std.ArrayList(Triangle).initCapacity(alloc.gpa, tri_count),
        };

        try result.triangles.append(initial_triangle);
        std.debug.assert(result.triangles.items.len == 1);

        try result.sierpinski(iterations);

        return result;
    }

    fn sierpinski(this: *@This(), iterations: usize) !void {
        for (0..iterations) |_| {
            const tri_count = this.triangles.items.len;

            for (0..tri_count) |i| {
                const idx = tri_count - 1 - i;
                const triangle = this.triangles.swapRemove(idx);

                const pos = triangle.pos;
                const size = triangle.size / 2;
                const offset = size / 2;

                try this.triangles.appendSlice(&.{
                    Triangle{ .size = size, .pos = pos.add(.{ .x = 0, .y = -offset }) },
                    Triangle{ .size = size, .pos = pos.add(.{ .x = offset, .y = offset }) },
                    Triangle{ .size = size, .pos = pos.add(.{ .x = -offset, .y = offset }) },
                });
            }
        }
    }

    pub fn deinit(this: *@This()) void {
        this.triangles.deinit();
    }

    pub fn vertices(this: *@This()) ![]Vertex {
        const result = try alloc.gpa.alloc(Vertex, this.triangles.items.len * 3);

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
