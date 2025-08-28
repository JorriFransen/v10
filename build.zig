const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const main_module = b.addModule("main", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "v10",
        .root_module = main_module,
    });

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the engine");
    run_step.dependOn(&run_exe.step);
}
