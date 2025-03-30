const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "v10game",
        .root_source_file = b.path("src/main.zig"),
        .target = b.graph.host,
    });

    b.installArtifact(exe);

    const glfw_dep = b.dependency("glfw", .{ .target = b.graph.host, .x11 = true, .wayland = true });
    const glfw_lib = glfw_dep.artifact("glfw");
    const glfw_mod = glfw_dep.module("glfw");
    exe.root_module.addImport("glfw", glfw_mod);
    exe.linkLibrary(glfw_lib);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
