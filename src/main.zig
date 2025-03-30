const std = @import("std");
const vklog = std.log.scoped(.vulkan);

const glfw = @import("glfw");

const vk = @import("vulkan");
var vkb: vk.BaseWrapper = undefined;

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

    while (glfw.windowShouldClose(window) != glfw.TRUE) {
        glfw.pollEvents();
    }

    glfw.destroyWindow(window);
    glfw.terminate();
}
