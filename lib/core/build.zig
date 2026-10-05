const std = @import("std");

var test_fs = false;

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    test_fs = b.option(bool, "test_fs", "include modifying filesystem tests in the root tests") orelse test_fs;

    const options = b.addOptions();
    options.addOption(bool, "test_fs", test_fs);

    _ = b.addModule("core", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/core.zig"),
        .imports = &.{.{ .name = "options", .module = options.createModule() }},
    });
}
