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
const Model = gfx.Model;
const Vertex = Model.Vertex;
const Vec2 = gfx.Vec2;
const Vec3 = gfx.Vec3;

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
var command_buffers: []vk.CommandBuffer = undefined;

var model: Model = undefined;

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

    try Swapchain.init(&swapchain, &device, .{ .width = width, .height = height });
    defer swapchain.destroy(true);

    pipeline = try createPipeline();
    defer pipeline.destroy();

    // const initial_triangle = Triangle{ .pos = .{ .x = 0, .y = 0 }, .size = 1.8 };
    // var sierpinski = try Sierpinski.init(initial_triangle, 5);
    // defer sierpinski.deinit();
    //
    // const vertices = try sierpinski.vertices();
    // defer alloc.gpa.free(vertices);
    //
    // model = try Model.create(&device, vertices);
    model = try Model.create(&device, &.{
        .{ .position = Vec2.new(0, -0.9), .color = Vec3.new(1, 0, 0) },
        .{ .position = Vec2.new(0.9, 0.9), .color = Vec3.new(0, 1, 0) },
        .{ .position = Vec2.new(-0.9, 0.9), .color = Vec3.new(0, 0, 1) },
    });
    defer model.destroy();

    command_buffers = try swapchain.createCommandBuffers();

    _ = glfw.setKeyCallback(window.window, keyCallback);
    _ = glfw.setWindowRefreshCallback(window.window, refreshCallback);

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
    // std.log.debug("Refresh callback for window: {*}", .{glfw_window});
    _ = glfw_window;
    drawFrame() catch unreachable;
}

const Triangle = struct {
    pos: gfx.Vec2,
    size: f32,

    pub fn vertices(this: @This()) [3]Vertex {
        const half = this.size / 2;
        return .{
            .{ .position = this.pos.add(.{ .x = 0, .y = -half }), .color = Vec3.new(1, 0, 0) },
            .{ .position = this.pos.add(.{ .x = half, .y = half }), .color = Vec3.new(0, 1, 0) },
            .{ .position = this.pos.add(.{ .x = -half, .y = half }), .color = Vec3.new(0, 0, 1) },
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

fn createPipelineLayout() !vk.PipelineLayout {
    const pipeline_layout_info = vk.PipelineLayoutCreateInfo{
        .set_layout_count = 0,
        .p_set_layouts = null,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = null,
    };

    return try device.device.createPipelineLayout(&pipeline_layout_info, null);
}

fn createPipeline() !Pipeline {
    var pipeline_config = Pipeline.ConfigInfo.default(swapchain.swapchain_extent.width, swapchain.swapchain_extent.height);
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

    result = try swapchain.submitCommandBuffers(command_buffers[image_index], &image_index);
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

    pipeline.destroy();
    swapchain.destroy(false);

    try Swapchain.init(&swapchain, &device, extent);
    pipeline = try createPipeline();
}

fn recordCommandBuffer(image_index: usize) !void {
    std.debug.assert(image_index < command_buffers.len);
    const handle = command_buffers[image_index];

    var cb = vk.CommandBufferProxy.init(handle, swapchain.device.device.wrapper);
    const begin_info = vk.CommandBufferBeginInfo{};
    try cb.beginCommandBuffer(&begin_info);

    const clear_values = [_]vk.ClearValue{
        .{ .color = .{ .float_32 = .{ 0.05, 0.05, 0.05, 1 } } },
        .{ .depth_stencil = .{ .depth = 1, .stencil = 0 } },
    };

    const render_pass_info = vk.RenderPassBeginInfo{
        .render_pass = swapchain.render_pass,
        .framebuffer = swapchain.framebuffers[image_index],
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
