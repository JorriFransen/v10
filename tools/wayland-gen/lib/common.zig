const std = @import("std");

const wl = @import("wayland.zig");

pub const Object = struct {
    id: u32,
    version: u32,
    interface: *const Interface,
    freelist_node: std.SinglyLinkedList.Node = .{},
    listeners: std.SinglyLinkedList = .{},
};

pub const Interface = struct {
    name: []const u8,
    version: u32,
    requests: []const Message,
    events: []const Message,

    pub const Message = struct {
        name: []const u8,
    };
};

pub const RegisteredListener = struct {
    user_data: ?*anyopaque,
    node: std.SinglyLinkedList.Node = .{},
    implementation: []const *const fn () void,
};

pub const Fixed = extern struct {
    value: i32,

    pub fn toDouble(fixed: Fixed) f64 {
        return @as(f64, @floatFromInt(fixed.value)) / 256;
    }

    pub fn toInt(fixed: Fixed) c_int {
        return @divTrunc(@as(c_int, @intCast(fixed.value)), 256);
    }
};
