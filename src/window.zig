const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const vk = @import("vulkan");
const math = @import("math.zig");

const Window = @This();
const Vec2 = math.Vec2;
const Vec2f64 = math.Vec(2, f64);
const Vec2u32 = math.Vec(2, u32);
const Vec2u64 = math.Vec(2, u64);

const log = std.log.scoped(.window);

// TODO: This should be handled by glfw in the furture?
const c = if (builtin.os.tag == .windows)
    struct {}
else
    @cImport({
        @cInclude("fontconfig/fontconfig.h");
    });

const wlog = std.log.scoped(.window);

pub const PfnResizeCallback = ?*const fn (this: *Window, width: i32, height: i32) void;
pub const PfnFramebufferResizeCallback = ?*const fn (this: *Window) void;
pub const PfnCursorPosCallback = ?*const fn (this: *Window, x: f64, y: f64) void;

/// Framebuffer size in pixels
size: Vec2u32,

/// Dpi aware window size
window_size: Vec2u32,

framebuffer_resized: bool = false,
name: []const u8 = "",
handle: *glfw.Window = undefined,
resize_callback: PfnResizeCallback = null,
framebuffer_resize_callback: PfnFramebufferResizeCallback = null,
cursor_pos_callback: PfnCursorPosCallback = null,

pub const InitOptions = struct {
    platform: glfw.Platform = .any,
    resize_callback: PfnResizeCallback = null,
    framebuffer_resize_callback: PfnFramebufferResizeCallback = null,
    cursor_pos_callback: PfnCursorPosCallback = null,
};

pub fn init(this: *Window, logical_width: i32, logical_height: i32, name: [:0]const u8, options: InitOptions) !void {
    glfw.initHint(.platform, options.platform.initHint());

    if (glfw.init() != glfw.TRUE) return error.glfwInitFailed;

    glfw.windowHint(.client_api, glfw.WindowHintValue.no_api);
    glfw.windowHint(.resizable, .true);

    glfw.windowHintString(.wayland_app_id, name);

    if (builtin.os.tag != .windows) _ = c.FcInit();

    const handle = glfw.createWindow(logical_width, logical_height, name, null, null) orelse {
        var msg: [*:0]const u8 = undefined;
        const err = glfw.getError(&msg);
        log.err("glfwCreateWindow failed with error: {s}", .{msg});
        return err;
    };

    var fb_width: c_int = undefined;
    var fb_height: c_int = undefined;
    glfw.getFramebufferSize(handle, &fb_width, &fb_height);

    var w_width: c_int = undefined;
    var w_height: c_int = undefined;
    glfw.getWindowSize(handle, &w_width, &w_height);

    this.* = .{
        .size = Vec2u32.new(@intCast(fb_width), @intCast(fb_height)),
        .window_size = Vec2u32.new(@intCast(w_width), @intCast(w_height)),
        .framebuffer_resized = false,
        .name = name,
        .handle = handle,
        .resize_callback = options.resize_callback,
        .framebuffer_resize_callback = options.framebuffer_resize_callback,
        .cursor_pos_callback = options.cursor_pos_callback,
    };

    glfw.setWindowUserPointer(handle, this);

    _ = glfw.setWindowSizeCallback(handle, resizeCallback);
    _ = glfw.setFramebufferSizeCallback(handle, framebufferResizeCallback);
    _ = glfw.setKeyCallback(handle, keyCallback);
    _ = glfw.setCursorPosCallback(handle, cursorPosCallback);
}

pub fn destroy(this: *Window) void {
    glfw.destroyWindow(this.handle);
    if (builtin.os.tag != .windows) c.FcFini();
    glfw.terminate();
}

pub fn shouldClose(this: *const Window) bool {
    return glfw.windowShouldClose(this.handle) == glfw.TRUE;
}

pub fn pollEvents(_: *const Window) void {
    glfw.pollEvents();
}

pub fn waitEvents(_: *const Window) void {
    glfw.waitEvents();
}

pub fn waitEventsTimeout(_: *const Window, timeout: f64) void {
    glfw.waitEventsTimeout(timeout);
}

pub fn createWindowSurface(this: *const Window, instance: vk.Instance, surface: *vk.SurfaceKHR) !void {
    const instance_int = @intFromEnum(instance);
    const result_ = glfw.createWindowSurface(@enumFromInt(instance_int), this.handle, null, @ptrCast(surface));
    const result: vk.Result = @enumFromInt(@intFromEnum(result_));
    if (result != .success) {
        return error.glfwCreateWindowSurfaceFailed;
    }
}

pub fn windowToFrameBufferPoint(this: *const Window, comptime V: type, p: V) V {
    const IType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = @typeInfo(V.T).float.bits } });

    const i_size = math.intToIntVec(Vec2u32, Vec2u64, this.size);
    const f_size = math.intToFloatVec(math.Vec(V.N, IType), V, i_size);
    const f_window_size = math.intToFloatVec(Vec2u32, V, this.window_size);

    return p.mul(f_size.div(f_window_size));
}

/// Cursor position in framebuffer pixel space
pub fn getCursorPos(this: *const Window) Vec2 {
    var x: f64 = undefined;
    var y: f64 = undefined;
    glfw.getCursorPos(this.handle, &x, &y);

    return math.floatToFloatVec(Vec2f64, Vec2, this.windowToFrameBufferPoint(Vec2f64, .{ .x = x, .y = y }));
}

fn keyCallback(glfw_window: *glfw.Window, key: glfw.Key, scancode: c_int, action: glfw.Action, mods: glfw.Mod) callconv(.c) void {
    _ = scancode;
    _ = mods;

    const window: *Window = @ptrCast(@alignCast(glfw.getWindowUserPointer(glfw_window)));
    _ = window;

    if (key == .escape and action == .press) {
        glfw.setWindowShouldClose(glfw_window, glfw.TRUE);
    }
}

pub fn framebufferResizeCallback(glfw_window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    const window: *Window = @ptrCast(@alignCast(glfw.getWindowUserPointer(glfw_window)));

    window.framebuffer_resized = true;
    window.size = Vec2u32.new(@intCast(width), @intCast(height));

    if (window.framebuffer_resize_callback) |cb| cb(window);
}

fn resizeCallback(glfw_window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    const window: *Window = @ptrCast(@alignCast(glfw.getWindowUserPointer(glfw_window)));

    window.window_size = Vec2u32.new(@intCast(width), @intCast(height));

    if (window.resize_callback) |cb| cb(window, width, height);
}

fn cursorPosCallback(glfw_window: *glfw.Window, x: f64, y: f64) callconv(.c) void {
    const window: *Window = @ptrCast(@alignCast(glfw.getWindowUserPointer(glfw_window)));

    const p = window.windowToFrameBufferPoint(Vec2f64, .{ .x = x, .y = y });

    if (window.cursor_pos_callback) |cb| cb(window, p.x, p.y);
}
