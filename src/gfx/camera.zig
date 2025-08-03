const math = @import("../math.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

pub const OrthoGraphicProjectionOptions = struct {
    l: f32,
    r: f32,
    t: f32,
    b: f32,
    n: f32,
    f: f32,
};

pub const Camera2D = struct {
    projection_matrix: Mat4 = Mat4.identity,
    view_matrix: Mat4 = Mat4.identity,

    ortho_width: f32,
    ortho_height: f32,

    pub inline fn setProjection(this: *@This(), opt: OrthoGraphicProjectionOptions) void {
        this.ortho_width = @abs(opt.r - opt.l);
        this.ortho_height = @abs(opt.t - opt.b);
        this.projection_matrix = Mat4.ortho(opt.l, opt.r, opt.t, opt.b, opt.n, opt.f);
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
};

pub const Camera3D = struct {
    projection_matrix: Mat4 = Mat4.identity,
    view_matrix: Mat4 = Mat4.identity,

    pub const SetProjectionOptions = union(enum) {
        orthographic: OrthoGraphicProjectionOptions,
        perspective: struct {
            fov_y: f32,
            aspect: f32,
            near: f32,
            far: f32,
        },
    };

    pub inline fn setProjection(this: *@This(), info: SetProjectionOptions) void {
        this.projection_matrix = switch (info) {
            .orthographic => |o| blk: {
                break :blk Mat4.ortho(o.l, o.r, o.t, o.b, o.n, o.f);
            },
            .perspective => |p| blk: {
                break :blk Mat4.perspective(p.fov_y, p.aspect, p.near, p.far);
            },
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
};
