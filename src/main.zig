const std = @import("std");
const alloc = @import("alloc.zig");
const gfx = @import("gfx.zig");
const math = @import("math");
const cla = @import("command_line_args.zig");

const Window = @import("window.zig");
const Renderer = gfx.Renderer;
const Device = gfx.Device;
const Model = gfx.Model;
const Entity = @import("entity.zig");
const SimpleRenderSystem = @import("simple_render_system.zig");
const Camera = @import("camera.zig");
const Instant = std.time.Instant;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const KBMoveController = @import("keyboard_movement_controller.zig");

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
var kb_move_controller: KBMoveController = .{};

var camera_entity: Entity = undefined;
var cube: *Entity = undefined;
var entities: []Entity = &.{};

fn run() !void {
    const width = 1920;
    const height = 1080;

    try window.init(width, height, "v10game", .{
        .platform = cla.clap_options.glfw_platform,
        .refresh_callback = refreshCallback,
        .resize_callback = resizeCallback,
    });
    defer window.destroy();

    try gfx.System.init();

    device = try Device.create(&gfx.system, &window);
    defer device.destroy();

    try renderer.init(&window, &device);
    defer renderer.destroy();

    try simple_render_system.init(&device, renderer.swapchain.render_pass);
    defer simple_render_system.destroy();

    camera_entity = Entity.new();

    var model = try createCubeModel(.{});
    // var model = try Model.create(&device, &.{
    //     .{ .position = Vec3.new(0, -0.5, 0), .color = Vec3.new(1, 0, 0) },
    //     .{ .position = Vec3.new(0.5, 0.5, 0), .color = Vec3.new(0, 1, 0) },
    //     .{ .position = Vec3.new(-0.5, 0.5, 0), .color = Vec3.new(0, 0, 1) },
    // });
    defer model.destroy();

    var entities_ = [_]Entity{Entity.new()};
    entities = &entities_;

    cube = &entities[0];
    cube.model = &model;
    // triangle.color = Vec3.v(.{ 0.1, 0.8, 0.1 });
    cube.transform.translation = .{ .z = 2.5 };
    cube.transform.scale = Vec3.scalar(0.5);
    // triangle.transform.rotation = .{ .y = 0.75 * std.math.tau };

    try renderer.createCommandBuffers();

    const aspect = renderer.swapchain.extentSwapchainRatio();
    // if (aspect >= 1) {
    //     camera.setProjection(.{ .orthographic = .{ .l = -aspect, .r = aspect, .t = -1, .b = 1 } }, -1, 1);
    // } else {
    //     camera.setProjection(.{ .orthographic = .{ .l = -1, .r = 1, .t = -1 / aspect, .b = 1 / aspect } }, -1, 1);
    // }

    camera.setProjection(.{ .perspective = .{ .fov_y = math.radians(50), .aspect = aspect } }, 0.1, 10);

    var current_time = try Instant.now();

    while (!window.shouldClose()) {
        window.pollEvents();

        const new_time = try Instant.now();
        const dt_ns = new_time.since(current_time);
        const dt: f32 = @as(f32, @floatFromInt(dt_ns)) / std.time.ns_per_s;
        current_time = new_time;

        const cf = camera_entity.transform;
        camera.setViewYXZ(cf.translation, cf.rotation);

        updateEntities(dt);
        drawFrame() catch unreachable;
    }

    try device.device.deviceWaitIdle();
}

fn updateEntities(dt: f32) void {
    kb_move_controller.moveInPlaneXZ(&window, dt, &camera_entity);

    const rot_speed = 1;
    const ctf = &cube.transform;
    ctf.rotation.y = @mod(ctf.rotation.y + dt * rot_speed, std.math.tau);
    ctf.rotation.x = @mod(ctf.rotation.x + dt * rot_speed * 0.5, std.math.tau);
}

fn drawFrame() !void {
    if (try renderer.beginFrame()) |cb| {
        renderer.beginRenderpass(cb);

        simple_render_system.drawEntities(&cb, entities, &camera);

        renderer.endRenderPass(cb);
        try renderer.endFrame(cb);
    }
}

fn resizeCallback(_: *Window, _: i32, _: i32) void {
    const aspect = renderer.swapchain.extentSwapchainRatio();
    // if (aspect >= 1) {
    //     camera.setProjection(.{ .orthographic = .{ .l = -aspect, .r = aspect, .t = -1, .b = 1 } }, -1, 1);
    // } else {
    //     camera.setProjection(.{ .orthographic = .{ .l = -1, .r = 1, .t = -1 / aspect, .b = 1 / aspect } }, -1, 1);
    // }

    camera.setProjection(.{ .perspective = .{ .fov_y = math.radians(50), .aspect = aspect } }, 0.1, 10);
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
