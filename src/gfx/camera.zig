const math = @import("../math.zig");

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

pub const Camera2D = struct {
    pos: Vec2 = Vec2.scalar(0),
    zoom: f32 = 1,
    ppu: f32 = 1,

    ortho_width: f32 = 0,
    ortho_height: f32 = 0,
    near_clip: f32 = -10,
    far_clip: f32 = 10,

    projection_dirty: bool = true,
    view_dirty: bool = true,

    projection_matrix: Mat4 = Mat4.identity,
    view_matrix: Mat4 = Mat4.identity,

    pub const Camera2DInitOptions = struct {
        screen_width: u32,
        screen_height: u32,
        zoom: f32 = 1,
        ppu: f32 = 1,
        near_clip: f32,
        far_clip: f32,
    };

    pub fn init(opt: Camera2DInitOptions) Camera2D {
        var result = Camera2D{
            .zoom = opt.zoom,
            .ppu = opt.ppu,
            .near_clip = opt.near_clip,
            .far_clip = opt.far_clip,
        };

        result.update(opt.screen_width, opt.screen_height);

        return result;
    }

    pub inline fn setPosition(this: *Camera2D, pos: Vec2) void {
        if (!this.pos.eql(pos)) {
            this.view_dirty = true;
            this.pos = pos;
        }
    }

    pub inline fn setZoom(this: *Camera2D, zoom: f32) void {
        if (this.zoom != zoom) {
            this.projection_dirty = true;
            this.zoom = zoom;
        }
    }

    pub fn update(this: *Camera2D, screen_width: u32, screen_height: u32) void {
        if (this.projection_dirty) {
            const fwidth: f32 = @floatFromInt(screen_width);
            const fheight: f32 = @floatFromInt(screen_height);
            const aspect = fwidth / fheight;

            const half_ortho_height = fheight / (2 * this.ppu * this.zoom);
            const half_ortho_width = half_ortho_height * aspect;

            this.projection_matrix = Mat4.ortho(
                -half_ortho_width,
                half_ortho_width,
                half_ortho_height,
                -half_ortho_height,
                this.near_clip,
                this.far_clip,
            );
            this.ortho_width = 2 * half_ortho_width;
            this.ortho_height = 2 * half_ortho_height;
            this.projection_dirty = false;
        }

        if (this.view_dirty) {
            this.view_matrix = Mat4.lookXYZEuler(this.pos.toVector3(this.near_clip), .{});
            this.view_dirty = false;
        }
    }

    //
    // pub inline fn setProjection(this: *Camera2D, opt: OrthoGraphicProjectionOptions) void {
    //     this.ortho_width = @abs(opt.r - opt.l);
    //     this.ortho_height = @abs(opt.t - opt.b);
    //     this.projection_matrix = Mat4.ortho(opt.l, opt.r, opt.t, opt.b, opt.n, opt.f);
    // }

};

pub const OrthoGraphicProjectionOptions = struct {
    l: f32,
    r: f32,
    t: f32,
    b: f32,
    n: f32,
    f: f32,
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
