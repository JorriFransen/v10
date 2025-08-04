const std = @import("std");
const math = @import("../math.zig");

const log = std.log.scoped(.camera);

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

pub const Camera2D = struct {
    pos: Vec2 = Vec2.scalar(0),
    zoom: f32 = 1,
    ppu: f32 = 1,

    screen_width: f32 = 0,
    screen_height: f32 = 0,
    near_clip: f32 = -10,
    far_clip: f32 = 10,

    origin: Origin = .center,

    projection_dirty: bool = true,
    view_dirty: bool = true,

    projection_matrix: Mat4 = Mat4.identity,
    view_matrix: Mat4 = Mat4.identity,

    pub const Origin = enum {
        center,
        top_left,
        bottom_left,
    };

    pub const Camera2DInitOptions = struct {
        screen_width: u32,
        screen_height: u32,
        zoom: f32 = 1,
        ppu: f32 = 1,
        near_clip: f32,
        far_clip: f32,
        origin: Origin = .center,
    };

    pub fn init(opt: Camera2DInitOptions) Camera2D {
        var result = Camera2D{
            .screen_width = @floatFromInt(opt.screen_width),
            .screen_height = @floatFromInt(opt.screen_height),
            .zoom = opt.zoom,
            .ppu = opt.ppu,
            .near_clip = opt.near_clip,
            .far_clip = opt.far_clip,
            .origin = opt.origin,
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
        const fwidth: f32 = @floatFromInt(screen_width);
        const fheight: f32 = @floatFromInt(screen_height);
        if ((!math.eqlEps(f32, fwidth, this.screen_width)) or
            (!math.eqlEps(f32, fheight, this.screen_height)))
        {
            this.screen_width = fwidth;
            this.screen_height = fheight;
            this.projection_dirty = true;
        }

        if (this.projection_dirty) {
            const aspect = fwidth / fheight;

            const half_ortho_height = fheight / (2 * this.ppu * this.zoom);
            const half_ortho_width = half_ortho_height * aspect;
            const ortho_width = 2 * half_ortho_width;
            const ortho_height = 2 * half_ortho_height;

            this.projection_matrix = switch (this.origin) {
                .center => Mat4.ortho(
                    -half_ortho_width,
                    half_ortho_width,
                    half_ortho_height,
                    -half_ortho_height,
                    this.near_clip,
                    this.far_clip,
                ),
                .top_left => Mat4.ortho(
                    0,
                    ortho_width,
                    0,
                    ortho_height,
                    this.near_clip,
                    this.far_clip,
                ),
                .bottom_left => Mat4.ortho(
                    0,
                    ortho_width,
                    ortho_height,
                    0,
                    this.near_clip,
                    this.far_clip,
                ),
            };

            this.projection_dirty = false;
        }

        if (this.view_dirty) {
            this.view_matrix = Mat4.lookXYZEuler(this.pos.toVector3(this.near_clip), .{});
            this.view_dirty = false;
        }
    }

    pub fn toWorldSpace(this: *const Camera2D, screen_space_point: Vec2) Vec2 {
        const view_offset: Vec2 = switch (this.origin) {
            .center => blk: {
                const scale = this.ppu * this.zoom;
                break :blk .{
                    .x = (screen_space_point.x - (this.screen_width / 2)) / scale,
                    .y = ((this.screen_height / 2) - screen_space_point.y) / scale,
                };
            },

            .top_left => blk: {
                const ortho = this.getViewportWorldSize();
                break :blk .{
                    .x = (screen_space_point.x / this.screen_width) * ortho.x,
                    .y = (screen_space_point.y / this.screen_height) * ortho.y,
                };
            },

            .bottom_left => blk: {
                const ortho = this.getViewportWorldSize();
                break :blk .{
                    .x = (screen_space_point.x / this.screen_width) * ortho.x,
                    .y = (1 - (screen_space_point.y / this.screen_height)) * ortho.y,
                };
            },
        };

        return this.pos.add(view_offset);
    }

    pub fn getViewportWorldSize(this: *const Camera2D) Vec2 {
        const aspect = this.screen_width / this.screen_height;
        const half_ortho_height = this.screen_height / (2 * this.ppu * this.zoom);
        const half_ortho_width = half_ortho_height * aspect;

        return .{ .x = 2 * half_ortho_width, .y = 2 * half_ortho_height };
    }
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
