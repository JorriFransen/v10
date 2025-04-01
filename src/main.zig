const std = @import("std");
const Window = @import("window.zig");

const glfw = @import("glfw");

const gfx = @import("gfx/gfx.zig");

pub fn main() !void {
    const width = 800;
    const height = 600;

    var window = try Window.create(width, height, "v10");
    defer window.destroy();

    try gfx.System.init();

    var device = try gfx.Device.create(&gfx.system, &window);
    defer device.destroy();

    const pipeline = try gfx.Pipeline.create(
        &device,
        "shaders/simple.vert.spv",
        "shaders/simple.frag.spv",
        gfx.Pipeline.ConfigInfo.default(width, height),
    );
    defer pipeline.destroy();

    while (!window.shouldClose()) {
        glfw.pollEvents();
        glfw.swapBuffers(window.window.?);
    }
}
