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
const GpuModel = gfx.GpuModel;
const Camera = gfx.Camera;
const SimpleRenderSystem2D = gfx.SimpleRenderSystem2D;
const SimpleRenderSystem3D = gfx.SimpleRenderSystem3D;
const Entity = @import("entity.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const KBMoveController = @import("keyboard_movement_controller.zig");

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
        .platform = cli_options.glfw_platform,
        .refresh_callback = refreshCallback,
        .resize_callback = resizeCallback,
    });
    defer window.destroy();

    try gfx.System.init();

    device = try Device.create(&gfx.system, &window);
    defer device.destroy();

    try renderer.init(&window, &device);
    defer renderer.destroy();

    try d3d.init(&device, renderer.swapchain.render_pass);
    defer d3d.destroy();

    try d2d.init(&device, renderer.swapchain.render_pass);
    defer d2d.destroy();

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

        d3d.drawEntities(cb, entities, &camera);

        d2d.beginDrawing();
        {
            d2d.drawTriangle(Vec2.new(-0.5, 0), Vec2.new(0, -0.5), Vec2.new(0.5, 0), .{ .color = Vec4.new(1, 0, 0, 0.4) });
            d2d.drawTriangle(Vec2.new(-0.9, 0.9), Vec2.new(-0.9, 0.8), Vec2.new(-0.8, 0.9), .{ .color = Vec4.new(0, 1, 0, 1) });

            d2d.drawQuad(Vec2.new(-0.95, -0.95), Vec2.scalar(0.2), .{ .color = Vec4.new(0, 0, 1, 1) });
        }
        d2d.endDrawing(cb);

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
