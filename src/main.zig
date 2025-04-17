const std = @import("std");
const alloc = @import("alloc.zig");
const glfw = @import("glfw");
const gfx = @import("gfx/gfx.zig");
const vk = @import("vulkan");

const Window = @import("window.zig");
const Renderer = gfx.Renderer;
const Device = gfx.Device;
const Pipeline = gfx.Pipeline;
const Entity = @import("entity.zig");
const Model = gfx.Model;
const Vec2 = gfx.Vec2;
const Vec3 = gfx.Vec3;
const Vec4 = gfx.Vec4;

pub fn main() !void {
    try run();
    try alloc.deinit();

    std.log.debug("Clean exit", .{});
}

var window: Window = undefined;
var device: Device = undefined;
var renderer: Renderer = undefined;
var layout: vk.PipelineLayout = .null_handle;

// TODO: Seperate arena for swapchain/pipeline (resizing).
var pipeline: Pipeline = undefined;

var entities: []Entity = undefined;

const PushConstantData = extern struct {
    transform: [3]Vec4,
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

    try renderer.init(&window, &device);
    defer renderer.destroy();

    pipeline = try createPipeline();
    defer pipeline.destroy();

    var model = try Model.create(&device, &.{
        .{ .position = Vec2.new(0, -0.5) },
        .{ .position = Vec2.new(0.5, 0.5) },
        .{ .position = Vec2.new(-0.5, 0.5) },
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

    try renderer.createCommandBuffers();

    // TODO: Move this to window
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
    pipeline_config.render_pass = renderer.swapchain.render_pass;
    pipeline_config.pipeline_layout = layout;

    return try Pipeline.create(&device, "shaders/simple.vert.spv", "shaders/simple.frag.spv", pipeline_config);
}

fn drawFrame() !void {
    var cb_opt = try renderer.beginFrame();
    while (cb_opt == null) {
        cb_opt = try renderer.beginFrame();

        // Resized swapchain
        // TODO: This can be omitted if the new renderpass is compatible with the old one
        pipeline.destroy();
        pipeline = try createPipeline();
    }
    const cb = cb_opt.?;

    renderer.beginRenderpass(cb);

    recordCommandBuffer(cb);

    renderer.endRenderPass(cb);
    renderer.endFrame(cb) catch |err| switch (err) {
        else => return err,
        error.swapchainRecreated => {

            // TODO: This can be omitted if the new renderpass is compatible with the old one
            pipeline.destroy();
            pipeline = try createPipeline();
        },
    };
}

fn recordCommandBuffer(cb: vk.CommandBufferProxy) void {
    drawEntities(&cb);
}

fn drawEntities(cb: *const vk.CommandBufferProxy) void {
    cb.bindPipeline(.graphics, pipeline.graphics_pipeline);

    for (entities) |*entity| {
        entity.transform.rotation = @mod(entity.transform.rotation + 0.001, std.math.tau);
        var pcd = PushConstantData{
            .offset = entity.transform.translation,
            .color = entity.color,
            .transform = gfx.math.padMat3f32(entity.transform.mat3()),
        };
        cb.pushConstants(layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, @sizeOf(PushConstantData), &pcd);

        entity.model.bind(cb.handle);
        entity.model.draw(cb.handle);
    }
}
