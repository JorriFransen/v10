const std = @import("std");
const alloc = @import("alloc.zig");
const glfw = @import("glfw");
const gfx = @import("gfx/gfx.zig");
const vk = @import("vulkan");
const math = @import("math");

const Window = @import("window.zig");
const Renderer = gfx.Renderer;
const Device = gfx.Device;
const Entity = @import("entity.zig");
const Model = gfx.Model;
const SimpleRenderSystem = @import("simple_render_system.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

pub fn main() !void {
    try run();
    try alloc.deinit();

    std.log.debug("Clean exit", .{});
}

var window: Window = undefined;
var device: Device = undefined;
var renderer: Renderer = undefined;
var simple_render_system: SimpleRenderSystem = undefined;

var entities: []Entity = undefined;

fn run() !void {
    const width = 1920;
    const height = 1080;

    try window.init(width, height, "v10game");
    defer window.destroy();

    try gfx.System.init();

    device = try Device.create(&gfx.system, &window);
    defer device.destroy();

    try renderer.init(&window, &device);
    defer renderer.destroy();

    try simple_render_system.init(&device, renderer.swapchain.render_pass);
    defer simple_render_system.destroy();

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
        updateEntities();
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

fn updateEntities() void {
    for (entities) |*entity| {
        entity.transform.rotation = @mod(entity.transform.rotation + 0.001, std.math.tau);
    }
}

fn drawFrame() !void {
    var resize = false;
    if (try renderer.beginFrame()) |cb| {
        renderer.beginRenderpass(cb);

        simple_render_system.drawEntities(&cb, entities);

        renderer.endRenderPass(cb);
        renderer.endFrame(cb) catch |err| switch (err) {
            else => return err,
            error.swapchainRecreated => resize = true,
        };
    } else {
        resize = true;
    }

    if (resize) {
        // Resized swapchain
        // TODO: This can be omitted if the new renderpass is compatible with the old one
        // pipeline.destroy();
        // pipeline = try createPipeline();
        std.debug.assert(false);
    }
}
