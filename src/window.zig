const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const vk = @import("vulkan");

const wlog = std.log.scoped(.window);

pub const PfnRefreshCallback = ?*const fn (this: *@This()) void;

width: i32,
height: i32,
framebuffer_resized: bool,
name: []const u8,
window: glfw.Window,
refresh_callback: PfnRefreshCallback,

pub fn init(this: *@This(), w: i32, h: i32, name: [:0]const u8) !void {
    // glfw.initHint(glfw.PLATFORM, @intFromEnum(glfw.Platform.X11));

    if (glfw.init() != glfw.TRUE) return error.glfwInitFailed;

    glfw.windowHint(glfw.CLIENT_API, glfw.NO_API);
    glfw.windowHint(glfw.RESIZABLE, glfw.TRUE);

    glfw.windowHintString(glfw.WAYLAND_APP_ID, name);

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

    this.* = .{
        .width = w,
        .height = h,
        .framebuffer_resized = false,
        .name = name,
        .window = handle,
        .refresh_callback = null,
    };
}

pub fn destroy(this: *@This()) void {
    glfw.destroyWindow(this.window);
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
    if (glfw.createWindowSurface(instance, this.window.?, null, surface) != .success) {
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

fn keyCallback(glfw_window: glfw.Window, key: c_int, scancode: c_int, action: glfw.Action, mods: c_int) callconv(.C) void {
    _ = scancode;
    _ = mods;

    if (key == glfw.c.GLFW_KEY_ESCAPE and action == .press) {
        glfw.setWindowShouldClose(glfw_window, glfw.TRUE);
    }
}

fn refreshCallback(glfw_window: glfw.Window) callconv(.c) void {
    const window: *@This() = @ptrCast(@alignCast(glfw.getWindowUserPointer(glfw_window)));
    if (window.refresh_callback) |cb| cb(window);
}
