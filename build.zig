const std = @import("std");

const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const ResolvedTarget = Build.ResolvedTarget;
const Step = Build.Step;

var force_llvm: bool = undefined;

pub fn build(b: *Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    force_llvm = b.option(bool, "llvm", "Use the llvm backend") orelse false;

    std.fs.cwd().makeDir("runtree") catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    const tools = try buildTools(b, optimize, target);

    _ = try buildEngine(b, optimize, target, &tools);

    const clean_step = b.step("clean", "Clean build and cache");
    const rm_zig_out = b.addRemoveDirTree(b.path("zig-out"));
    const rm_cache = b.addRemoveDirTree(b.path(".zig-cache"));
    clean_step.dependOn(&rm_zig_out.step);
    clean_step.dependOn(&rm_cache.step);
}

fn buildEngine(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, tools: *const Tools) !*Step.Compile {
    const os = target.result.os.tag;

    const exe = switch (os) {
        else => return error.PlatformNotSupported,
        .windows => try buildWindows(b, optimize, target, tools),
        .linux => try buildLinux(b, optimize, target, tools),
    };

    const exe_install = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&exe_install.step);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(&exe_install.step);
    const run_step = b.step("run", "Run the engine");
    run_step.dependOn(&run_exe.step);
    run_exe.setCwd(b.path("runtree"));
    if (b.args) |a| run_exe.addArgs(a);

    return exe;
}

fn buildWindows(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, tools: *const Tools) !*Step.Compile {
    _ = tools;

    const main_module = b.addModule("main", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/win32_v10.zig"),
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "v10",
        .root_module = main_module,
        // .use_llvm = force_llvm,
        .use_llvm = true,
    });
    exe.linkSystemLibrary("user32");
    exe.subsystem = .Windows;

    return exe;
}

fn buildLinux(b: *Build, optimize: OptimizeMode, target: ResolvedTarget, tools: *const Tools) !*Step.Compile {
    const main_module = b.addModule("main", .{
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
        .root_module = main_module,
        .use_llvm = force_llvm,
    });

    return exe;
}

const Tools = struct {
    wayland_module: *Build.Module,
};

fn buildTools(b: *Build, optimize: OptimizeMode, target: ResolvedTarget) !Tools {
    const cli_parse_dep = b.dependency("zig_cli_parse", .{});

    const mem_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/memory/memory.zig"),
    });

    const xml_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/xml.zig"),
        .imports = &.{
            .{ .name = "mem", .module = mem_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "wayland-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/wayland-gen/src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "xml", .module = xml_module },
                .{ .name = "mem", .module = mem_module },
                .{ .name = "clip", .module = cli_parse_dep.module("CliParse") },
            },
        }),
        .use_llvm = force_llvm,
    });

    // b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("wayland-gen", "Generate wayland bindings");
    run_step.dependOn(&run_exe.step);
    run_exe.setCwd(b.path("."));

    _ = run_exe.addPrefixedFileArg("--wayland=", b.path("vendor/wayland/wayland.xml"));
    _ = run_exe.addPrefixedFileArg("--protocol=", b.path("vendor/wayland/xdg_shell.xml"));
    _ = run_exe.addPrefixedFileArg("--protocol=", b.path("vendor/wayland/xdg-decoration-unstable-v1.xml"));

    const wayland_source = run_exe.addPrefixedOutputFileArg("--out=", "wayland.zig");

    return .{
        .wayland_module = b.createModule(.{
            .optimize = optimize,
            .target = target,
            .root_source_file = wayland_source,
        }),
    };
}
