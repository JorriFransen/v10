const std = @import("std");
const Arena = @import("memory.zig").Arena;
const heap = std.heap;

var gpa_data = heap.GeneralPurposeAllocator(.{}).init;
pub const gpa = gpa_data.allocator();

pub var common_arena: Arena = undefined;
pub var swapchain_arena: Arena = undefined;

pub var temp_arena_data = heap.ArenaAllocator.init(heap.page_allocator);

pub fn init() !void {
    common_arena = try Arena.init(.{ .virtual = .{} });
    swapchain_arena = try Arena.init(.{ .virtual = .{} });
}

pub fn deinit() !void {
    common_arena.deinit();
    swapchain_arena.deinit();

    temp_arena_data.deinit();

    if (gpa_data.detectLeaks()) {
        return error.GpaMemoryLeaked;
    }
}
