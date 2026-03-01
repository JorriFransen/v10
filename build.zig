const std = @import("std");

const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const ResolvedTarget = Build.ResolvedTarget;
const Step = Build.Step;

var use_llvm: bool = undefined;
var internal_build: bool = true;

const src_path = "src";

pub fn build(b: *Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const native_target = b.resolveTargetQuery(.{});

    use_llvm = b.option(bool, "llvm", "Use the llvm backend (ignored on windows, linux debug)") orelse false;
    if (target.result.os.tag == .windows) use_llvm = true;

    internal_build = b.option(bool, "internal_build", "Internal build") orelse internal_build;

    var src_dir_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const src_dir_path_len = std.Io.Dir.cwd().realPathFile(b.graph.io, src_path, &src_dir_path_buffer) catch @panic("realPathFile failed!");
    const src_dir_path = src_dir_path_buffer[0..src_dir_path_len];

    var options = b.addOptions();
    options.addOption(bool, "internal_build", internal_build);
    options.addOption(bool, "debug", optimize == .Debug);
    options.addOption([]const u8, "src_dir_path", src_dir_path);

    const dynlib_module = b.createModule(.{
        .optimize = optimize,
        .root_source_file = b.path(src_path ++ "/dynlib.zig"),
    });

    const win32_module = b.createModule(.{
        .optimize = optimize,
        .root_source_file = b.path(src_path ++ "/win32/win32.zig"),
        .imports = &.{
            .{ .name = "dynlib", .module = dynlib_module },
        },
    });
    dynlib_module.addImport("win32", win32_module);

    const mem_module = b.createModule(.{
        .optimize = optimize,
        .root_source_file = b.path(src_path ++ "/memory/memory.zig"),
        .imports = &.{
            .{ .name = "win32", .module = win32_module },
        },
    });

    const modules = Modules{
        .options = options.createModule(),
        .win32 = win32_module,
        .memory = mem_module,
        .dynlib = dynlib_module,
        .xml = b.createModule(.{
            .optimize = optimize,
            .root_source_file = b.path(src_path ++ "/xml.zig"),
            .imports = &.{
                .{ .name = "mem", .module = mem_module },
            },
        }),
    };

    const tools = try buildTools(b, optimize, native_target, &modules);

    const engine = try buildEngine(b, optimize, target, &modules, &tools);
    const game = try buildGameLib(b, optimize, target, &modules);
    engine.run.step.dependOn(&game.install.step);

    if (try buildAssets(b, &tools)) |assets| {
        engine.run.step.dependOn(assets);
        game.install.step.dependOn(assets);
    }
}

// TODO: These need to be the module options except for the target/optimize
//        options, to support passing different targets/optimize options to
//        different helper functions like buildTools.
const Modules = struct {
    options: *Build.Module,
    win32: *Build.Module,
    memory: *Build.Module,
    dynlib: *Build.Module,
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
    run_exe.setCwd(Build.LazyPath{ .cwd_relative = b.install_prefix });
    if (b.args) |a| run_exe.addArgs(a);

    return .{
        .build = exe,
        .install = exe_install,
        .run = run_exe,
    };
}

fn buildEngineWindows(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, modules: *const Modules, tools: *const Tools) !*Step.Compile {
    _ = tools;

    const root_module = b.addModule("main", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path(src_path ++ "/win32_v10.zig"),
        .link_libc = true,
        .imports = &.{
            .{ .name = "win32", .module = modules.win32 },
            .{ .name = "dynlib", .module = modules.dynlib },
        },
    });

    root_module.linkSystemLibrary("kernel32", .{});
    root_module.linkSystemLibrary("user32", .{});
    root_module.linkSystemLibrary("gdi32", .{});
    root_module.linkSystemLibrary("winmm", .{});

    const exe = b.addExecutable(.{
        .name = "v10",
        .root_module = root_module,
    });
    exe.subsystem = .Windows;

    return exe;
}

fn buildEngineLinux(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, modules: *const Modules, tools: *const Tools) !*Step.Compile {
    const root_module = b.addModule("main", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path(src_path ++ "/linux_v10.zig"),
        .link_libc = true, // Required for dlopen, maybe more
        .imports = &.{
            .{ .name = "dynlib", .module = modules.dynlib },
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
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path(src_path ++ "/v10.zig"),
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
    aseprite_script_runner: ?*Step.Compile,
};

fn buildTools(b: *Build, optimize: OptimizeMode, native_target: ResolvedTarget, modules: *const Modules) !Tools {
    const cli_parse_dep = b.dependency("zig_cli_parse", .{});

    const wayland_gen_exe = b.addExecutable(.{
        .name = "wayland-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/wayland-gen/src/main.zig"),
            .target = native_target,
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

    const run_wayland_gen_exe = b.addRunArtifact(wayland_gen_exe);
    const run_wayland_gen_exe_step = b.step("wayland-gen", "Generate wayland bindings");
    run_wayland_gen_exe_step.dependOn(&run_wayland_gen_exe.step);
    run_wayland_gen_exe.setCwd(b.path("."));

    _ = run_wayland_gen_exe.addPrefixedFileArg("--wayland=", b.path("vendor/wayland/wayland.xml"));
    _ = run_wayland_gen_exe.addPrefixedFileArg("--protocol=", b.path("vendor/wayland/xdg_shell.xml"));
    _ = run_wayland_gen_exe.addPrefixedFileArg("--protocol=", b.path("vendor/wayland/xdg-decoration-unstable-v1.xml"));

    const wayland_source = run_wayland_gen_exe.addPrefixedOutputFileArg("--out=", "wayland.zig");
    const wayland_module = b.createModule(.{
        .optimize = optimize,
        .root_source_file = wayland_source,
    });

    const aseprite_script_runner_exe = if (b.findProgram(&.{"aseprite"}, &.{})) |_|
        b.addExecutable(.{
            .name = "aseprite-script-runner",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/aseprite/script_runner.zig"),
                .target = native_target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "mem", .module = modules.memory },
                    .{ .name = "clip", .module = cli_parse_dep.module("CliParse") },
                },
            }),
            .use_llvm = use_llvm,
        })
    else |_|
        null;

    return .{
        .wayland_module = wayland_module,
        .aseprite_script_runner = aseprite_script_runner_exe,
    };
}

pub fn buildAssets(b: *Build, tools: *const Tools) !?*Step {
    // TODO: Check for asprite availability

    var assets: ?*Step = null;

    if (tools.aseprite_script_runner) |script_runner| {
        assets = createAspriteExportRunner(b, script_runner, "assets", true);

        _ = createAspriteExportRunner(b, script_runner, "force-assets", false);
    }

    return assets;
}

pub fn createAspriteExportRunner(b: *Build, script_runner: *Step.Compile, name: []const u8, donefile: bool) *Step {
    const asprite_extract_files: []const []const u8 = &.{
        "data/test_background.aseprite",
    };
    const asprite_extract_layers_recursive_files: []const []const u8 = &.{
        "data/test_hero.aseprite",
    };

    const assets = b.step(name, "Generate assets from raw art files");

    const run_extract = b.addRunArtifact(script_runner);
    run_extract.setName("aseprite extract.lua");
    run_extract.addPrefixedFileArg("-s", b.path("tools/aseprite/scripts/extract.lua"));
    for (asprite_extract_files) |input_file| {
        run_extract.addPrefixedFileArg("-i", b.path(input_file));
    }
    if (donefile) _ = run_extract.addPrefixedOutputFileArg("-d", "done");
    assets.dependOn(&run_extract.step);

    const run_extract_layers_recursive = b.addRunArtifact(script_runner);
    run_extract_layers_recursive.setName("asprite extract_layers_recursive.lua");
    run_extract_layers_recursive.addPrefixedFileArg("-s", b.path("tools/aseprite/scripts/extract_layers_recursive.lua"));
    for (asprite_extract_layers_recursive_files) |input_file| {
        run_extract_layers_recursive.addPrefixedFileArg("-i", b.path(input_file));
    }
    if (donefile) _ = run_extract_layers_recursive.addPrefixedOutputFileArg("-d", "done");
    assets.dependOn(&run_extract_layers_recursive.step);

    return assets;
}
