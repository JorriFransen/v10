const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const vk = @import("vulkan");

// TODO: This should be handled by glfw in the furture?
const c = if (builtin.os.tag == .windows)
    struct {}
else
    @cImport({
        @cInclude("fontconfig/fontconfig.h");
    });

const wlog = std.log.scoped(.window);

pub const PfnRefreshCallback = ?*const fn (this: *@This()) void;
pub const PfnResizeCallback = ?*const fn (this: *@This(), width: i32, height: i32) void;

width: i32 = undefined,
height: i32 = undefined,
framebuffer_resized: bool = false,
name: []const u8 = "",
window: glfw.Window = null,
refresh_callback: PfnRefreshCallback = null,
resize_callback: PfnResizeCallback = null,

pub const InitOptions = struct {
    platform: glfw.Platform = .ANY,
    refresh_callback: PfnRefreshCallback = null,
    resize_callback: PfnResizeCallback = null,
};

pub fn init(this: *@This(), w: i32, h: i32, name: [:0]const u8, options: InitOptions) !void {
    glfw.initHint(glfw.PLATFORM, @intFromEnum(options.platform));

    if (glfw.init() != glfw.TRUE) return error.glfwInitFailed;

    glfw.windowHint(glfw.CLIENT_API, glfw.NO_API);
    glfw.windowHint(glfw.RESIZABLE, glfw.TRUE);

    glfw.windowHintString(glfw.WAYLAND_APP_ID, name);

    if (builtin.os.tag != .windows) _ = c.FcInit();
    const handle = glfw.createWindow(w, h, name, null, null);

    glfw.setWindowUserPointer(handle, this);
    _ = glfw.setFramebufferSizeCallback(handle, framebufferResizeCallback);
    _ = glfw.setKeyCallback(handle, keyCallback);

    if (glfw.getPlatform() != .WAYLAND) {
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
        .window = handle,
        .refresh_callback = options.refresh_callback,
        .resize_callback = options.resize_callback,
    };
}

pub fn destroy(this: *@This()) void {
    glfw.destroyWindow(this.window);
    if (builtin.os.tag != .windows) c.FcFini();
    glfw.terminate();
}

pub fn shouldClose(this: *const @This()) bool {
    return glfw.windowShouldClose(this.window) == glfw.TRUE;
}

pub fn pollEvents(_: *const @This()) void {
    glfw.pollEvents();
}

pub fn waitEvents(_: *const @This()) void {
    glfw.waitEvents();
}

pub fn createWindowSurface(this: *const @This(), instance: vk.Instance, surface: *vk.SurfaceKHR) !void {
    const instance_int: usize = @intFromEnum(instance);

    const result_ = glfw.createWindowSurface(@ptrFromInt(instance_int), this.window.?, null, @ptrCast(surface));
    const result: vk.Result = @enumFromInt(@intFromEnum(result_));
    if (result != .success) {
        return error.glfwCreateWindowSurfaceFailed;
    }
}

pub fn getExtent(this: *const @This()) vk.Extent2D {
    return .{ .width = @intCast(this.width), .height = @intCast(this.height) };
}

pub fn framebufferResizeCallback(glfw_window: glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    const window: *@This() = @ptrCast(@alignCast(glfw.getWindowUserPointer(glfw_window)));
    window.framebuffer_resized = true;
    window.width = width;
    window.height = height;
}

fn keyCallback(glfw_window: glfw.Window, key: c_int, scancode: c_int, action: glfw.Action, mods: c_int) callconv(.c) void {
    _ = scancode;
    _ = mods;

    const window: *@This() = @ptrCast(@alignCast(glfw.getWindowUserPointer(glfw_window)));
    _ = window;

    if (key == glfw.c.GLFW_KEY_ESCAPE and action == .press) {
        glfw.setWindowShouldClose(glfw_window, glfw.TRUE);
    }
}

fn refreshCallback(glfw_window: glfw.Window) callconv(.c) void {
    const window: *@This() = @ptrCast(@alignCast(glfw.getWindowUserPointer(glfw_window)));
    if (window.refresh_callback) |cb| cb(window);
}

fn resizeCallback(glfw_window: glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    const window: *@This() = @ptrCast(@alignCast(glfw.getWindowUserPointer(glfw_window)));
    if (window.resize_callback) |cb| cb(window, width, height);
}
