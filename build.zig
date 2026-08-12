const std = @import("std");
const assert = std.debug.assert;

const Build = std.Build;
const Module = Build.Module;
const OptimizeMode = std.builtin.OptimizeMode;
const ResolvedTarget = Build.ResolvedTarget;
const Step = Build.Step;

var use_llvm: bool = false;
var tools_optimize: OptimizeMode = .ReleaseSafe;
var internal_build: bool = true;
var verbose_wayland: bool = false;
// TODO: pulsePull requires locking during gamecode reload
var linux_audio_impl: LinuxAudioImplementation = .pulseEmulateDSound;
var cross_compile = false;

const src_path = "src";

pub fn build(b: *Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const native_target = b.resolveTargetQuery(.{});
    cross_compile = !target.query.eql(native_target.query);

    use_llvm = b.option(bool, "llvm", "Use the llvm backend (ignored on windows, linux debug)") orelse use_llvm;
    if (target.result.os.tag == .windows) use_llvm = true;

    internal_build = b.option(bool, "internal_build", "Internal build") orelse internal_build;
    tools_optimize = b.option(OptimizeMode, "tools_optimize", "Optimization mode for tools") orelse tools_optimize;

    verbose_wayland = b.option(bool, "verbose_wayland", "Verbose wayland logging") orelse verbose_wayland;

    var options = b.addOptions();
    options.addOption(bool, "internal_build", internal_build);
    options.addOption(bool, "debug", optimize == .Debug);
    options.addOption(OptimizeMode, "tools_optimize", tools_optimize);

    const options_module = options.createModule();

    const core_module = b.createModule(.{
        .optimize = optimize,
        .root_source_file = b.path(src_path ++ "/core/core.zig"),
    });

    const common_module = b.createModule(.{
        .optimize = optimize,
        .root_source_file = b.path(src_path ++ "/v10_common.zig"),
        .imports = &.{
            .{ .name = "options", .module = options_module },
            .{ .name = "core", .module = core_module },
        },
    });

    const cli_parse_dep = b.dependency("zig_cli_parse", .{});
    const clip_module = cli_parse_dep.module("CliParse");

    var modules = Modules{
        .options = options_module,
        .core = core_module,
        .common = common_module,
        .clip = clip_module,
    };

    const tools = try Tools.build(b, native_target, target, &modules);

    const engine = try buildEngine(b, optimize, target, &modules, &tools);
    const game = try buildGameLib(b, optimize, target, &engine);
    _ = game;

    var run_asset_compiler = false;
    if (tools.asset_compiler) |_| {
        const asset_mode: AssetBuildMode = if (internal_build and !cross_compile) .engine else .build;
        run_asset_compiler = asset_mode == .engine;

        const rel_scan_dir = "raw_art";
        const rel_output_dir = "data";

        try buildAssets(b, &engine, &tools, asset_mode, rel_scan_dir, rel_output_dir);

        if (internal_build) {
            options.addOption(bool, "run_asset_compiler", run_asset_compiler);

            if (asset_mode == .engine) {
                options.addOption([]const u8, "asset_compiler_scan_dir", b.pathFromRoot(rel_scan_dir));
                options.addOption([]const u8, "asset_compiler_output_dir", b.pathFromRoot(rel_output_dir));
            }
        }
    } else {
        std.log.warn("Skipping asset compilation", .{});
    }

    try buildTests(b, &modules);
}

const Modules = struct {
    options: *Module,
    core: *Module,
    clip: *Module,

    common: *Module,
};

const Engine = struct {
    build: *Step.Compile,
    install: *Step.InstallArtifact,
    run: *Step.Run,

    modules: *const Modules,
    tools: *const Tools,
};

fn buildEngine(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, modules: *const Modules, tools: *const Tools) !Engine {
    const os = target.result.os.tag;

    const exe = switch (os) {
        else => return error.PlatformNotSupported,
        .windows => try buildEngineWindows(b, optimize, target),
        .linux => try buildEngineLinux(b, optimize, target, modules, tools),
    };
    exe.root_module.addImport("core", modules.core);
    exe.root_module.addImport("options", modules.options);
    exe.root_module.addImport("v10_common", modules.common);

    const exe_install = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .prefix } });
    b.getInstallStep().dependOn(&exe_install.step);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep()); // To ensure we run the installed exe, not the one in cache

    const run_step = b.step("run", "Run the engine");
    run_step.dependOn(&run_exe.step);
    // run_exe.setCwd(b.graph.path(.install_prefix, ""));
    // run_exe.addPassthruArgs();
    run_exe.setCwd(b.path("data/"));
    if (b.args) |a| run_exe.addArgs(a);

    return .{
        .build = exe,
        .install = exe_install,
        .run = run_exe,
        .modules = modules,
        .tools = tools,
    };
}

fn buildEngineWindows(b: *Build, optimize: OptimizeMode, target: ResolvedTarget) !*Step.Compile {
    const root_module = b.addModule("main", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path(src_path ++ "/win32_v10.zig"),
        .link_libc = false,
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

const LinuxAudioImplementation = enum {
    pulseEmulateDSound,
    pulsePull,
};

fn buildEngineLinux(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, modules: *const Modules, tools: *const Tools) !*Step.Compile {
    linux_audio_impl = b.option(LinuxAudioImplementation, "linux_audio_impl", "Linux audio implementation") orelse linux_audio_impl;

    var linux_options = b.addOptions();
    linux_options.addOption(LinuxAudioImplementation, "linux_audio_impl", linux_audio_impl);
    const linux_options_module = linux_options.createModule();

    const wayland_module = tools.wayland_gen.?.module(
        b,
        optimize,
        modules,
        "vendor/wayland/wayland.xml",
        &.{
            "vendor/wayland/xdg_shell.xml",
            "vendor/wayland/xdg-decoration-unstable-v1.xml",
        },
    );

    const root_module = b.addModule("main", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path(src_path ++ "/linux_v10.zig"),
        .link_libc = true,
        .imports = &.{
            .{ .name = "wayland", .module = wayland_module },
            .{ .name = "linux_options", .module = linux_options_module },
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

fn buildGameLib(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, engine: *const Engine) !Game {
    const game_root_module = b.addModule("gamelib", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path(src_path ++ "/v10.zig"),
        .link_libc = true,
        .imports = &.{
            .{ .module = engine.modules.options, .name = "options" },
            .{ .module = engine.modules.core, .name = "core" },
            .{ .module = engine.modules.common, .name = "v10_common" },
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
    engine.run.step.dependOn(&lib_install.step);

    if (lib_install.implib_dir) |_| {
        lib_install.implib_dir = null;
    }

    return .{
        .build = lib,
        .install = lib_install,
    };
}

const Tools = struct {
    wayland_gen: ?WaylandGen,
    asset_compiler: ?AssetCompiler,

    fn build(b: *Build, tools_target: ResolvedTarget, target: ResolvedTarget, modules: *Modules) !Tools {
        const result: Tools = .{
            .wayland_gen = if (target.result.os.tag == .linux)
                WaylandGen.build(b, tools_target, modules)
            else
                null,

            .asset_compiler = AssetCompiler.build(b, tools_target, modules),
        };

        return result;
    }

    pub const WaylandGen = struct {
        gen_exe: *Step.Compile,
        options_module: *Module,

        fn build(b: *Build, tools_target: ResolvedTarget, modules: *Modules) ?WaylandGen {
            const options = b.addOptions();
            options.addOption(bool, "verbose_wayland", verbose_wayland);
            const options_module = options.createModule();

            const wayland_gen_exe = b.addExecutable(.{
                .name = "wayland_gen",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("tools/wayland_gen/src/wayland_generator.zig"),
                    .target = tools_target,
                    .optimize = tools_optimize,
                    .imports = &.{
                        .{ .name = "core", .module = modules.core },
                        .{ .name = "clip", .module = modules.clip },
                        .{ .name = "options", .module = options_module },
                        .{ .name = "v10_common", .module = modules.common },
                    },
                }),
                .use_llvm = use_llvm,
            });
            wayland_gen_exe.root_module.addAnonymousImport("lib/client.zig", .{ .root_source_file = b.path("tools/wayland_gen/lib/client.zig") });
            wayland_gen_exe.root_module.addAnonymousImport("lib/root_template.zig", .{ .root_source_file = b.path("tools/wayland_gen/lib/root_template.zig") });

            return .{ .gen_exe = wayland_gen_exe, .options_module = options_module };
        }

        pub fn module(this: *const WaylandGen, b: *Build, optimize: OptimizeMode, modules: *const Modules, core_xml_path: []const u8, protocol_xml_paths: []const []const u8) *Module {
            const run_wayland_gen_exe = b.addRunArtifact(this.gen_exe);

            _ = run_wayland_gen_exe.addPrefixedFileArg("--wayland=", b.path(core_xml_path));
            for (protocol_xml_paths) |protocol_xml_path| {
                _ = run_wayland_gen_exe.addPrefixedFileArg("--protocol=", b.path(protocol_xml_path));
            }

            const wayland_source_dir = run_wayland_gen_exe.addPrefixedOutputDirectoryArg("--out=", "wayland");

            const result = b.createModule(.{
                .optimize = optimize,
                .root_source_file = wayland_source_dir.path(b, "root.zig"),
                .imports = &.{
                    .{ .name = "core", .module = modules.core },
                    .{ .name = "options", .module = this.options_module },
                },
            });

            return result;
        }
    };

    pub const AssetCompiler = struct {
        exe: *Step.Compile,
        module: *Module,

        fn build(b: *Build, tools_target: ResolvedTarget, modules: *Modules) ?AssetCompiler {
            const aseprite_names: []const []const u8 = if (tools_target.result.os.tag == .windows)
                &.{"aseprite.exe"}
            else
                &.{"aseprite"};

            const aseprite_exe = b.findProgram(aseprite_names, &.{}) catch {
                std.log.warn("Unable to find aseprite executable", .{});
                return null;
            };

            const options = b.addOptions();
            options.addOption([]const u8, "aseprite_exe_path", aseprite_exe);
            options.addOptionPath("aseprite_script_path", b.path("tools/aseprite/"));

            const option_module = options.createModule();

            const root_module = b.createModule(.{
                .root_source_file = b.path("tools/asset_compiler/asset_compiler.zig"),
                .target = tools_target,
                .optimize = tools_optimize,
                .imports = &.{
                    .{ .name = "core", .module = modules.core },
                    .{ .name = "clip", .module = modules.clip },
                    .{ .name = "options", .module = option_module },
                    .{ .name = "v10_common", .module = modules.common },
                },
            });

            const asset_compiler_exe = b.addExecutable(.{
                .name = "asset_compiler",
                .root_module = root_module,
                .use_llvm = use_llvm,
            });

            b.installArtifact(asset_compiler_exe);

            return .{
                .exe = asset_compiler_exe,
                .module = root_module,
            };
        }
    };
};

pub const AssetBuildMode = enum {
    engine,
    build,
};

pub fn buildAssets(b: *Build, engine: *const Engine, tools: *const Tools, mode: AssetBuildMode, scan_dir: []const u8, output_dir: []const u8) !void {
    assert(tools.asset_compiler != null);

    const asset_compiler = tools.asset_compiler.?;

    switch (mode) {
        .engine => {
            engine.modules.common.addImport("asset_compiler", asset_compiler.module);
        },

        .build => {
            const asset_step = b.step("assets", "compile assets");

            const asset_compiler_run = b.addRunArtifact(asset_compiler.exe);
            asset_step.dependOn(&asset_compiler_run.step);

            if (b.verbose) {
                asset_compiler_run.addArg("-v");
            }

            asset_compiler_run.addPrefixedDirectoryArg("-i", b.path(scan_dir));
            asset_compiler_run.addPrefixedDirectoryArg("-o", b.path(output_dir));

            b.getInstallStep().dependOn(asset_step);
            engine.run.step.dependOn(asset_step);
        },
    }
}

pub fn buildTests(b: *Build, modules: *const Modules) !void {
    const test_step = b.step("test", "run all tests");
    const test_install_step = b.step("test_install", "install tests");

    const clip_test_exe = b.addTest(.{ .root_module = modules.clip, .name = "clip_test" });
    const clip_test_run = b.addRunArtifact(clip_test_exe);
    const clip_test_install = b.addInstallArtifact(clip_test_exe, .{ .dest_dir = .{ .override = .{ .custom = "test" } } });

    test_step.dependOn(&clip_test_run.step);
    test_install_step.dependOn(&clip_test_install.step);
}
