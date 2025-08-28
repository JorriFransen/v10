const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const Scanner = @import("zig_wayland").Scanner;

    const scanner = Scanner.create(b, .{});

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");

    scanner.generate("wl_seat", 4);
    scanner.generate("xdg_wm_base", 3);

    const gen_file = b.addInstallFileWithDir(scanner.result, .prefix, "wayland.zig");
    b.getInstallStep().dependOn(&gen_file.step);

    _ = optimize;
    _ = target;
}
