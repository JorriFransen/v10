const std = @import("std");
const glfw = @import("glfw");
const math = @import("math.zig");

const Window = @import("window.zig");
const Transform = @import("transform.zig");
const Key = glfw.Key;
const Vec3 = math.Vec3;

pub const KeyMappings = struct {
    move_left: Key = .a,
    move_right: Key = .d,
    move_forward: Key = .w,
    move_back: Key = .s,
    move_up: Key = .e,
    move_down: Key = .q,
    look_left: Key = .left,
    look_right: Key = .right,
    look_up: Key = .up,
    look_down: Key = .down,
};

keys: KeyMappings = .{},
move_speed: f32 = 3,
look_speed: f32 = 1.5,

pub fn moveInPlaneXZ(this: *const @This(), window_: *Window, dt: f32, transform: *Transform) void {
    const window = window_.handle;

    const epsilon = std.math.floatEps(@TypeOf(transform.rotation).T);

    var rot = Vec3{};
    if (glfw.getKey(window, this.keys.look_right) == .press) rot.y += 1;
    if (glfw.getKey(window, this.keys.look_left) == .press) rot.y -= 1;
    if (glfw.getKey(window, this.keys.look_up) == .press) rot.x -= 1;
    if (glfw.getKey(window, this.keys.look_down) == .press) rot.x += 1;

    if (rot.dot(rot) > epsilon) {
        const trot = &transform.rotation;
        trot.* = trot.add(rot.normalized().mul_scalar(dt * this.look_speed));

        // Limit pitch to about +/- 85 degrees
        trot.x = std.math.clamp(trot.x, -1.5, 1.5);
        trot.y = @mod(trot.y, std.math.tau); // Avoid overflow
    }

    const yaw = transform.rotation.y;
    const cy = @cos(yaw);
    const sy = @sin(yaw);
    const forward = Vec3.new(sy, 0, cy);
    const right = Vec3.new(cy, 0, -sy);
    const up = Vec3.new(0, 1, 0);

    var mdir = Vec3{};
    if (glfw.getKey(window, this.keys.move_left) == .press) mdir = mdir.add(right.negate());
    if (glfw.getKey(window, this.keys.move_right) == .press) mdir = mdir.add(right);
    if (glfw.getKey(window, this.keys.move_forward) == .press) mdir = mdir.add(forward);
    if (glfw.getKey(window, this.keys.move_back) == .press) mdir = mdir.add(forward.negate());
    if (glfw.getKey(window, this.keys.move_up) == .press) mdir = mdir.add(up);
    if (glfw.getKey(window, this.keys.move_down) == .press) mdir = mdir.add(up.negate());

    if (mdir.dot(mdir) > epsilon) {
        const ttra = &transform.translation;
        ttra.* = ttra.add(mdir.normalized().mul_scalar(dt * this.move_speed));
        // std.log.debug("Cam pos: {}", .{ttra.*});
    }
}
