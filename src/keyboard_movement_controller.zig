const std = @import("std");
const glfw = @import("glfw");
const math = @import("math");

const Window = @import("window.zig");
const Entity = @import("entity.zig");
const Key = c_int;
const Vec3 = math.Vec3;

pub const KeyMappings = struct {
    move_left: Key = glfw.c.GLFW_KEY_A,
    move_right: Key = glfw.c.GLFW_KEY_D,
    move_forward: Key = glfw.c.GLFW_KEY_W,
    move_back: Key = glfw.c.GLFW_KEY_S,
    move_up: Key = glfw.c.GLFW_KEY_E,
    move_down: Key = glfw.c.GLFW_KEY_Q,
    look_left: Key = glfw.c.GLFW_KEY_LEFT,
    look_right: Key = glfw.c.GLFW_KEY_RIGHT,
    look_up: Key = glfw.c.GLFW_KEY_UP,
    look_down: Key = glfw.c.GLFW_KEY_DOWN,
};

keys: KeyMappings = .{},
move_speed: f32 = 3,
look_speed: f32 = 1.5,

pub fn moveInPlaneXZ(this: *const @This(), window_: *Window, dt: f32, entity: *Entity) void {
    const window = window_.window;

    const epsilon = std.math.floatEps(@TypeOf(entity.transform.rotation).T);

    var rot = Vec3{};
    if (glfw.getKey(window, this.keys.look_right) == glfw.c.GLFW_PRESS) rot.y += 1;
    if (glfw.getKey(window, this.keys.look_left) == glfw.c.GLFW_PRESS) rot.y -= 1;
    if (glfw.getKey(window, this.keys.look_up) == glfw.c.GLFW_PRESS) rot.x += 1;
    if (glfw.getKey(window, this.keys.look_down) == glfw.c.GLFW_PRESS) rot.x -= 1;

    if (rot.dot(rot) > epsilon) {
        const trot = &entity.transform.rotation;
        trot.* = trot.add(rot.normalized().mul_scalar(dt * this.look_speed));

        // Limit pitch to about +/- 85 degrees
        trot.x = std.math.clamp(trot.x, -1.5, 1.5);
        trot.y = @mod(trot.y, std.math.tau); // Avoid overflow
    }

    const pitch = entity.transform.rotation.x;
    const yaw = entity.transform.rotation.y;

    const cp = @cos(pitch);
    const cy = @cos(yaw);
    const sp = @sin(pitch);
    const sy = @sin(yaw);

    const forward = Vec3.new(cp * sy, -sp, cp * cy);
    const right = Vec3.new(cy, 0, -sy);

    // relative up
    // const up = Vec3.new(-sp * sy, -cp, sp * -cy); // -y is up

    // world up
    const up = Vec3.new(0, -1, 0);

    var mdir = Vec3{};
    if (glfw.getKey(window, this.keys.move_left) == glfw.c.GLFW_PRESS) mdir = mdir.add(right.negate());
    if (glfw.getKey(window, this.keys.move_right) == glfw.c.GLFW_PRESS) mdir = mdir.add(right);
    if (glfw.getKey(window, this.keys.move_forward) == glfw.c.GLFW_PRESS) mdir = mdir.add(forward);
    if (glfw.getKey(window, this.keys.move_back) == glfw.c.GLFW_PRESS) mdir = mdir.add(forward.negate());
    if (glfw.getKey(window, this.keys.move_up) == glfw.c.GLFW_PRESS) mdir = mdir.add(up);
    if (glfw.getKey(window, this.keys.move_down) == glfw.c.GLFW_PRESS) mdir = mdir.add(up.negate());

    if (mdir.dot(mdir) > epsilon) {
        const ttra = &entity.transform.translation;
        ttra.* = ttra.add(mdir.normalized().mul_scalar(dt * this.move_speed));
    }
}
