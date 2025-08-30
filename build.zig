const std = @import("std");

const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const ResolvedTarget = Build.ResolvedTarget;
const Step = Build.Step;

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const os = target.result.os.tag;

    std.fs.cwd().makeDir("runtree") catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    const buildForTarget = switch (os) {
        else => return error.PlatformNotSupported,
        .windows => &buildWindows,
        .linux => &buildLinux,
    };

    const exe = try buildForTarget(b, optimize, target);

    const exe_install = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&exe_install.step);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(&exe_install.step);
    const run_step = b.step("run", "Run the engine");
    run_step.dependOn(&run_exe.step);
    run_exe.setCwd(b.path("runtree"));
    if (b.args) |a| run_exe.addArgs(a);
}

fn buildWindows(b: *std.Build, optimize: OptimizeMode, target: ResolvedTarget) !*Step.Compile {
    const main_module = b.addModule("main", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/win32_v10.zig"),
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "v10",
        .root_module = main_module,
    });
    exe.linkSystemLibrary("user32");
    exe.subsystem = .Windows;

    return exe;
}

fn buildLinux(b: *Build, optimize: OptimizeMode, target: ResolvedTarget) !*Step.Compile {
    const main_module = b.addModule("main", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/linux_v10.zig"),
        .link_libc = true, // Required for dlopen, maybe more
    });

    const exe = b.addExecutable(.{
        .name = "v10",
        .root_module = main_module,
    });
    exe.linkSystemLibrary("wayland-client");

    return exe;
}
