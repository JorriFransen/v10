const std = @import("std");
const log = std.log.scoped(.v10_build);
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clap = b.dependency("clap", .{});
    const vulkan = b.dependency("vulkan", .{
        .target = target,
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    });
    const vulkan_module = vulkan.module("vulkan-zig");
    const glfw = b.dependency("glfw", .{
        .x11 = true,
        .wayland = true,
        .target = target,
        .optimize = optimize,
    });
    const glfw_module = glfw.module("glfw");
    glfw_module.addImport("vulkan", vulkan_module);

    const main_module = b.addModule("main", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_module.addImport("clap", clap.module("clap"));
    main_module.addImport("glfw", glfw_module);
    main_module.addImport("vulkan", vulkan_module);

    const exe = b.addExecutable(.{
        .name = "v10game",
        .root_module = main_module,
    });
    b.installArtifact(exe);

    std.fs.cwd().makeDir("res") catch |e| switch (e) {
        error.PathAlreadyExists => {}, // ok,
        else => return e,
    };
    b.installDirectory(.{ .source_dir = b.path("res"), .install_dir = .bin, .install_subdir = "res" });

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());
    run_exe.setCwd(b.path("zig-out/bin"));
    if (b.args) |args| run_exe.addArgs(args);

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);

    const shader_step = try addShaderStep(b);
    exe.step.dependOn(shader_step);

    const test_options = b.addOptions();
    const test_color = b.option(bool, "color", "Enable colored test output") orelse true;
    const test_full_name = b.option(bool, "full_name", "Print full test names") orelse false;
    test_options.addOption(bool, "color", test_color);
    test_options.addOption(bool, "full_name", test_full_name);

    const test_exe = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .target = target,
        .optimize = optimize,
        .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
    });
    test_exe.root_module.addOptions("options", test_options);
    const run_tests = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);

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
