const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    std.fs.cwd().makeDir("runtree") catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

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

    const exe_install = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&exe_install.step);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(&exe_install.step);
    const run_step = b.step("run", "Run the engine");
    run_step.dependOn(&run_exe.step);
    run_exe.setCwd(b.path("runtree"));
    if (b.args) |a| run_exe.addArgs(a);
}
