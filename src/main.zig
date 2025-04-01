const std = @import("std");
const Window = @import("window.zig");

const glfw = @import("glfw");

const gfx = @import("gfx/gfx.zig");

pub fn main() !void {
    var window = try Window.create(800, 600, "v10");
    defer window.destroy();

    try gfx.System.init();

    var device = try gfx.Device.create(&gfx.system, &window);
    defer device.destroy();

    const pipeline = try gfx.Pipeline.create(.{ .device = &device });
    defer pipeline.destroy();

    while (!window.shouldClose()) {
        glfw.pollEvents();
        glfw.swapBuffers(window.window.?);
    }
}
