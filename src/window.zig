const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const vk = @import("vulkan");

const Window = @This();

// TODO: This should be handled by glfw in the furture?
const c = if (builtin.os.tag == .windows)
    struct {}
else
    @cImport({
        @cInclude("fontconfig/fontconfig.h");
    });

const wlog = std.log.scoped(.window);

pub const PfnRefreshCallback = ?*const fn (this: *Window) void;
pub const PfnResizeCallback = ?*const fn (this: *Window, width: i32, height: i32) void;

width: i32 = undefined,
height: i32 = undefined,
framebuffer_resized: bool = false,
name: []const u8 = "",
handle: *glfw.Window = undefined,
refresh_callback: PfnRefreshCallback = null,
resize_callback: PfnResizeCallback = null,

pub const InitOptions = struct {
    platform: glfw.Platform = .any,
    refresh_callback: PfnRefreshCallback = null,
    resize_callback: PfnResizeCallback = null,
};

pub fn init(this: *Window, w: i32, h: i32, name: [:0]const u8, options: InitOptions) !void {
    glfw.initHint(.platform, options.platform.initHint());

    if (glfw.init() != glfw.TRUE) return error.glfwInitFailed;

    glfw.windowHint(.client_api, glfw.WindowHintValue.no_api);
    glfw.windowHint(.resizable, .true);

    glfw.windowHintString(.wayland_app_id, name);

    if (builtin.os.tag != .windows) _ = c.FcInit();
    const handle = glfw.createWindow(w, h, name, null, null);

    glfw.setWindowUserPointer(handle, this);
    _ = glfw.setFramebufferSizeCallback(handle, framebufferResizeCallback);
    _ = glfw.setKeyCallback(handle, keyCallback);

    if (glfw.getPlatform() != .wayland) {
        // The drawFrame() call in refreshCallback() makes window resizing laggy.
        // This is meant to redraw during resize, to make resizing smoother, but wayland
        //  doesn't have this problem to start with.
        _ = glfw.setWindowRefreshCallback(handle, refreshCallback);
    }

    _ = glfw.setWindowSizeCallback(handle, resizeCallback);

    this.* = .{
        .width = w,
        .height = h,
        .framebuffer_resized = false,
        .name = name,
        .handle = handle,
        .refresh_callback = options.refresh_callback,
        .resize_callback = options.resize_callback,
    };
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

pub fn createWindowSurface(this: *const Window, instance: vk.Instance, surface: *vk.SurfaceKHR) !void {
    const instance_int = @intFromEnum(instance);
    const result_ = glfw.createWindowSurface(@enumFromInt(instance_int), this.handle, null, @ptrCast(surface));
    const result: vk.Result = @enumFromInt(@intFromEnum(result_));
    if (result != .success) {
        return error.glfwCreateWindowSurfaceFailed;
    }
}

pub fn getExtent(this: *const Window) vk.Extent2D {
    return .{ .width = @intCast(this.width), .height = @intCast(this.height) };
}

pub fn framebufferResizeCallback(glfw_window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    const window: *Window = @ptrCast(@alignCast(glfw.getWindowUserPointer(glfw_window)));
    window.framebuffer_resized = true;
    window.width = width;
    window.height = height;
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

fn refreshCallback(glfw_window: *glfw.Window) callconv(.c) void {
    const window: *Window = @ptrCast(@alignCast(glfw.getWindowUserPointer(glfw_window)));
    if (window.refresh_callback) |cb| cb(window);
}

fn resizeCallback(glfw_window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    const window: *Window = @ptrCast(@alignCast(glfw.getWindowUserPointer(glfw_window)));
    if (window.resize_callback) |cb| cb(window, width, height);
}
