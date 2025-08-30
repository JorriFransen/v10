const std = @import("std");

pub const core = @import("wayland/wayland_client_core.zig");
pub const protocol = @import("wayland/wayland_client_protocol.zig");

pub fn load(lib: *std.DynLib) !void {
    try core.load(lib);
    try protocol.interface.load(lib);
}
