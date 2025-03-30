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

    const vulkan_mod = b.dependency("vulkan_zig", .{
        .target = b.graph.host,
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");
    exe.root_module.addImport("vulkan", vulkan_mod);

    const shaders = [_][]const u8{
        "shaders/simple.vert",
        "shaders/simple.frag",
    };

    const shaders_step = b.step("shaders", "Compile shaders");
    exe.step.dependOn(shaders_step);
    for (shaders) |path| {
        const compile_step = b.addSystemCommand(&.{"glslc"});
        compile_step.addFileArg(b.path(path));
        compile_step.addArgs(&.{ "-o", b.fmt("{s}.spv", .{path}) });
        shaders_step.dependOn(&compile_step.step);
    }

    // const glslc_step = b.addSystemCommand(&.{"glslc"});
    // glslc_step.addFileArg(b.path("shaders/simple.vert"));
    // glslc_step.addArgs(&.{ "-o", "shaders/simple.vert.spv" });
    // exe.step.dependOn(&glslc_step.step);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
