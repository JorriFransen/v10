const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_xml_dep = b.dependency("zig_xml", .{});

    const mem_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("../../src/memory/memory.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "wayland_gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "xml", .module = zig_xml_dep.module("xml") },
                .{ .name = "mem", .module = mem_module },
            },
        }),
        .use_llvm = true, // zig-xml (or maybe zig?) doesn't work with the new backend...
    });
    const exe_install = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&exe_install.step);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.setCwd(b.path("./"));
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(&exe_install.step);
    if (b.args) |args| run_cmd.addArgs(args);
}
