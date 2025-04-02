const std = @import("std");
const heap = std.heap;

var gpa_data = heap.GeneralPurposeAllocator(.{}).init;
pub const gpa = gpa_data.allocator();

pub fn reportLeaks() !void {
    if (gpa_data.detectLeaks()) {
        return error.GpaMemoryLeaked;
    }
}
