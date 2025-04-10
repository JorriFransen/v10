const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const vk = @import("vulkan");

const wlog = std.log.scoped(.window);

width: i32,
height: i32,
framebuffer_resized: bool,
name: []const u8,
window: glfw.Window,
platform: glfw.Platform,

pub fn init(this: *@This(), w: i32, h: i32, name: [:0]const u8) !void {
    // glfw.initHint(glfw.PLATFORM, @intFromEnum(glfw.Platform.X11));

    if (glfw.init() != glfw.TRUE) return error.glfwInitFailed;

    glfw.windowHint(glfw.CLIENT_API, glfw.NO_API);
    glfw.windowHint(glfw.RESIZABLE, glfw.TRUE);

    glfw.windowHintString(glfw.WAYLAND_APP_ID, name);

    const handle = glfw.createWindow(w, h, name, null, null);

    glfw.setWindowUserPointer(handle, this);
    _ = glfw.setFramebufferSizeCallback(handle, framebufferResizeCallback);

    const platform = glfw.getPlatform();

    this.* = .{
        .width = w,
        .height = h,
        .framebuffer_resized = false,
        .name = name,
        .window = handle,
        .platform = platform,
    };
}

pub fn destroy(this: *@This()) void {
    glfw.destroyWindow(this.window);
    glfw.terminate();
}

pub fn shouldClose(this: *const @This()) bool {
    return glfw.windowShouldClose(this.window) == glfw.TRUE;
}

pub fn waitEvents(this: *const @This()) void {
    _ = this;
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
    wlog.debug("framebufferResizeCallback(\"{s}\", {}, {})", .{ window.name, width, height });
}
