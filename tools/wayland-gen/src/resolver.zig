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

    interface.zig_name = try toZigTypeName(context, tmp.arena, interface.name, true);

    for (interface.requests) |*message| {
        try resolveMessage(context, protocol, interface, message, core, tmp.arena);
    }

    for (interface.events) |*message| {
        try resolveMessage(context, protocol, interface, message, core, tmp.arena);
    }

    for (interface.enums) |*@"enum"| {
        try resolveEnum(context, protocol, interface, @"enum", core, tmp.arena);
    }
}

fn resolveMessage(context: *const Context, protocol: *const AST.Protocol, interface: *const AST.Interface, message: *AST.Message, core: bool, tmp: *mem.Arena) Error!void {
    message.zig_name = try toZigFunctionName(context, tmp, message.name);

    for (message.args) |*arg| {
        try resolveArg(context, protocol, interface, message, arg, core, tmp);
    }
}

fn resolveArg(context: *const Context, protocol: *const AST.Protocol, interface: *const AST.Interface, message: *const AST.Message, arg: *AST.Arg, core: bool, tmp: *mem.Arena) Error!void {
    _ = protocol;
    _ = interface;
    _ = message;
    _ = core;

    arg.zig_name = try toZigVariableName(context, tmp, arg.name);

    if (arg.enum_name) |enum_name| {
        arg.zig_enum_name = try toZigTypeName(context, tmp, enum_name, false);
    }

    if (arg.interface_name) |interface_name| {
        arg.zig_interface_name = try toZigTypeName(context, tmp, interface_name, true);
    }
}

fn resolveEnum(context: *const Context, protocol: *const AST.Protocol, interface: *const AST.Interface, @"enum": *AST.Enum, core: bool, tmp: *mem.Arena) Error!void {
    _ = protocol;
    _ = interface;
    _ = core;

    @"enum".zig_name = try toZigTypeName(context, tmp, @"enum".name, false);

    var int_type: ?[]const u8 = null;
    for (@"enum".entries) |*e| {
        if (int_type == null and e.value[0] == '-') {
            int_type = "c_int";
        }

        e.zig_name = try toZigVariableName(context, tmp, e.name);
    }

    @"enum".zig_int_type = int_type orelse "c_uint";
}

fn toZigTypeName(context: *const Context, tmp: *mem.Arena, maybe_prefix_name: []const u8, strip_prefix: bool) ![]const u8 {
    const name = if (strip_prefix) blk: {
        if (std.mem.findScalar(u8, maybe_prefix_name, '_')) |idx| {
            assert(maybe_prefix_name.len > idx + 1);
            break :blk maybe_prefix_name[idx + 1 ..];
        } else {
            try context.stderr.print("Invalid name, expected '_' in '{s}'", .{maybe_prefix_name});
            return error.InterfaceNameWithoutPrefix;
        }
    } else maybe_prefix_name;

    if (std.mem.findScalar(u8, name, '.')) |dot_idx| {
        assert(std.mem.countScalar(u8, name, '.') == 1);
        const first = try toZigTypeName(context, tmp, name[0..dot_idx], true);
        const second = try toZigTypeName(context, tmp, name[dot_idx + 1 ..], false);
        return try std.mem.concat(context.arena, u8, &.{ first, ".", second });
    } else {
        const buf = try tmp.allocator().alloc(u8, name.len);
        var result: std.ArrayList(u8) = .initBuffer(buf);

        result.appendAssumeCapacity(std.ascii.toUpper(name[0]));
        var cap_next = false;
        for (name[1..]) |c| {
            if (c == '_') {
                cap_next = true;
                continue;
            }

            if (cap_next) {
                cap_next = false;
                result.appendAssumeCapacity(std.ascii.toUpper(c));
            } else {
                result.appendAssumeCapacity(c);
            }
        }

        return try std.fmt.allocPrint(context.arena, "{f}", .{std.zig.fmtId(result.items)});
    }
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
            result.appendAssumeCapacity(std.ascii.toUpper(c));
        } else {
            result.appendAssumeCapacity(c);
        }
    }

    return try std.fmt.allocPrint(context.arena, "{f}", .{std.zig.fmtId(result.items)});
}

fn toZigVariableName(context: *const Context, tmp: *mem.Arena, name: []const u8) ![]const u8 {
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
            result.appendAssumeCapacity(std.ascii.toUpper(c));
        } else {
            result.appendAssumeCapacity(c);
        }
    }

    return try std.fmt.allocPrint(context.arena, "{f}", .{std.zig.fmtId(result.items)});
}
