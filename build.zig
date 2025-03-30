const std = @import("std");
const dlog = std.log.debug;

const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const exe = b.addExecutable(.{
        .name = "v10game",
        .root_source_file = b.path("src/main.zig"),
        .target = b.graph.host,
    });

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
    run_step.dependOn(b.getInstallStep());

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

    const shader_step = try addShaderStep(b);
    exe.step.dependOn(shader_step);

    const clean_step = b.step("clean", "Clean shaders and zig-out directory");
    clean_step.dependOn(&b.addRemoveDirTree(std.Build.LazyPath{ .cwd_relative = b.install_path }).step);
    if (builtin.os.tag != .windows) {
        clean_step.dependOn(&b.addRemoveDirTree(std.Build.LazyPath{ .cwd_relative = b.cache_root.path.? }).step);
    }
}

fn addShaderStep(b: *std.Build) !*std.Build.Step {
    const shaders = [_][]const u8{
        "shaders/simple.vert",
        "shaders/simple.frag",
    };

    const shaders_step = b.step("shaders", "compile shaders");
    const wf = b.addWriteFiles();
    wf.step.name = "WriteFile shaders";
    shaders_step.dependOn(&wf.step);

    for (shaders) |path| {
        const spv_name = b.fmt("{s}.spv", .{path});

        const compile_step = b.addSystemCommand(&.{"glslc"});
        compile_step.addFileArg(b.path(path));
        const spv_cache_path = compile_step.addPrefixedOutputFileArg("-o", spv_name);

        _ = wf.addCopyFile(spv_cache_path, spv_name);
    }

    const shader_install_dir = b.addInstallDirectory(.{
        .source_dir = wf.getDirectory(),
        .install_dir = .bin,
        .install_subdir = "",
    });

    shaders_step.dependOn(&shader_install_dir.step);

    return shaders_step;
}
