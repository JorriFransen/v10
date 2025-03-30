const std = @import("std");
const heap = std.heap;

var gpa_data = heap.GeneralPurposeAllocator(.{}).init;
pub const gpa = gpa_data.allocator();
