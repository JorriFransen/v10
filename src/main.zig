const std = @import("std");
const mem = @import("memory");
const gfx = @import("gfx.zig");
const math = @import("math.zig");
const cla = @import("command_line_args.zig");

const Instant = std.time.Instant;
const Window = @import("window.zig");
const Renderer = gfx.Renderer;
const Device = gfx.Device;
const GpuModel = gfx.GpuModel;
const Camera = gfx.Camera;
const SimpleRenderSystem = gfx.SimpleRenderSystem;
const Entity = @import("entity.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const KBMoveController = @import("keyboard_movement_controller.zig");

pub fn main() !void {
    try mem.init();

    // TODO: Remove clap dependency
    cla.parse();
    try run();

    try mem.deinit();

    std.log.debug("Clean exit", .{});
}

var window: Window = .{};
var device: Device = .{};
var renderer: Renderer = .{};
var simple_render_system: SimpleRenderSystem = .{};
var camera: Camera = .{};
var kb_move_controller: KBMoveController = .{};

var camera_entity: Entity = .{};
var entities: []Entity = &.{};
var entity: *Entity = undefined;
var arrow_t: *Entity = undefined;

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

    var smooth_vase = try GpuModel.load(&device, "res/obj/smooth_vase.obj");
    defer smooth_vase.destroy();

    var flat_vase = try GpuModel.load(&device, "res/obj/flat_vase.obj");
    defer flat_vase.destroy();

    var entities_: [1]Entity = undefined;
    for (&entities_) |*e| e.* = Entity.new();
    entities = &entities_;

    entity = &entities[0];
    entity.model = &smooth_vase;
    entity.transform.translation = .{ .z = 2.5 };
    entity.transform.scale = Vec3.scalar(3);
    entity.transform.scale = entity.transform.scale.mul(Vec3.new(1, -1, -1));

    camera_entity = Entity.new();
    camera_entity.transform.translation = .{ .z = 0 };

    const aspect = renderer.swapchain.extentSwapchainRatio();
    camera.setProjection(.{ .perspective = .{ .fov_y = math.radians(50), .aspect = aspect } }, 0.1, 100);

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
}

fn drawFrame() !void {
    if (try renderer.beginFrame()) |cb| {
        renderer.beginRenderpass(cb);

        simple_render_system.drawEntities(cb, entities, &camera);

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

fn createCubeModel(offset: Vec3) !GpuModel {
    const white = Vec3.scalar(1);
    const yellow = Vec3.new(0.8, 0.8, 0.1);
    const orange = Vec3.new(0.9, 0.6, 0.1);
    const blue = Vec3.new(0.1, 0.1, 0.8);
    const green = Vec3.new(0.1, 0.8, 0.1);
    const red = Vec3.new(0.8, 0.1, 0.1);

    var vertices = [_]GpuModel.Vertex{
        // Left face (white);
        .{ .position = Vec3.new(-0.5, -0.5, -0.5), .color = white },
        .{ .position = Vec3.new(-0.5, 0.5, 0.5), .color = white },
        .{ .position = Vec3.new(-0.5, -0.5, 0.5), .color = white },
        .{ .position = Vec3.new(-0.5, -0.5, -0.5), .color = white },
        .{ .position = Vec3.new(-0.5, 0.5, -0.5), .color = white },
        .{ .position = Vec3.new(-0.5, 0.5, 0.5), .color = white },

        // Right face (yellow)
        .{ .position = Vec3.new(0.5, -0.5, -0.5), .color = yellow },
        .{ .position = Vec3.new(0.5, -0.5, 0.5), .color = yellow },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = yellow },
        .{ .position = Vec3.new(0.5, -0.5, -0.5), .color = yellow },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = yellow },
        .{ .position = Vec3.new(0.5, 0.5, -0.5), .color = yellow },

        // Bottom face (orange)
        .{ .position = Vec3.new(-0.5, -0.5, -0.5), .color = orange },
        .{ .position = Vec3.new(-0.5, -0.5, 0.5), .color = orange },
        .{ .position = Vec3.new(0.5, -0.5, 0.5), .color = orange },
        .{ .position = Vec3.new(-0.5, -0.5, -0.5), .color = orange },
        .{ .position = Vec3.new(0.5, -0.5, 0.5), .color = orange },
        .{ .position = Vec3.new(0.5, -0.5, -0.5), .color = orange },

        // Top face (red)
        .{ .position = Vec3.new(-0.5, 0.5, -0.5), .color = red },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = red },
        .{ .position = Vec3.new(-0.5, 0.5, 0.5), .color = red },
        .{ .position = Vec3.new(-0.5, 0.5, -0.5), .color = red },
        .{ .position = Vec3.new(0.5, 0.5, -0.5), .color = red },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = red },

        // Tail face (blue)
        .{ .position = Vec3.new(-0.5, -0.5, 0.5), .color = blue },
        .{ .position = Vec3.new(-0.5, 0.5, 0.5), .color = blue },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = blue },
        .{ .position = Vec3.new(-0.5, -0.5, 0.5), .color = blue },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = blue },
        .{ .position = Vec3.new(0.5, -0.5, 0.5), .color = blue },

        // Nose face (green)
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

    return try GpuModel.create(&device, GpuModel.build(&vertices));
}

fn createCubeModelIndexed(offset: Vec3) !GpuModel {
    const white = Vec3.scalar(1);
    const yellow = Vec3.new(0.8, 0.8, 0.1);
    const orange = Vec3.new(0.9, 0.6, 0.1);
    const blue = Vec3.new(0.1, 0.1, 0.8);
    const green = Vec3.new(0.1, 0.8, 0.1);
    const red = Vec3.new(0.8, 0.1, 0.1);

    var vertices = [_]GpuModel.Vertex{
        // Left face (white);
        .{ .position = Vec3.new(-0.5, -0.5, -0.5), .color = white },
        .{ .position = Vec3.new(-0.5, 0.5, 0.5), .color = white },
        .{ .position = Vec3.new(-0.5, -0.5, 0.5), .color = white },
        .{ .position = Vec3.new(-0.5, 0.5, -0.5), .color = white },

        // Right face (yellow)
        .{ .position = Vec3.new(0.5, -0.5, -0.5), .color = yellow },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = yellow },
        .{ .position = Vec3.new(0.5, -0.5, 0.5), .color = yellow },
        .{ .position = Vec3.new(0.5, 0.5, -0.5), .color = yellow },

        // Bottom face (orange)
        .{ .position = Vec3.new(-0.5, -0.5, -0.5), .color = orange },
        .{ .position = Vec3.new(0.5, -0.5, 0.5), .color = orange },
        .{ .position = Vec3.new(-0.5, -0.5, 0.5), .color = orange },
        .{ .position = Vec3.new(0.5, -0.5, -0.5), .color = orange },

        // Top face (red)
        .{ .position = Vec3.new(-0.5, 0.5, -0.5), .color = red },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = red },
        .{ .position = Vec3.new(-0.5, 0.5, 0.5), .color = red },
        .{ .position = Vec3.new(0.5, 0.5, -0.5), .color = red },

        // Tail face (blue)
        .{ .position = Vec3.new(-0.5, -0.5, 0.5), .color = blue },
        .{ .position = Vec3.new(0.5, 0.5, 0.5), .color = blue },
        .{ .position = Vec3.new(-0.5, 0.5, 0.5), .color = blue },
        .{ .position = Vec3.new(0.5, -0.5, 0.5), .color = blue },

        // Nose face (green)
        .{ .position = Vec3.new(-0.5, -0.5, -0.5), .color = green },
        .{ .position = Vec3.new(0.5, 0.5, -0.5), .color = green },
        .{ .position = Vec3.new(-0.5, 0.5, -0.5), .color = green },
        .{ .position = Vec3.new(0.5, -0.5, -0.5), .color = green },
    };

    for (&vertices) |*vertex| {
        vertex.position = vertex.position.add(offset);
    }

    const indices = [_]u8{
        0,  1,  2,  0,  3,  1,
        4,  6,  5,  4,  5,  7,
        8,  10, 9,  8,  9,  11,
        12, 13, 14, 12, 15, 13,
        16, 18, 17, 16, 17, 19,
        20, 21, 22, 20, 23, 21,
    };

    return try GpuModel.create(&device, GpuModel.buildIndexed(&vertices, &indices));
}
