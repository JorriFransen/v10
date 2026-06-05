const std = @import("std");
const assert = std.debug.assert;

const Context = @import("wayland_generator.zig").Context;

const AST = @import("ast.zig");

pub const Error = error{InterfaceNameWithoutPrefix} ||
    std.mem.Allocator.Error ||
    std.Io.Writer.Error;

pub fn resolveProtocol(context: *const Context, protocol: *AST.Protocol, core: bool) Error!void {
    for (protocol.interfaces) |*interface| {
        try resolveInterface(context, protocol, interface, core);
    }
}

fn resolveInterface(context: *const Context, protocol: *const AST.Protocol, interface: *AST.Interface, core: bool) Error!void {
    _ = core;
    _ = protocol;

    if (std.mem.findScalar(u8, interface.name, '_')) |idx| {
        assert(interface.name.len > idx + 1);
        interface.zig_name = try toZigTypeName(context, interface.name[idx + 1 ..]);
    } else {
        try context.stderr.print("Invalid interface name, missing '_' in '{s}'", .{interface.name});
        return error.InterfaceNameWithoutPrefix;
    }
}

fn toZigTypeName(context: *const Context, name: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .{ .items = &.{}, .capacity = 0 };

    try result.append(context.arena, std.ascii.toUpper(name[0]));
    var cap_next = false;
    for (name[1..]) |c| {
        if (c == '_') {
            cap_next = true;
            continue;
        }

        if (cap_next) {
            cap_next = false;
            try result.append(context.arena, std.ascii.toUpper(c));
        } else {
            try result.append(context.arena, c);
        }
    }

    return try result.toOwnedSlice(context.arena);
}
