const std = @import("std");
const Window = @import("window.zig");

const glfw = @import("glfw");

pub fn main() !void {
    var window = try Window.create(800, 600, "v10");

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }

    window.destroy();
}
