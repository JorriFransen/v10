const std = @import("std");
const mem = @import("memory");
const gfx = @import("gfx.zig");
const math = @import("math.zig");
const clip = @import("cli_parse");
const glfw = @import("glfw");

const Instant = std.time.Instant;
const Window = @import("window.zig");
const Renderer = gfx.Renderer;
const Device = gfx.Device;
const Model = gfx.Model;
const Texture = gfx.Texture;
const Camera = gfx.Camera;
const SimpleRenderSystem2D = gfx.SimpleRenderSystem2D;
const SimpleRenderSystem3D = gfx.SimpleRenderSystem3D;
const Entity = @import("entity.zig");
const Transform = @import("transform.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const KBMoveController = @import("keyboard_movement_controller.zig");

const assert = std.debug.assert;

const OptionParser = clip.OptionParser(&.{
    clip.option(glfw.Platform.any, "glfw_platform", 'p', "Specify the platform hint for glfw.\n"),
    clip.option(false, "help", 'h', "Print this help message and exit.\n"),
});

pub var cli_options: OptionParser.Options = undefined;

pub fn main() !void {
    try mem.init();

    var tmp = mem.get_temp();
    cli_options = OptionParser.parse(mem.common_arena.allocator(), tmp.allocator()) catch {
        try OptionParser.usage(std.fs.File.stderr());
        return;
    };
    tmp.release();

    if (cli_options.help) {
        try OptionParser.usage(std.fs.File.stdout());
        return;
    }

    try run();

    try mem.deinit();

    std.log.debug("Clean exit", .{});
}

var window: Window = .{};
var device: Device = .{};
var renderer: Renderer = .{};
var d3d: SimpleRenderSystem3D = .{};
var d2d: SimpleRenderSystem2D = .{};
var camera_3d: Camera = .{};
var camera_2d: Camera = .{};
var kb_move_controller: KBMoveController = .{};

var camera_3d_transform: Transform = .{};
var camera_2d_transform: Transform = .{};
var entities: []Entity = &.{};
var entity: *Entity = undefined;
var arrow_t: *Entity = undefined;

var test_texture: Texture = undefined;
var uv_test_texture: Texture = undefined;

fn run() !void {
    const width = 1920;
    const height = 1080;

    try window.init(width, height, "v10game", .{
        .platform = cli_options.glfw_platform,
    });
    defer window.destroy();

    try gfx.System.init();

    device = try Device.create(&gfx.system, &window);
    defer device.destroy();

    try renderer.init(&window, &device, resizeCallback);
    defer renderer.destroy();

    try d3d.init(&device, renderer.swapchain.render_pass);
    defer d3d.destroy();

    try d2d.init(&device, renderer.swapchain.render_pass);
    defer d2d.destroy();

    test_texture = try Texture.load(&device, "res/textures/test.png");
    defer test_texture.deinit(&device);

    uv_test_texture = try Texture.load(&device, "res/textures/uvtest.png");
    defer uv_test_texture.deinit(&device);

    var smooth_vase = try Model.load(&device, "res/obj/smooth_vase.obj");
    defer smooth_vase.deinit(&device);

    var flat_vase = try Model.load(&device, "res/obj/flat_vase.obj");
    defer flat_vase.deinit(&device);

    var entities_: [1]Entity = undefined;
    for (&entities_) |*e| e.* = Entity.new();
    entities = &entities_;

    entity = &entities[0];
    entity.model = &smooth_vase;
    entity.transform.translation = .{ .z = 2.5 };
    entity.transform.scale = Vec3.scalar(3);
    entity.transform.scale = entity.transform.scale.mul(Vec3.new(1, -1, -1));

    camera_3d_transform.translation = .{ .z = 0 };

    const aspect = renderer.swapchain.extentSwapchainRatio();
    camera_3d.setProjection(.{ .perspective = .{ .fov_y = math.radians(50), .aspect = aspect } }, 0.1, 100);

    camera_2d_transform.translation.z = -10;
    camera_2d.setProjection(.{ .orthographic = .{ .l = 0, .r = @as(f32, @floatFromInt(window.width)), .t = 0, .b = @as(f32, @floatFromInt(window.height)) } }, -50, 50);

    var current_time = try Instant.now();

    while (!window.shouldClose()) {
        window.waitEventsTimeout(0);

        const new_time = try Instant.now();
        const dt_ns = new_time.since(current_time);
        const dt: f32 = @as(f32, @floatFromInt(dt_ns)) / std.time.ns_per_s;
        current_time = new_time;

        camera_3d.setViewYXZ(camera_3d_transform.translation, camera_3d_transform.rotation);

        camera_2d.setViewYXZ(camera_2d_transform.translation, camera_2d_transform.rotation);

        updateEntities(dt);
        drawFrame() catch unreachable;
    }

    try device.device.deviceWaitIdle();
}

fn updateEntities(dt: f32) void {
    // kb_move_controller.moveInPlaneXZ(&window, dt, &camera_3d_transform);

    kb_move_controller.moveInPlaneXZ(&window, dt, &camera_2d_transform);
}

fn drawFrame() !void {
    if (try renderer.beginFrame()) |cb| {
        renderer.beginRenderpass(cb);

        d3d.drawEntities(cb, entities, &camera_3d);

        d2d.beginBatch(&camera_2d);
        {
            d2d.drawTexture(&test_texture, Vec2.scalar(20));
            d2d.drawTexture(&uv_test_texture, .{ .x = 532, .y = 20 });
            // d2d.drawQuad(Vec2.scalar(1124), Vec2.scalar(100), .{ .color = Vec4.new(1, 0, 0, 1) });
        }
        d2d.endBatch(cb);

        renderer.endRenderPass(cb);
        try renderer.endFrame(cb);
    }
}

fn resizeCallback(r: *const Renderer) void {
    std.log.debug("Resized to: {},{}", .{ r.window.width, r.window.height });
    const aspect = r.swapchain.extentSwapchainRatio();

    camera_3d.setProjection(.{ .perspective = .{ .fov_y = math.radians(50), .aspect = aspect } }, 0.1, 10);

    if (aspect >= 1) {
        camera_2d.setProjection(.{ .orthographic = .{ .l = 0, .r = @as(f32, @floatFromInt(renderer.window.width)), .t = 0, .b = @as(f32, @floatFromInt(renderer.window.height)) } }, -50, 50);
    } else {
        camera_2d.setProjection(.{ .orthographic = .{ .l = 0, .r = @as(f32, @floatFromInt(renderer.window.width)), .t = 0, .b = @as(f32, @floatFromInt(renderer.window.height)) } }, -50, 50);
    }

    // std.log.debug("Resized: {},{}  --  swapchain_extent: {},{}  --  swapchain_window: {},{}", .{
    //     renderer.window.width,
    //     renderer.window.height,
    //     r.swapchain.swapchain_extent.width,
    //     r.swapchain.swapchain_extent.height,
    //     r.swapchain.window_extent.width,
    //     r.swapchain.window_extent.height,
    // });
}
