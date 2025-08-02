const std = @import("std");
const glfw = @import("glfw");
const math = @import("math.zig");

const Controller = @This();
const Window = @import("window.zig");
const Transform = @import("transform.zig");
const Key = glfw.Key;
const Vec2 = math.Vec2;

const KeyMappings = struct {
    move_left: Key = .a,
    move_right: Key = .d,
    move_up: Key = .w,
    move_down: Key = .s,
    zoom_in: Key = .e,
    zoom_out: Key = .q,
};

keys: KeyMappings = .{},
move_speed: f32 = 20,
zoom_step_per_second: f32 = 3,

pub fn updateInput(this: *const Controller, window_: *Window, dt: f32, pos: *Vec2, zoom: *f32) void {
    const window = window_.handle;

    var dir = Vec2{};
    var zoom_dir: f32 = 0;

    if (glfw.getKey(window, this.keys.move_left) == .press) dir = dir.add(.{ .x = -1 });
    if (glfw.getKey(window, this.keys.move_right) == .press) dir = dir.add(.{ .x = 1 });
    if (glfw.getKey(window, this.keys.move_up) == .press) dir = dir.add(.{ .y = 1 });
    if (glfw.getKey(window, this.keys.move_down) == .press) dir = dir.add(.{ .y = -1 });
    if (glfw.getKey(window, this.keys.zoom_in) == .press) zoom_dir = 1;
    if (glfw.getKey(window, this.keys.zoom_out) == .press) zoom_dir = -1;

    if (dir.x != 0 and dir.y != 0) {
        dir = dir.normalized();
    }

    zoom.* *= std.math.pow(f32, this.zoom_step_per_second, dt * zoom_dir);

    // Proportional to zoom level
    pos.* = pos.add(dir.mul_scalar(dt * this.move_speed / zoom.*));
}
