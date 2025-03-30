const std = @import("std");
const vklog = std.log.scoped(.vulkan);
const v10log = std.log.scoped(.v10);

const glfw = @import("glfw");

const vk = @import("vulkan");
var vkb: vk.BaseWrapper = undefined;

const lm = @import("lm.zig");
const Mat4 = lm.Mat4f32;
const Vec4 = lm.Vec4f32;

pub fn main() !void {
    if (glfw.init() != glfw.TRUE) {
        return error.glfwInitFailed;
    }

    glfw.windowHint(glfw.CLIENT_API, glfw.NO_API);

    const window = glfw.createWindow(800, 600, "Vulkan window", null, null) orelse return error.glfwCreateWindowFailed;

    vkb = vk.BaseWrapper.load(glfw.getInstanceProcAddress);

    var instance_extension_count: u32 = undefined;
    if (try vkb.enumerateInstanceExtensionProperties(null, &instance_extension_count, null) != vk.Result.success) {
        return error.vkbEnumerateInstanceExtensionPropertiesFailed;
    }
    vklog.debug("instance extension count: {}", .{instance_extension_count});

    const matrix = Mat4.identity;
    const vec = Vec4.scalar(1);
    v10log.debug("matrix: {}", .{matrix});
    v10log.debug("vec: {}", .{vec});

    while (glfw.windowShouldClose(window) != glfw.TRUE) {
        glfw.pollEvents();
    }

    glfw.destroyWindow(window);
    glfw.terminate();
}
