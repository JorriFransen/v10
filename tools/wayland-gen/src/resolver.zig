const std = @import("std");
const assert = std.debug.assert;

const mem = @import("mem");

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
    var tmp = mem.getTemp();
    defer tmp.release();

    if (std.mem.findScalar(u8, interface.name, '_')) |idx| {
        assert(interface.name.len > idx + 1);
        interface.zig_name = try toZigTypeName(context, tmp.arena, interface.name[idx + 1 ..]);
    } else {
        try context.stderr.print("Invalid interface name, missing '_' in '{s}'", .{interface.name});
        return error.InterfaceNameWithoutPrefix;
    }

    for (interface.requests) |*message| {
        try resolveMessage(context, protocol, interface, message, core, tmp.arena);
    }

    for (interface.events) |*message| {
        try resolveMessage(context, protocol, interface, message, core, tmp.arena);
    }
}

fn resolveMessage(context: *const Context, protocol: *const AST.Protocol, interface: *const AST.Interface, message: *AST.Message, core: bool, tmp: *mem.Arena) Error!void {
    _ = protocol;
    _ = interface;
    _ = core;

    message.zig_name = try toZigFunctionName(context, tmp, message.name);
}

fn toZigTypeName(context: *const Context, tmp: *mem.Arena, name: []const u8) ![]const u8 {
    const buf = try tmp.allocator().alloc(u8, name.len);
    var result: std.ArrayList(u8) = .initBuffer(buf);

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

    return try std.fmt.allocPrint(context.arena, "{f}", .{std.zig.fmtId(result.items)});
}

fn toZigFunctionName(context: *const Context, tmp: *mem.Arena, name: []const u8) ![]const u8 {
    const buf = try tmp.allocator().alloc(u8, name.len);
    var result: std.ArrayList(u8) = .initBuffer(buf);

    var cap_next = false;
    for (name) |c| {
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

    return try std.fmt.allocPrint(context.arena, "{f}", .{std.zig.fmtId(result.items)});
}
