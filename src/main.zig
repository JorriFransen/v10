const std = @import("std");
const alloc = @import("alloc.zig");
const gfx = @import("gfx/gfx.zig");
const math = @import("math");

const Window = @import("window.zig");
const Renderer = gfx.Renderer;
const Device = gfx.Device;
const Entity = @import("entity.zig");
const Model = gfx.Model;
const SimpleRenderSystem = @import("simple_render_system.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;

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
    window.refresh_callback = refreshCallback;

    try gfx.System.init();

    device = try Device.create(&gfx.system, &window);
    defer device.destroy();

    try renderer.init(&window, &device);
    defer renderer.destroy();

    try simple_render_system.init(&device, renderer.swapchain.render_pass);
    defer simple_render_system.destroy();

    var model = try Model.create(&device, &.{
        .{ .position = Vec3.new(0, -0.5, 0) },
        .{ .position = Vec3.new(0.5, 0.5, 0) },
        .{ .position = Vec3.new(-0.5, 0.5, 0) },
    });
    defer model.destroy();

    var _entities = [_]Entity{
        Entity.new(),
    };
    const triangle = &_entities[0];
    triangle.model = &model;
    triangle.color = Vec3.v(.{ 0.1, 0.8, 0.1 });
    triangle.transform.translation = .{ .x = 0.1, .y = 0.0, .z = 0 };
    // triangle.transform.scale = .{ .x = 2, .y = 0.5 };
    // triangle.transform.rotation = 0.25 * std.math.tau;

    entities = &_entities;

    try renderer.createCommandBuffers();

    while (!window.shouldClose()) {
        window.pollEvents();
        updateEntities();
        drawFrame() catch unreachable;
    }

    try device.device.deviceWaitIdle();
}

fn updateEntities() void {
    // for (entities) |*entity| {
    //     entity.transform.rotation = @mod(entity.transform.rotation + 0.001, std.math.tau);
    // }
}

fn drawFrame() !void {
    if (try renderer.beginFrame()) |cb| {
        renderer.beginRenderpass(cb);

        simple_render_system.drawEntities(&cb, entities);

        renderer.endRenderPass(cb);
        try renderer.endFrame(cb);
    }
}

fn refreshCallback(_: *Window) void {
    drawFrame() catch unreachable;
}
