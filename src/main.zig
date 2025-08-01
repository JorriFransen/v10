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
const Sprite = gfx.Sprite;
const Camera = gfx.Camera;
const SimpleRenderSystem2D = gfx.SimpleRenderSystem2D;
const SimpleRenderSystem3D = gfx.SimpleRenderSystem3D;
const Entity = @import("entity.zig");
const Transform = @import("transform.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Rect = math.Rect;
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

pub const EngineConfig = struct {
    ppu: f32 = 32,
    zoom: f32 = 3,
};

pub const config = EngineConfig{};

var window: Window = .{};
var device: Device = .{};
var renderer: Renderer = .{};
var d3d: SimpleRenderSystem3D = .{};
var d2d: SimpleRenderSystem2D = .{};

const camera_3d_fov_y = math.radians(50);
const camera_3d_near_clip = 0.1;
const camera_3d_far_clip = 100;
var camera_3d: Camera = .{};
var camera_3d_transform: Transform = .{};

const camera_2d_near_clip = -50;
const camera_2d_far_clip = 50;

var camera_ui: Camera = .{};
var camera_2d: Camera = .{};

var kb_move_controller: KBMoveController = .{};

var entities: []Entity = &.{};
var entity: *Entity = undefined;

var test_tile_texture: Texture = undefined;
var test_texture: Texture = undefined;

var test_tile_sprite: Sprite = undefined;
var test_tile_sprite_sub: Sprite = undefined;
var test_sprite: Sprite = undefined;
var test_sprite_sub: Sprite = undefined;

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

    test_tile_texture = try Texture.load(&device, "res/textures/test_tile.png");
    defer test_tile_texture.deinit(&device);
    test_tile_sprite = Sprite.init(&test_tile_texture, .{ .yflip = true });
    test_tile_sprite_sub = Sprite.init(&test_tile_texture, .{ .yflip = true, .uv_rect = .{ .size = Vec2.scalar(0.5) } });

    test_texture = try Texture.load(&device, "res/textures/test.png");
    defer test_texture.deinit(&device);
    test_sprite = Sprite.init(&test_texture, .{ .yflip = true, .ppu = 512 });
    test_sprite_sub = Sprite.init(&test_texture, .{ .yflip = true, .ppu = 512, .uv_rect = .{ .size = Vec2.scalar(0.5) } });

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
    camera_3d.setProjection(.{ .perspective = .{
        .fov_y = camera_3d_fov_y,
        .aspect = aspect,
    } }, camera_3d_near_clip, camera_3d_far_clip);

    camera_ui.setProjection(.{ .orthographic = .{
        .l = 0,
        .r = @as(f32, @floatFromInt(window.width)),
        .t = 0,
        .b = @as(f32, @floatFromInt(window.height)),
    } }, camera_2d_near_clip, camera_2d_far_clip);
    camera_ui.setViewYXZ(Vec3.new(0, 0, camera_2d_near_clip), Vec3.scalar(0));

    const ortho_height = @as(f32, @floatFromInt(window.height)) / (2 * config.ppu) / config.zoom;
    const ortho_width = ortho_height * aspect;
    camera_2d.setProjection(.{ .orthographic = .{
        .l = -ortho_width,
        .r = ortho_width,
        .b = -ortho_height,
        .t = ortho_height,
    } }, camera_2d_near_clip, camera_2d_far_clip);
    camera_2d.setViewYXZ(Vec3.new(0, 0, camera_2d_near_clip), Vec3.scalar(0));

    var current_time = try Instant.now();

    while (!window.shouldClose()) {
        window.waitEventsTimeout(0);

        const new_time = try Instant.now();
        const dt_ns = new_time.since(current_time);
        const dt: f32 = @as(f32, @floatFromInt(dt_ns)) / std.time.ns_per_s;
        current_time = new_time;

        camera_3d.setViewYXZ(camera_3d_transform.translation, camera_3d_transform.rotation);

        updateEntities(dt);
        drawFrame() catch unreachable;
    }

    try device.device.deviceWaitIdle();
}

fn updateEntities(dt: f32) void {
    _ = dt;
    // kb_move_controller.moveInPlaneXZ(&window, dt, &camera_3d_transform);

    // kb_move_controller.moveInPlaneXZ(&window, dt, &camera_2d_transform);
}

fn drawFrame() !void {
    if (try renderer.beginFrame()) |cb| {
        renderer.beginRenderpass(cb);

        // d3d.drawEntities(cb, entities, &camera_3d);

        const batch = d2d.beginBatch(cb, &camera_2d);
        {
            // Draw the sprites, sprite loading flips y for these sprites
            batch.drawSprite(&test_sprite, .{ .y = 4 });
            batch.drawSprite(&test_tile_sprite, .{ .x = 2, .y = 4 });

            // Draw them by texture, need to flip uv's manually, also need to specify size in worldspace (ppu not applied)
            const y_flip_uv = Rect{ .pos = .{ .x = 0, .y = 1 }, .size = .{ .x = 1, .y = -1 } };
            batch.drawQuad(.{ .y = 2 }, Vec2.scalar(1), .{ .texture = &test_texture, .uv_rect = y_flip_uv });
            batch.drawQuad(.{ .x = 2, .y = 2 }, Vec2.scalar(1), .{ .texture = &test_tile_texture, .uv_rect = y_flip_uv });

            // Cannot control uv's in this case, only specify size in worldspace
            batch.drawTextureRect(&test_texture, .{ .size = Vec2.scalar(1) });
            batch.drawTextureRect(&test_tile_texture, .{ .pos = .{ .x = 2, .y = 0 }, .size = Vec2.scalar(1) });

            // Same as drawTextureRect, but contol uvs
            batch.drawTextureRectUv(&test_texture, .{ .pos = .{ .y = -2 }, .size = Vec2.scalar(1) }, y_flip_uv);
            batch.drawTextureRectUv(&test_tile_texture, .{ .pos = .{ .x = 2, .y = -2 }, .size = Vec2.scalar(1) }, y_flip_uv);

            // Test uv_rect not covering whole texture
            batch.drawSprite(&test_sprite_sub, .{ .y = -4 });
            batch.drawSprite(&test_tile_sprite_sub, .{ .y = -4, .x = 2 });
        }
        batch.end();

        const ui_batch = d2d.beginBatch(cb, &camera_ui);
        {
            // ui_batch.drawTexture(&test_texture, Vec2.scalar(20));
            // ui_batch.drawTexture(&uv_test_texture, .{ .x = 532, .y = 20 });
            // ui_batch.drawQuad(Vec2.scalar(1124), Vec2.scalar(100), .{ .color = Vec4.new(1, 0, 0, 1) });
        }
        ui_batch.end();

        renderer.endRenderPass(cb);
        try renderer.endFrame(cb);
    }
}

fn resizeCallback(r: *const Renderer) void {
    const aspect = r.swapchain.extentSwapchainRatio();
    // std.log.debug("Resized to: {},{} - aspect: {}", .{ r.window.width, r.window.height, aspect });

    camera_3d.setProjection(.{ .perspective = .{
        .fov_y = camera_3d_fov_y,
        .aspect = aspect,
    } }, camera_3d_near_clip, camera_3d_far_clip);

    const ortho_height = @as(f32, @floatFromInt(r.window.height)) / (2 * config.ppu) / config.zoom;
    const ortho_width = ortho_height * aspect;
    camera_2d.setProjection(.{ .orthographic = .{
        .l = -ortho_width,
        .r = ortho_width,
        .b = -ortho_height,
        .t = ortho_height,
    } }, camera_2d_near_clip, camera_2d_far_clip);
    camera_ui.setProjection(.{ .orthographic = .{
        .l = 0,
        .r = @as(f32, @floatFromInt(renderer.window.width)),
        .t = 0,
        .b = @as(f32, @floatFromInt(renderer.window.height)),
    } }, camera_2d_near_clip, camera_2d_far_clip);
}
