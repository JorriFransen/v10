const std = @import("std");
const alloc = @import("alloc.zig");
const gfx = @import("gfx/gfx.zig");
const math = @import("math");

const Window = @import("window.zig");
const Renderer = gfx.Renderer;
const Device = gfx.Device;
const Entity = @import("entity.zig");
const Model = gfx.Model;
const Vertex = Model.Vertex;
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
var physics_objects: []Entity = undefined;

fn run() !void {
    const width = 1080;
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
        .{ .position = Vec2.new(0, -0.5) },
        .{ .position = Vec2.new(0.5, 0.5) },
        .{ .position = Vec2.new(-0.5, 0.5) },
    });
    defer model.destroy();

    try renderer.createCommandBuffers();

    var circle_model = try createCircleModel(64);
    defer circle_model.destroy();

    var red = Entity.new();
    red.transform.scale = Vec2.scalar(0.05);
    red.transform.translation = Vec2.new(0.5, 0.5);
    red.color = Vec3.new(1, 0, 0);
    red.model = &circle_model;

    var blue = Entity.new();
    blue.transform.scale = Vec2.scalar(0.05);
    blue.transform.translation = Vec2.new(-0.45, -0.25);
    blue.color = Vec3.new(0, 0, 1);
    blue.model = &circle_model;

    var _physics_obj = [_]Entity{ red, blue };
    physics_objects = &_physics_obj;

    while (!window.shouldClose()) {
        window.pollEvents();
        drawFrame() catch unreachable;
    }

    try device.device.deviceWaitIdle();
}

fn drawFrame() !void {
    if (try renderer.beginFrame()) |cb| {
        renderer.beginRenderpass(cb);

        simple_render_system.drawEntities(&cb, entities);
        simple_render_system.drawEntities(&cb, physics_objects);

        renderer.endRenderPass(cb);
        try renderer.endFrame(cb);
    }
}

fn refreshCallback(_: *Window) void {
    drawFrame() catch unreachable;
}

fn createCircleModel(edge_count: usize) !Model {
    const mark = alloc.temp_arena_data.queryCapacity();
    const ta = alloc.temp_arena_data.allocator();
    defer _ = alloc.temp_arena_data.reset(.{ .retain_with_limit = mark });

    var unique_vertices = try std.ArrayList(Vertex).initCapacity(ta, edge_count + 1);

    const edge_count_float: f32 = @floatFromInt(edge_count);

    for (0..edge_count) |i| {
        const fi: f32 = @floatFromInt(i);
        const angle = fi * std.math.tau / edge_count_float;
        const vertex = Vertex{ .position = Vec2.new(@cos(angle), @sin(angle)) };
        try unique_vertices.append(vertex);
    }
    try unique_vertices.append(.{ .position = Vec2.scalar(0) }); // center

    var vertices = try std.ArrayList(Vertex).initCapacity(ta, unique_vertices.items.len * 3);
    for (0..edge_count) |i| {
        try vertices.append(unique_vertices.items[i]);
        try vertices.append(unique_vertices.items[(i + 1) % edge_count]);
        try vertices.append(unique_vertices.items[edge_count]);
    }

    return try Model.create(&device, vertices.items);
}
