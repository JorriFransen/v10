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
const Font = gfx.Font;
const Camera2D = gfx.Camera2D;
const Camera3D = gfx.Camera3D;
const Renderer2D = gfx.Renderer2D;
const Renderer3D = gfx.Renderer3D;
const Entity = @import("entity.zig");
const Transform = @import("transform.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Rect = math.Rect;
const KB3DMoveController = @import("3d_keyboard_move_controller.zig");
const KB2DMoveController = @import("2d_keyboard_move_controller.zig");
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

var window: Window = undefined;
var device: Device = .{};
var renderer: Renderer = .{};
var r3d: Renderer3D = .{};
var r2d: Renderer2D = .{};

const camera_3d_fov_y = math.radians(50);
const camera_3d_near_clip = 0.1;
const camera_3d_far_clip = 100;
var camera_3d: Camera3D = .{};
var camera_3d_transform: Transform = .{};

const camera_2d_near_clip = -50;
const camera_2d_far_clip = 50;

var camera_ui: Camera2D = undefined;
var camera_2d: Camera2D = undefined;

var kb_3d_move_controller: KB3DMoveController = .{};
var kb_2d_move_controller: KB2DMoveController = .{};

var entities: []Entity = &.{};
var entity: *Entity = undefined;

var test_font: Font = undefined;
var font_tex: Texture = undefined;

var test_tile_texture: Texture = undefined;
var test_texture: Texture = undefined;

var test_tile_sprite: Sprite = undefined;
var test_tile_sprite_sub_tl: Sprite = undefined;
var test_tile_sprite_sub_tr: Sprite = undefined;
var test_tile_sprite_sub_bl: Sprite = undefined;
var test_tile_sprite_sub_br: Sprite = undefined;
var test_sprite: Sprite = undefined;
var test_sprite_sub_tl: Sprite = undefined;
var test_sprite_sub_tr: Sprite = undefined;
var test_sprite_sub_bl: Sprite = undefined;
var test_sprite_sub_br: Sprite = undefined;

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

    try r3d.init(&device, renderer.swapchain.render_pass);
    defer r3d.destroy();

    try r2d.init(&device, renderer.swapchain.render_pass);
    defer r2d.destroy();

    camera_ui = Camera2D.init(.{
        .screen_width = window.size.x,
        .screen_height = window.size.y,
        .zoom = 1,
        .near_clip = camera_2d_near_clip,
        .far_clip = camera_2d_far_clip,
        .origin = .top_left,
    });

    camera_2d = Camera2D.init(.{
        .screen_width = window.size.x,
        .screen_height = window.size.y,
        .zoom = config.zoom,
        .ppu = config.ppu,
        .near_clip = camera_2d_near_clip,
        .far_clip = camera_2d_far_clip,
    });

    // Mono bitmap font
    test_font = try Font.load(&device, "res/fonts/ProFont/96.fnt");
    defer test_font.deinit(&device);

    font_tex = try Texture.load(&device, "res/fonts/ProFont/96_0.png", .nearest);
    defer font_tex.deinit(&device);

    test_tile_texture = try Texture.load(&device, "res/textures/test_tile.png", .nearest);
    defer test_tile_texture.deinit(&device);
    test_tile_sprite = Sprite.init(&test_tile_texture, .{ .yflip = true });
    test_tile_sprite_sub_tl = Sprite.init(&test_tile_texture, .{ .yflip = true, .uv_rect = .{ .size = Vec2.scalar(0.5) } });
    test_tile_sprite_sub_tr = Sprite.init(&test_tile_texture, .{ .yflip = true, .uv_rect = .{ .pos = .{ .x = 0.5 }, .size = Vec2.scalar(0.5) } });
    test_tile_sprite_sub_bl = Sprite.init(&test_tile_texture, .{ .yflip = true, .uv_rect = .{ .pos = .{ .y = 0.5 }, .size = Vec2.scalar(0.5) } });
    test_tile_sprite_sub_br = Sprite.init(&test_tile_texture, .{ .yflip = true, .uv_rect = .{ .pos = Vec2.scalar(0.5), .size = Vec2.scalar(0.5) } });

    test_texture = try Texture.load(&device, "res/textures/test.png", .linear);
    defer test_texture.deinit(&device);
    test_sprite = Sprite.init(&test_texture, .{ .yflip = true, .ppu = 512 });
    test_sprite_sub_tl = Sprite.init(&test_texture, .{ .yflip = true, .ppu = 512, .uv_rect = .{ .size = Vec2.scalar(0.5) } });
    test_sprite_sub_tr = Sprite.init(&test_texture, .{ .yflip = true, .ppu = 512, .uv_rect = .{ .pos = .{ .x = 0.5 }, .size = Vec2.scalar(0.5) } });
    test_sprite_sub_bl = Sprite.init(&test_texture, .{ .yflip = true, .ppu = 512, .uv_rect = .{ .pos = .{ .y = 0.5 }, .size = Vec2.scalar(0.5) } });
    test_sprite_sub_br = Sprite.init(&test_texture, .{ .yflip = true, .ppu = 512, .uv_rect = .{ .pos = Vec2.scalar(0.5), .size = Vec2.scalar(0.5) } });

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
        .near = camera_3d_near_clip,
        .far = camera_3d_far_clip,
    } });

    var current_time = try Instant.now();

    while (!window.shouldClose()) {
        window.waitEventsTimeout(0);

        const new_time = try Instant.now();
        const dt_ns = new_time.since(current_time);
        const dt: f32 = @as(f32, @floatFromInt(dt_ns)) / std.time.ns_per_s;
        current_time = new_time;

        update(dt);
        drawFrame() catch unreachable;
    }

    try device.device.deviceWaitIdle();
}

fn update(dt: f32) void {
    camera_3d.setViewYXZ(camera_3d_transform.translation, camera_3d_transform.rotation);
    // kb_3d_move_controller.moveInPlaneXZ(&window, dt, &camera_3d_transform);

    var pos: Vec2 = camera_2d.pos;
    var zoom: f32 = camera_2d.zoom;
    kb_2d_move_controller.updateInput(&window, dt, &pos, &zoom);
    camera_2d.setPosition(pos);
    camera_2d.setZoom(zoom);
    camera_2d.update(window.size.x, window.size.y);

    camera_ui.update(window.size.x, window.size.y);
}

fn drawFrame() !void {
    if (try renderer.beginFrame()) |cb| {
        // const clear_color = @Vector(4, f32){ 0, 0, 0, 1 };
        const clear_color = @Vector(4, f32){ 0.01, 0.04, 0.04, 1 };
        renderer.beginRenderpass(cb, clear_color);

        // r3d.drawEntities(cb, entities, &camera_3d);

        r2d.beginFrame(cb);

        const spos = window.getCursorPos();
        var batch = r2d.beginBatch(cb, &camera_2d);
        {
            drawDebugWorldGrid(&batch);
            drawTestScene(&batch);

            const wpos = camera_2d.toWorldSpace(spos);
            batch.drawDebugLine(Vec2.scalar(0), wpos, .{});

            batch.drawRect(Rect.new(wpos, Vec2.scalar(5)), .{ .texture = &font_tex });
        }
        batch.end();

        var ui_batch = r2d.beginBatch(cb, &camera_ui);
        {
            const ui_pos = camera_ui.toWorldSpace(spos);
            ui_batch.drawDebugLine(Vec2.scalar(100), ui_pos, .{ .color = Vec4.new(1, 0, 0, 1) });

            ui_batch.drawRect(Rect.new(Vec2.new(10, 10), font_tex.getSize()), .{ .texture = &font_tex });
        }
        ui_batch.end();

        r2d.endFrame();

        renderer.endRenderPass(cb);
        try renderer.endFrame(cb);
    }
}
const outline = Renderer2D.DrawLineOptions{ .color = Vec4.new(1, 1, 1, 1), .width = 2 };
const ruler_line = Renderer2D.DrawLineOptions{ .color = outline.color.mulScalar(0.5) };
const quadrant_line = Renderer2D.DrawLineOptions{ .color = Vec4.new(0.5, 0, 0.5, 1), .width = 2 };
const triangle_line = Renderer2D.DrawLineOptions{ .color = Vec4.new(0, 0, 0, 1), .width = 2 };
const divider_line = Renderer2D.DrawLineOptions{ .color = Vec4.new(1, 0, 0, 1) };

fn drawDebugWorldGrid(batch: *Renderer2D.Batch) void {
    const campos = camera_2d.pos;
    const o_dim = camera_2d.getViewportWorldSize();

    assert(o_dim.x != 0);
    assert(o_dim.y != 0);

    const left = -(o_dim.x / 2) + campos.x;
    const right = (o_dim.x / 2) + campos.x;
    const top = (o_dim.y / 2) + campos.y;
    const bottom = -(o_dim.y / 2) + campos.y;

    const left_i = @ceil(left);
    const right_i = @floor(right);
    const top_i = @floor(top);
    const bottom_i = @ceil(bottom);

    const vcount = @abs(left_i - right_i) + 1;
    const hcount = @abs(bottom_i - top_i) + 1;

    for (0..@as(usize, @intFromFloat(vcount))) |i| {
        const x = @as(f32, @floatFromInt(i)) + left_i;
        batch.drawDebugLine(Vec2.new(x, top), Vec2.new(x, bottom), ruler_line);
    }

    for (0..@as(usize, @intFromFloat(hcount))) |i| {
        const y = @as(f32, @floatFromInt(i)) + bottom_i;
        batch.drawDebugLine(Vec2.new(left, y), Vec2.new(right, y), ruler_line);
    }
}

fn drawTestScene(batch: *Renderer2D.Batch) void {
    @setEvalBranchQuota(10000);

    const xstep = Vec2.new(2, 0);
    const ystep = Vec2.new(0, -2);
    const p = Vec2.new(-2, 4);

    const p0_0 = p;
    const p0_1 = p0_0.add(ystep);
    const p0_2 = p0_1.add(ystep);
    const p0_3 = p0_2.add(ystep);
    const p0_4 = p0_3.add(ystep);

    const p1_0 = p0_0.add(xstep);
    const p1_1 = p1_0.add(ystep);
    const p1_2 = p1_1.add(ystep);
    const p1_3 = p1_2.add(ystep);
    const p1_4 = p1_3.add(ystep);

    const p2_0 = p1_0.add(xstep);
    const p2_1 = p2_0.add(ystep);
    const p2_2 = p2_1.add(ystep);
    const p2_3 = p2_2.add(ystep);
    const p2_4 = p2_3.add(ystep);

    const sub_size = Vec2.scalar(0.5);
    const sub_tl_rect = Rect.new(p0_4.add(Vec2.new(-0.05, 0.55)), sub_size);
    const sub_tr_rect = sub_tl_rect.move(.{ .x = 0.6 });
    const sub_bl_rect = sub_tl_rect.move(.{ .y = -0.6 });
    const sub_br_rect = sub_bl_rect.move(.{ .x = 0.6 });

    const tile_sub_tl_rect = sub_tl_rect.move(xstep);
    const tile_sub_tr_rect = sub_tr_rect.move(xstep);
    const tile_sub_bl_rect = sub_bl_rect.move(xstep);
    const tile_sub_br_rect = sub_br_rect.move(xstep);

    const dim = Vec2.scalar(1);

    // Draw the sprites, sprite loading flips y for these sprites
    batch.drawSprite(&test_sprite, p0_0);
    drawRectLine(batch, Rect.new(p0_0, dim), outline);
    batch.drawSprite(&test_tile_sprite, p1_0);
    drawRectLine(batch, Rect.new(p1_0, dim), outline);

    // Draw them by texture, need to flip uv's manually, also need to specify size in worldspace (ppu not applied)
    const y_flip_uv = Rect{ .pos = .{ .x = 0, .y = 1 }, .size = .{ .x = 1, .y = -1 } };
    batch.drawRect(.{ .pos = p0_1, .size = dim }, .{ .texture = &test_texture, .uv_rect = y_flip_uv });
    drawRectLine(batch, Rect.new(p0_1, dim), outline);
    batch.drawRect(.{ .pos = p1_1, .size = dim }, .{ .texture = &test_tile_texture, .uv_rect = y_flip_uv });
    drawRectLine(batch, Rect.new(p1_1, dim), outline);

    // Cannot control uv's in this case, only specify size in worldspace
    batch.drawRect(.{ .pos = p0_2, .size = dim }, .{ .texture = &test_texture });
    drawRectLine(batch, Rect.new(p0_2, dim), outline);
    batch.drawRect(.{ .pos = p1_2, .size = dim }, .{ .texture = &test_tile_texture });
    drawRectLine(batch, Rect.new(p1_2, dim), outline);

    batch.drawRect(.{ .pos = p0_3, .size = dim }, .{ .color = Vec4.new(1, 0, 0, 1) });
    drawRectLine(batch, Rect.new(p0_3, dim), outline);
    batch.drawRect(.{ .pos = p1_3, .size = dim }, .{ .color = Vec4.new(0, 1, 0, 1) });
    drawRectLine(batch, Rect.new(p1_3, dim), outline);

    // Test uv_rect not covering whole texture
    batch.drawDebugLine(sub_tl_rect.tr().add(.{ .x = 0.05, .y = 0.05 }), sub_bl_rect.br().add(.{ .x = 0.05, .y = -0.05 }), divider_line);
    batch.drawDebugLine(sub_tl_rect.bl().add(.{ .x = -0.05, .y = -0.05 }), sub_tr_rect.br().add(.{ .x = 0.05, .y = -0.05 }), divider_line);
    batch.drawSpriteRect(&test_sprite_sub_tl, sub_tl_rect);
    drawRectLine(batch, sub_tl_rect, quadrant_line);
    batch.drawSpriteRect(&test_sprite_sub_tr, sub_tr_rect);
    drawRectLine(batch, sub_tr_rect, quadrant_line);
    batch.drawSpriteRect(&test_sprite_sub_bl, sub_bl_rect);
    drawRectLine(batch, sub_bl_rect, quadrant_line);
    batch.drawSpriteRect(&test_sprite_sub_br, sub_br_rect);
    drawRectLine(batch, sub_br_rect, quadrant_line);
    drawRectLine(batch, Rect.new(p0_4, dim), outline);

    batch.drawDebugLine(tile_sub_tl_rect.tr().add(.{ .x = 0.05, .y = 0.05 }), tile_sub_bl_rect.br().add(.{ .x = 0.05, .y = -0.05 }), divider_line);
    batch.drawDebugLine(tile_sub_tl_rect.bl().add(.{ .x = -0.05, .y = -0.05 }), tile_sub_tr_rect.br().add(.{ .x = 0.05, .y = -0.05 }), divider_line);
    batch.drawSpriteRect(&test_tile_sprite_sub_tl, tile_sub_tl_rect);
    drawRectLine(batch, tile_sub_tl_rect, quadrant_line);
    batch.drawSpriteRect(&test_tile_sprite_sub_tr, tile_sub_tr_rect);
    drawRectLine(batch, tile_sub_tr_rect, quadrant_line);
    batch.drawSpriteRect(&test_tile_sprite_sub_bl, tile_sub_bl_rect);
    drawRectLine(batch, tile_sub_bl_rect, quadrant_line);
    batch.drawSpriteRect(&test_tile_sprite_sub_br, tile_sub_br_rect);
    drawRectLine(batch, tile_sub_br_rect, quadrant_line);
    drawRectLine(batch, Rect.new(p1_4, dim), outline);

    batch.drawTriangle(p2_0, p2_0.add(Vec2.new(0.5, 1)), p2_0.add(.{ .x = 1 }), .{ .color = Vec4.new(1, 0, 0, 1) });
    drawRectLine(batch, Rect.new(p2_0, dim), outline);
    drawTriangleLine(batch, p2_0, p2_0.add(Vec2.new(0.5, 1)), p2_0.add(.{ .x = 1 }), triangle_line);
    batch.drawTriangle(p2_1, p2_1.add(Vec2.new(0.5, 1)), p2_1.add(.{ .x = 1 }), .{
        .texture = &test_texture,
        .uv_coords = .{ Vec2.new(0, 1), Vec2.new(0.5, 0), Vec2.new(1, 1) },
    });
    drawRectLine(batch, Rect.new(p2_1, dim), outline);
    drawTriangleLine(batch, p2_1, p2_1.add(Vec2.new(0.5, 1)), p2_1.add(.{ .x = 1 }), triangle_line);
    batch.drawTriangle(p2_2.add(.{ .y = 1 }), p2_2.add(dim), p2_2.add(.{ .x = 1 }), .{
        .texture = &test_tile_texture,
        .uv_coords = .{ Vec2.new(0, 1), Vec2.new(1, 1), Vec2.new(1, 0) },
    });
    drawRectLine(batch, Rect.new(p2_2, dim), outline);
    drawTriangleLine(batch, p2_2.add(.{ .y = 1 }), p2_2.add(dim), p2_2.add(.{ .x = 1 }), triangle_line);
    batch.drawTriangle(p2_3, p2_3.add(Vec2.new(0.5, 1)), p2_3.add(.{ .x = 1 }), .{
        .texture = &test_tile_texture,
        .uv_coords = .{ Vec2.new(0, 1), Vec2.new(1, 1), Vec2.new(1, 0) },
    });
    drawRectLine(batch, Rect.new(p2_3, dim), outline);
    drawTriangleLine(batch, p2_3, p2_3.add(Vec2.new(0.5, 1)), p2_3.add(.{ .x = 1 }), triangle_line);

    const tl = p2_4.add(Vec2.new(-0.05, 1.05));
    const tr = tl.add(.{ .x = 1.1 });
    const bl = tl.add(.{ .y = -1.1 });
    const br = bl.add(.{ .x = 1.1 });
    batch.drawDebugLine(tl.add(.{ .x = 0.55, .y = 0.05 }), bl.add(.{ .x = 0.55, .y = -0.05 }), divider_line);
    batch.drawDebugLine(tl.add(.{ .x = -0.05, .y = -0.55 }), tr.add(.{ .x = 0.05, .y = -0.55 }), divider_line);

    const tl_uv = test_sprite_sub_tl.uv_rect;
    batch.drawTriangle(tl, tl.add(.{ .x = 0.5 }), tl.add(.{ .x = 0.5, .y = -0.5 }), .{
        .texture = &test_texture,
        .uv_coords = .{ tl_uv.tl(), tl_uv.tr(), tl_uv.br() },
    });
    drawRectLine(batch, Rect.new(tl.add(.{ .y = -0.5 }), Vec2.scalar(0.5)), quadrant_line);
    drawTriangleLine(batch, tl, tl.add(.{ .x = 0.5 }), tl.add(.{ .x = 0.5, .y = -0.5 }), triangle_line);

    const tr_uv = test_sprite_sub_tr.uv_rect;
    batch.drawTriangle(tr.add(.{ .x = -0.5 }), tr, tr.add(Vec2.scalar(-0.5)), .{
        .texture = &test_texture,
        .uv_coords = .{ tr_uv.tl(), tr_uv.tr(), tr_uv.bl() },
    });
    drawRectLine(batch, Rect.new(tr.addScalar(-0.5), Vec2.scalar(0.5)), quadrant_line);
    drawTriangleLine(batch, tr.add(.{ .x = -0.5 }), tr, tr.add(Vec2.scalar(-0.5)), triangle_line);

    const bl_uv = test_sprite_sub_bl.uv_rect;
    batch.drawTriangle(bl, bl.add(Vec2.scalar(0.5)), bl.add(.{ .x = 0.5 }), .{
        .texture = &test_texture,
        .uv_coords = .{ bl_uv.bl(), bl_uv.tr(), bl_uv.br() },
    });
    drawRectLine(batch, Rect.new(bl, Vec2.scalar(0.5)), quadrant_line);
    drawTriangleLine(batch, bl, bl.add(Vec2.scalar(0.5)), bl.add(.{ .x = 0.5 }), triangle_line);

    const br_uv = test_sprite_sub_br.uv_rect;
    batch.drawTriangle(br.add(.{ .x = -0.5 }), br.add(.{ .x = -0.5, .y = 0.5 }), br, .{
        .texture = &test_texture,
        .uv_coords = .{ br_uv.bl(), br_uv.tl(), br_uv.br() },
    });
    drawRectLine(batch, Rect.new(br.add(.{ .x = -0.5 }), Vec2.scalar(0.5)), quadrant_line);
    drawTriangleLine(batch, br.add(.{ .x = -0.5 }), br.add(.{ .x = -0.5, .y = 0.5 }), br, triangle_line);

    drawRectLine(batch, Rect.new(p2_4, dim), outline);
}

fn drawRectLine(batch: *Renderer2D.Batch, rect: Rect, options: Renderer2D.DrawLineOptions) void {
    const bl = rect.bl();
    const br = rect.br();
    const tl = rect.tl();
    const tr = rect.tr();
    batch.drawDebugLine(bl, tl, .{ .color = options.color, .width = options.width });
    batch.drawDebugLine(tl, tr, .{ .color = options.color, .width = options.width });
    batch.drawDebugLine(tr, br, .{ .color = options.color, .width = options.width });
    batch.drawDebugLine(br, bl, .{ .color = options.color, .width = options.width });
}

fn drawTriangleLine(batch: *Renderer2D.Batch, p0: Vec2, p1: Vec2, p2: Vec2, options: Renderer2D.DrawLineOptions) void {
    batch.drawDebugLine(p0, p1, options);
    batch.drawDebugLine(p1, p2, options);
    batch.drawDebugLine(p2, p0, options);
}

fn resizeCallback(r: *const Renderer) void {
    const aspect = r.swapchain.extentSwapchainRatio();
    // std.log.debug("Resized to: {} - aspect: {}", .{ r.window.size, aspect });

    camera_3d.setProjection(.{ .perspective = .{
        .fov_y = camera_3d_fov_y,
        .aspect = aspect,
        .near = camera_3d_near_clip,
        .far = camera_3d_far_clip,
    } });
}
