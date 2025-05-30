const math = @import("../math.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

projection_matrix: Mat4 = Mat4.identity,
view_matrix: Mat4 = Mat4.identity,

pub const ProjectionInfo = union(enum) {
    orthographic: struct { l: f32, r: f32, t: f32, b: f32 },
    perspective: struct {
        fov_y: f32,
        aspect: f32,
    },
};

pub inline fn setProjection(this: *@This(), info: ProjectionInfo, near: f32, far: f32) void {
    this.projection_matrix = switch (info) {
        .orthographic => |o| Mat4.ortho(o.l, o.r, o.t, o.b, near, far),
        .perspective => |p| Mat4.perspective(p.fov_y, p.aspect, near, far),
    };
}

pub inline fn setViewDirection(this: *@This(), pos: Vec3, direction: Vec3, up: Mat4.UpDirection) void {
    this.view_matrix = Mat4.lookInDirection(pos, direction, up);
}

pub inline fn setViewTarget(this: *@This(), pos: Vec3, target: Vec3, up: Mat4.UpDirection) void {
    this.view_matrix = Mat4.lookAtPosition(pos, target, up);
}

pub inline fn setViewYXZ(this: *@This(), pos: Vec3, euler_angles: Vec3) void {
    this.view_matrix = Mat4.lookXYZEuler(pos, euler_angles);
}
