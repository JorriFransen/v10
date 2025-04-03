const builtin = @import("builtin");
const glfw = @import("glfw");
const vk = @import("vulkan");

width: i32,
height: i32,
name: []const u8,
window: glfw.Window,

pub fn create(w: i32, h: i32, name: [:0]const u8) !@This() {
    if (glfw.init() != glfw.TRUE) return error.glfwInitFailed;

    glfw.windowHint(glfw.CLIENT_API, glfw.NO_API);
    glfw.windowHint(glfw.RESIZABLE, glfw.FALSE);

    glfw.windowHintString(glfw.WAYLAND_APP_ID, name);

    const handle = glfw.createWindow(w, h, name, null, null);

    return .{
        .width = w,
        .height = h,
        .name = name,
        .window = handle,
    };
}

pub fn destroy(this: *@This()) void {
    glfw.destroyWindow(this.window);
    glfw.terminate();
}

pub fn shouldClose(this: *const @This()) bool {
    return glfw.windowShouldClose(this.window) == glfw.TRUE;
}

pub fn createWindowSurface(this: *const @This(), instance: vk.Instance, surface: *vk.SurfaceKHR) !void {
    if (glfw.createWindowSurface(instance, this.window.?, null, surface) != .success) {
        return error.glfwCreateWindowSurfaceFailed;
    }
}

pub fn getExtent(this: *const @This()) vk.Extent2D {
    return .{ .width = @intCast(this.width), .height = @intCast(this.height) };
}
