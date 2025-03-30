const std = @import("std");

const glfw = @import("glfw");

pub fn main() !void {
    if (glfw.init() != glfw.TRUE) {
        return error.glfwInitFailed;
    }

    const window = glfw.createWindow(800, 600, "Vulkan window", null, null) orelse return error.glfwCreateWindowFailed;
    while (glfw.windowShouldClose(window) != glfw.TRUE) {
        glfw.pollEvents();
    }

    glfw.destroyWindow(window);
    glfw.terminate();
}
