const std = @import("std");

const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const ResolvedTarget = Build.ResolvedTarget;
const Step = Build.Step;

var use_llvm: bool = undefined;
var internal_build: bool = true;

const runtree_dir = "runtree";

pub fn build(b: *Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    use_llvm = b.option(bool, "llvm", "Use the llvm backend (ignored on windows, linux debug)") orelse false;
    if (target.result.os.tag == .windows) use_llvm = true;

    internal_build = b.option(bool, "internal_build", "Internal build") orelse internal_build;

    var options = b.addOptions();
    options.addOption(bool, "internal_build", internal_build);
    options.addOption(bool, "debug", optimize == .Debug);

    const mem_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/memory/memory.zig"),
    });

    const modules = Modules{
        .options = options.createModule(),
        .memory = mem_module,
        .xml = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/xml.zig"),
            .imports = &.{
                .{ .name = "mem", .module = mem_module },
            },
        }),
    };

    std.fs.cwd().makeDir(runtree_dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    const tools = try buildTools(b, optimize, target, &modules);

    const game = try buildGameLib(b, optimize, target, &modules);
    const engine = try buildEngine(b, optimize, target, &modules, &tools);
    engine.run.step.dependOn(&game.install.step);

    const clean_step = b.step("clean", "Clean build and cache");
    const rm_zig_out = b.addRemoveDirTree(b.path("zig-out"));
    const rm_cache = b.addRemoveDirTree(b.path(".zig-cache"));
    clean_step.dependOn(&rm_zig_out.step);
    clean_step.dependOn(&rm_cache.step);
}

const Modules = struct {
    options: *Build.Module,
    memory: *Build.Module,
    xml: *Build.Module,
};

const Engine = struct {
    build: *Step.Compile,
    install: *Step.InstallArtifact,
    run: *Step.Run,
};

fn buildEngine(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, modules: *const Modules, tools: *const Tools) !Engine {
    const os = target.result.os.tag;

    const exe = switch (os) {
        else => return error.PlatformNotSupported,
        .windows => try buildEngineWindows(b, optimize, target, modules, tools),
        .linux => try buildEngineLinux(b, optimize, target, modules, tools),
    };
    exe.root_module.addImport("mem", modules.memory);
    exe.root_module.addImport("options", modules.options);

    const exe_install = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .prefix } });
    b.getInstallStep().dependOn(&exe_install.step);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(&exe_install.step);
    const run_step = b.step("run", "Run the engine");
    run_step.dependOn(&run_exe.step);
    // run_exe.setCwd(b.path(runtree_dir));
    run_exe.setCwd(Build.LazyPath{ .cwd_relative = b.getInstallPath(.{ .prefix = {} }, "") });
    if (b.args) |a| run_exe.addArgs(a);

    return .{
        .build = exe,
        .install = exe_install,
        .run = run_exe,
    };
}

fn buildEngineWindows(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, modules: *const Modules, tools: *const Tools) !*Step.Compile {
    _ = modules;
    _ = tools;

    const root_module = b.addModule("main", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/win32_v10.zig"),
        .link_libc = true,
        .imports = &.{},
    });

    const exe = b.addExecutable(.{
        .name = "v10",
        .root_module = root_module,
    });
    exe.linkSystemLibrary("kernel32");
    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("winmm");
    exe.subsystem = .Windows;

    return exe;
}

fn buildEngineLinux(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, modules: *const Modules, tools: *const Tools) !*Step.Compile {
    _ = modules;

    const root_module = b.addModule("main", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/linux_v10.zig"),
        .link_libc = true, // Required for dlopen, maybe more
        .imports = &.{
            .{ .name = "wayland", .module = tools.wayland_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "v10",
        .root_module = root_module,
        .use_llvm = use_llvm,
    });

    return exe;
}

const Game = struct {
    build: *Step.Compile,
    install: *Step.InstallArtifact,
};

fn buildGameLib(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, modules: *const Modules) !Game {
    const game_root_module = b.addModule("main", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/v10.zig"),
        .imports = &.{
            .{ .module = modules.options, .name = "options" },
        },
    });

    const lib = b.addLibrary(.{
        .name = "v10_game",
        .root_module = game_root_module,
        .linkage = .dynamic,
        .use_llvm = use_llvm,
    });

    const lib_install = b.addInstallArtifact(lib, .{ .dest_dir = .{
        .override = .prefix,
    } });
    b.getInstallStep().dependOn(&lib_install.step);

    if (lib_install.implib_dir) |_| {
        lib_install.implib_dir = null;
    }

    return .{
        .build = lib,
        .install = lib_install,
    };
}

// TODO: Maybe merge this with 'Modules'?
const Tools = struct {
    wayland_module: *Build.Module,
};

fn buildTools(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, modules: *const Modules) !Tools {
    const cli_parse_dep = b.dependency("zig_cli_parse", .{});

    const exe = b.addExecutable(.{
        .name = "wayland-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/wayland-gen/src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "xml", .module = modules.xml },
                .{ .name = "mem", .module = modules.memory },
                .{ .name = "clip", .module = cli_parse_dep.module("CliParse") },
            },
        }),
        .use_llvm = use_llvm,
    });

    // b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("wayland-gen", "Generate wayland bindings");
    run_step.dependOn(&run_exe.step);
    run_exe.setCwd(b.path("."));

    _ = run_exe.addPrefixedFileArg("--wayland=", b.path("vendor/wayland/wayland.xml"));
    _ = run_exe.addPrefixedFileArg("--protocol=", b.path("vendor/wayland/xdg_shell.xml"));
    _ = run_exe.addPrefixedFileArg("--protocol=", b.path("vendor/wayland/xdg-decoration-unstable-v1.xml"));
    _ = run_exe.addPrefixedFileArg("--protocol=", b.path("vendor/wayland/viewporter.xml"));

    const wayland_source = run_exe.addPrefixedOutputFileArg("--out=", "wayland.zig");

    return .{
        .wayland_module = b.createModule(.{
            .optimize = optimize,
            .target = target,
            .root_source_file = wayland_source,
        }),
    };
}
