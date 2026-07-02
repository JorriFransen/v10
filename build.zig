const std = @import("std");
const assert = std.debug.assert;

const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const ResolvedTarget = Build.ResolvedTarget;
const Step = Build.Step;

var use_llvm: bool = false;
var tools_optimize: OptimizeMode = .ReleaseSafe;
var internal_build: bool = true;
var verbose_wayland: bool = false;
var linux_audio_impl: LinuxAudioImplementation = .pulseEmulateDSound;
var cross_compile = false;
var compile_assets_from_engine = true;

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

    compile_assets_from_engine = internal_build and !cross_compile;

    var options = b.addOptions();
    options.addOption(bool, "internal_build", internal_build);
    if (internal_build) {
        options.addOption(bool, "cross_compile", cross_compile);
    }
    options.addOption(bool, "debug", optimize == .Debug);
    options.addOption(OptimizeMode, "tools_optimize", tools_optimize);

    const options_module = options.createModule();

    const arch_module = b.createModule(.{
        .optimize = optimize,
        .root_source_file = b.path(src_path ++ "/arch/arch.zig"),
    });

    const dynlib_module = b.createModule(.{
        .optimize = optimize,
        .root_source_file = b.path(src_path ++ "/dynlib.zig"),
    });

    const linux_module = b.createModule(.{
        .optimize = optimize,
        .root_source_file = b.path(src_path ++ "/linux/linux.zig"),
        .imports = &.{
            .{ .name = "arch", .module = arch_module },
            .{ .name = "options", .module = options_module },
        },
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
            .{ .name = "linux", .module = linux_module },
            .{ .name = "win32", .module = win32_module },
        },
    });

    const cli_parse_dep = b.dependency("zig_cli_parse", .{});
    const clip_module = cli_parse_dep.module("CliParse");

    var modules = Modules{
        .options = options_module,
        .arch = arch_module,
        .linux = linux_module,
        .win32 = win32_module,
        .memory = mem_module,
        .dynlib = dynlib_module,
        .clip = clip_module,
        .xml = b.createModule(.{
            .optimize = optimize,
            .root_source_file = b.path(src_path ++ "/xml.zig"),
            .imports = &.{
                .{ .name = "mem", .module = mem_module },
            },
        }),
    };

    const tools = try Tools.build(b, native_target, target, &modules);

    const engine = try buildEngine(b, optimize, target, &modules, &tools);
    const game = try buildGameLib(b, optimize, target, &engine);

    const assets = try buildAssets(b, &engine, &tools);

    _ = game;
    _ = assets;

    try buildTests(b, &modules);
}

const Modules = struct {
    options: *Build.Module,
    arch: *Build.Module,
    linux: *Build.Module,
    win32: *Build.Module,
    memory: *Build.Module,
    dynlib: *Build.Module,
    xml: *Build.Module,
    clip: *Build.Module,
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
        .windows => try buildEngineWindows(b, optimize, target, modules),
        .linux => try buildEngineLinux(b, optimize, target, modules, tools),
    };
    exe.root_module.addImport("mem", modules.memory);
    exe.root_module.addImport("options", modules.options);

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

fn buildEngineWindows(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, modules: *const Modules) !*Step.Compile {
    const root_module = b.addModule("main", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path(src_path ++ "/win32_v10.zig"),
        .link_libc = false,
        .imports = &.{
            .{ .name = "arch", .module = modules.arch },
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
            .{ .name = "arch", .module = modules.arch },
            .{ .name = "linux", .module = modules.linux },
            .{ .name = "dynlib", .module = modules.dynlib },
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
        .imports = &.{
            .{ .module = engine.modules.options, .name = "options" },
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
    asset_compiler: AssetCompiler,

    fn build(b: *Build, tools_target: ResolvedTarget, target: ResolvedTarget, modules: *Modules) !Tools {
        const result: Tools = .{
            .wayland_gen = if (target.result.os.tag == .linux)
                WaylandGen.build(b, tools_target, modules)
            else
                null,

            .asset_compiler = try AssetCompiler.build(b, tools_target, modules),
        };

        return result;
    }

    pub const WaylandGen = struct {
        gen_exe: *Step.Compile,
        options_module: *Build.Module,

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
                        .{ .name = "xml", .module = modules.xml },
                        .{ .name = "mem", .module = modules.memory },
                        .{ .name = "clip", .module = modules.clip },
                        .{ .name = "options", .module = options_module },
                    },
                }),
                .use_llvm = use_llvm,
            });
            wayland_gen_exe.root_module.addAnonymousImport("lib/client.zig", .{ .root_source_file = b.path("tools/wayland_gen/lib/client.zig") });
            wayland_gen_exe.root_module.addAnonymousImport("lib/root_template.zig", .{ .root_source_file = b.path("tools/wayland_gen/lib/root_template.zig") });

            return .{ .gen_exe = wayland_gen_exe, .options_module = options_module };
        }

        pub fn module(this: *const WaylandGen, b: *Build, optimize: OptimizeMode, modules: *const Modules, core_xml_path: []const u8, protocol_xml_paths: []const []const u8) *Build.Module {
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
                    .{ .name = "linux", .module = modules.linux },
                    .{ .name = "options", .module = this.options_module },
                },
            });

            return result;
        }
    };

    pub const AssetCompiler = struct {
        exe: *Step.Compile,
        module: *Build.Module,

        fn build(b: *Build, tools_target: ResolvedTarget, modules: *Modules) !AssetCompiler {
            const aseprite_exe = try b.findProgram(&.{"aseprite"}, &.{});

            const options = b.addOptions();
            options.addOption([]const u8, "aseprite_exe_path", aseprite_exe);
            options.addOptionPath("aseprite_script_path", b.path("tools/aseprite/"));

            const option_module = options.createModule();

            const root_module = b.createModule(.{
                .root_source_file = b.path("tools/asset_compiler/asset_compiler.zig"),
                .target = tools_target,
                .optimize = tools_optimize,
                .imports = &.{
                    .{ .name = "mem", .module = modules.memory },
                    .{ .name = "clip", .module = modules.clip },
                    .{ .name = "options", .module = option_module },
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

pub fn buildAssets(b: *Build, engine: *const Engine, tools: *const Tools) !*Step {
    const asset_step = b.step("assets", "compile assets");

    if (compile_assets_from_engine) {
        engine.build.root_module.addImport("asset_compiler", tools.asset_compiler.module);
    } else {
        const asset_compiler_run = b.addRunArtifact(tools.asset_compiler.exe);
        asset_step.dependOn(&asset_compiler_run.step);

        if (b.verbose) {
            asset_compiler_run.addArg("-v");
        }

        asset_compiler_run.addPrefixedDirectoryArg("-i", b.path("data"));
        asset_compiler_run.addPrefixedDirectoryArg("-o", b.path("data/test"));
    }

    b.getInstallStep().dependOn(asset_step);
    engine.run.step.dependOn(asset_step);

    return asset_step;
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
