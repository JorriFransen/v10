const std = @import("std");

pub const c = @cImport({
    @cInclude("stb/stb_image.h");
});

pub const stbi_load = f("stbi_load", fn (path: [*:0]const u8, x: *c_int, y: *c_int, c: *c_int, desired_c: c_int) callconv(.c) ?[*]const u8);
pub const stbi_load_from_memory = f("stbi_load_from_memory", fn (buffer: [*]const u8, len: c_int, x: *c_int, y: *c_int, c: *c_int, desired_c: c_int) callconv(.c) ?[*]const u8);
pub const stbi_image_free = f("stbi_image_free", fn (data: [*]const u8) callconv(.c) void);

fn f(comptime name: []const u8, comptime T: type) *const T {
    return @extern(*const T, .{ .name = name, .library_name = "c" });
}

pub export fn zigAssert(condition: c_int) void {
    std.debug.assert(condition != 0);
}
