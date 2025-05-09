const std = @import("std");
const heap = std.heap;

var gpa_data = heap.GeneralPurposeAllocator(.{}).init;
pub const gpa = gpa_data.allocator();

pub var gfx_arena_data = heap.ArenaAllocator.init(heap.page_allocator);

pub var temp_arena_data = heap.ArenaAllocator.init(heap.page_allocator);

pub fn deinit() !void {
    gfx_arena_data.deinit();
    temp_arena_data.deinit();

    if (gpa_data.detectLeaks()) {
        return error.GpaMemoryLeaked;
    }
}
