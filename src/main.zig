const std = @import("std");
const alloc = @import("alloc.zig");
const gfx = @import("gfx/gfx.zig");
const math = @import("math");
const cla = @import("command_line_args.zig");

const Window = @import("window.zig");
const Renderer = gfx.Renderer;
const Device = gfx.Device;
const Entity = @import("entity.zig");
const Model = gfx.Model;
const SimpleRenderSystem = @import("simple_render_system.zig");
const Camera = @import("camera.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

pub fn main() !void {
    cla.parse();

    try run();
    try alloc.deinit();

    std.log.debug("Clean exit", .{});
}

var window: Window = undefined;
var device: Device = undefined;
var renderer: Renderer = undefined;
var simple_render_system: SimpleRenderSystem = undefined;
var camera: Camera = .{};

var entities: []Entity = undefined;

fn run() !void {
    const width = 1080;
    const height = 1080;

    try window.init(width, height, "v10game", .{
        .platform = cla.clap_options.glfw_platform,
    });
    defer window.destroy();
    window.refresh_callback = refreshCallback;

    try gfx.System.init();

    device = try Device.create(&gfx.system, &window);
    defer device.destroy();

    try renderer.init(&window, &device);
    defer renderer.destroy();

    try simple_render_system.init(&device, renderer.swapchain.render_pass);
    defer simple_render_system.destroy();

    camera.projection_matrix = Mat4.ortho(-1, 1, -1, 1, -1, 1);

    var model = try createCubeModel(.{});
    // var model = try Model.create(&device, &.{
    //     .{ .position = Vec3.new(0, -0.5, 0), .color = Vec3.new(1, 0, 0) },
    //     .{ .position = Vec3.new(0.5, 0.5, 0), .color = Vec3.new(0, 1, 0) },
    //     .{ .position = Vec3.new(-0.5, 0.5, 0), .color = Vec3.new(0, 0, 1) },
    // });
    defer model.destroy();

    var _entities = [_]Entity{
        Entity.new(),
    };
    const triangle = &_entities[0];
    triangle.model = &model;
    // triangle.color = Vec3.v(.{ 0.1, 0.8, 0.1 });
    triangle.transform.translation = .{ .z = 0.5 };
    triangle.transform.scale = Vec3.scalar(0.5);
    // triangle.transform.rotation = .{ .y = 0.75 * std.math.tau };

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
    if (!window.paused) {
        const speed = 1.0;
        for (entities) |*entity| {
            entity.transform.rotation.y = @mod(entity.transform.rotation.y + 0.001 * speed, std.math.tau);
            entity.transform.rotation.x = @mod(entity.transform.rotation.x + 0.001 / 2.0 * speed, std.math.tau);
        }
    }
}

fn drawFrame() !void {
    if (try renderer.beginFrame()) |cb| {
        renderer.beginRenderpass(cb);

        simple_render_system.drawEntities(&cb, entities, &camera);

        renderer.endRenderPass(cb);
        try renderer.endFrame(cb);
    }
}

fn refreshCallback(_: *Window) void {
    drawFrame() catch unreachable;
}

fn createCubeModel(offset: Vec3) !Model {
    const white = Vec3.scalar(1);
    const yellow = Vec3.new(0.8, 0.8, 0.1);
    const orange = Vec3.new(0.9, 0.6, 0.1);
    const blue = Vec3.new(0.1, 0.1, 0.8);
    const green = Vec3.new(0.1, 0.8, 0.1);
    const red = Vec3.new(0.8, 0.1, 0.1);

    var vertices = [_]Model.Vertex{
        // Left face (white);
        .{ .position = Vec3.new(-0.5, -0.5, -0.5), .color = white },
        .{ .position = Vec3.new(-0.5, 0.5, 0.5), .color = white },
        .{ .position = Vec3.new(-0.5, -0.5, 0.5), .color = white },
        .{ .position = Vec3.new(-0.5, -0.5, -0.5), .color = white },
        .{ .position = Vec3.new(-0.5, 0.5, -0.5), .color = white },
        .{ .position = Vec3.new(-0.5, 0.5, 0.5), .color = white },

        // Right face (yellow)
        .{ .position = Vec3.new(0.5, -0.5, -0.5), .color = yellow },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = yellow },
        .{ .position = Vec3.new(0.5, -0.5, 0.5), .color = yellow },
        .{ .position = Vec3.new(0.5, -0.5, -0.5), .color = yellow },
        .{ .position = Vec3.new(0.5, 0.5, -0.5), .color = yellow },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = yellow },

        // Top face (orange, y axis points down)
        .{ .position = Vec3.new(-0.5, -0.5, -0.5), .color = orange },
        .{ .position = Vec3.new(0.5, -0.5, 0.5), .color = orange },
        .{ .position = Vec3.new(-0.5, -0.5, 0.5), .color = orange },
        .{ .position = Vec3.new(-0.5, -0.5, -0.5), .color = orange },
        .{ .position = Vec3.new(0.5, -0.5, -0.5), .color = orange },
        .{ .position = Vec3.new(0.5, -0.5, 0.5), .color = orange },

        // Bottom face (red)
        .{ .position = Vec3.new(-0.5, 0.5, -0.5), .color = red },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = red },
        .{ .position = Vec3.new(-0.5, 0.5, 0.5), .color = red },
        .{ .position = Vec3.new(-0.5, 0.5, -0.5), .color = red },
        .{ .position = Vec3.new(0.5, 0.5, -0.5), .color = red },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = red },

        // Nose face (blue)
        .{ .position = Vec3.new(-0.5, -0.5, 0.5), .color = blue },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = blue },
        .{ .position = Vec3.new(-0.5, 0.5, 0.5), .color = blue },
        .{ .position = Vec3.new(-0.5, -0.5, 0.5), .color = blue },
        .{ .position = Vec3.new(0.5, -0.5, 0.5), .color = blue },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = blue },

        // Tail face (green)
        .{ .position = Vec3.new(-0.5, -0.5, -0.5), .color = green },
        .{ .position = Vec3.new(0.5, 0.5, -0.5), .color = green },
        .{ .position = Vec3.new(-0.5, 0.5, -0.5), .color = green },
        .{ .position = Vec3.new(-0.5, -0.5, -0.5), .color = green },
        .{ .position = Vec3.new(0.5, -0.5, -0.5), .color = green },
        .{ .position = Vec3.new(0.5, 0.5, -0.5), .color = green },
    };

    for (&vertices) |*vertex| {
        vertex.position = vertex.position.add(offset);
    }

    return try Model.create(&device, &vertices);
}
