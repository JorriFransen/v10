const std = @import("std");
const mem = @import("memory.zig");

const Arena = mem.Arena;

pub var common_arena: Arena = undefined;
pub var swapchain_arena: Arena = undefined;

pub var temp_arena: Arena = undefined;

pub fn init() !void {
    common_arena = try Arena.init(.{ .virtual = .{} });
    swapchain_arena = try Arena.init(.{ .virtual = .{} });

    temp_arena = try Arena.init(.{ .virtual = .{ .reserved_capacity = mem.GiB } });
}

pub fn deinit() !void {
    common_arena.deinit();
    swapchain_arena.deinit();

    temp_arena.deinit();
}
