const std = @import("std");

const wl = @import("wayland.zig");

pub const Object = struct {
    id: u32,
    version: u32,
    interface: *const Interface,
    freelist_node: std.SinglyLinkedList.Node = .{},
    listeners: std.SinglyLinkedList = .{},
};

pub const RegisteredListener = struct {
    user_data: ?*anyopaque,
    node: std.SinglyLinkedList.Node = .{},
    implementation: []const *const fn () void,
};

pub const Interface = struct {
    name: []const u8,
    version: u32,
    methods: []const Message,
    events: []const Message,

    pub const Message = struct {
        name: []const u8,
    };
};
