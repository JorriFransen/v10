const std = @import("std");
const log = std.log.scoped(.v10_build);
const builtin = @import("builtin");

const LazyPath = std.Build.LazyPath;

const debugging = false;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_llvm = if (target.result.os.tag == .windows) true else debugging;

    const clap = b.dependency("clap", .{});
    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const vulkan_xml = vulkan_headers.path("registry/vk.xml");
    const vulkan = b.dependency("vulkan", .{
        .target = target,
        .registry = vulkan_xml,
    });

    const vulkan_module = vulkan.module("vulkan-zig");

    const glfw_zig = b.dependency("glfw_zig", .{
        .x11 = true,
        .wayland = true,
        .target = target,
        .optimize = optimize,
        .vulkan_xml = vulkan_xml,
        .glfw = b.dependency("glfw", .{}).path(""),
        // .shared = true,
    });
    const glfw_lib = glfw_zig.artifact("glfw");
    const glfw_module = glfw_zig.module("glfw");

    const memory_module = b.addModule("memory", .{
        .root_source_file = b.path("src/memory.zig"),
        .target = target,
        .optimize = optimize,
    });

    const main_module = b.addModule("main", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_module.addImport("clap", clap.module("clap"));
    main_module.addImport("glfw", glfw_module);
    main_module.addImport("vulkan", vulkan_module);
    main_module.addImport("memory", memory_module);

    const exe = b.addExecutable(.{
        .name = "v10game",
        .root_module = main_module,
        .use_llvm = use_llvm,
    });

    if (target.result.os.tag != .windows) {
        // TODO: This should be handled by glfw in the future?
        exe.linkSystemLibrary("fontconfig");
    }

    exe.linkLibrary(glfw_lib);

    b.installArtifact(exe);

    std.fs.cwd().makeDir("res") catch |e| switch (e) { // Create emtpy res folder if it does not exist, to avoid errors when installing
        error.PathAlreadyExists => {}, // ok,
        else => return e,
    };
    b.installDirectory(.{
        .source_dir = b.path("res"),
        .install_dir = .bin,
        .install_subdir = "res",
        .exclude_extensions = &.{ "gitignore", "blend", "blend1" },
    });

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());
    run_exe.setCwd(b.path("zig-out/bin"));
    if (b.args) |args| run_exe.addArgs(args);

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);

    const shader_step = try addShaderStep(b);
    exe.step.dependOn(shader_step);

    const test_options = b.addOptions();
    const test_log_level = b.option(std.log.Level, "test_log_level", "Minimum log level filter") orelse .err;
    const test_color = b.option(bool, "test_color", "Enable colored test output") orelse true;
    const test_full_name = b.option(bool, "test_full_name", "Print full test names") orelse true;
    test_options.addOption(std.log.Level, "test_log_level", test_log_level);
    test_options.addOption(bool, "test_color", test_color);
    test_options.addOption(bool, "test_full_name", test_full_name);

    const test_exe = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
        .use_llvm = use_llvm,
    });
    if (debugging) b.installArtifact(test_exe);
    const run_tests = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
    test_exe.root_module.addOptions("options", test_options);
    test_exe.root_module.addImport("memory", memory_module);

    // Use path join for consistency, this path is also used in the import name so it needs to match everywhere
    try anonymousImportDir(b, test_exe.root_module, b.pathJoin(&.{ "res", "semantic_test_obj" }));

    const clean_step = b.step("clean", "Clean shaders and zig-out directory");
    clean_step.dependOn(&b.addRemoveDirTree(LazyPath{ .cwd_relative = b.install_path }).step);
    if (builtin.os.tag != .windows) {
        clean_step.dependOn(&b.addRemoveDirTree(LazyPath{ .cwd_relative = b.cache_root.path.? }).step);
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

fn installDynamicLib(b: *std.Build, target: *const std.Build.ResolvedTarget, lib: *std.Build.Step.Compile) void {
    if (target.result.os.tag == .windows) {
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(lib.getEmittedBin(), .lib, lib.out_lib_filename).step);
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(lib.getEmittedBin(), .bin, lib.out_filename).step);
    } else {
        const install_name = lib.major_only_filename orelse lib.out_filename;
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(lib.getEmittedBin(), .lib, install_name).step);
    }
}

/// Add anonymous imports to module for each file in the directory specified by dir_name
fn anonymousImportDir(b: *std.Build, module: *std.Build.Module, dir_name: []const u8) !void {
    var dir = try std.fs.cwd().openDir(dir_name, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        const rel_path = b.pathJoin(&.{ dir_name, entry.path });
        module.addAnonymousImport(rel_path, .{ .root_source_file = b.path(rel_path) });
    }
}
