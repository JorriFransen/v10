const std = @import("std");
const assert = std.debug.assert;

const mem = @import("mem");

const Context = @import("wayland_generator.zig").Context;

const AST = @import("ast.zig");

pub const Error = error{InterfaceNameWithoutPrefix} ||
    std.mem.Allocator.Error ||
    std.fmt.ParseIntError ||
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
        try resolveRequest(context, protocol, interface, message, core, tmp.arena);
        if (message.is_destructor) {
            assert(!interface.has_destructor);
            interface.has_destructor = true;
        }
    }

    for (interface.events) |*message| {
        try resolveEvent(context, protocol, interface, message, core, tmp.arena);
    }

    for (interface.enums) |*@"enum"| {
        try resolveEnum(context, protocol, interface, @"enum", core, tmp.arena);
    }
}

fn resolveRequest(context: *const Context, protocol: *const AST.Protocol, interface: *const AST.Interface, request: *AST.Message, core: bool, tmp: *mem.Arena) Error!void {
    try resolveMessage(context, protocol, interface, request, core, tmp);

    var return_type: ?[]const u8 = null;
    var is_anonymous_constructor = false;

    if (!request.is_destructor) {
        for (request.args) |*arg| {
            if (arg.type.tag == .new_id) {
                if (arg.interface_name) |return_type_interface| {
                    return_type = try toZigTypeName(context, tmp, return_type_interface, true);
                } else {
                    is_anonymous_constructor = true;
                }
                break;
            }
        }
    }

    request.zig_constructor_interface = return_type;
    request.is_anonymous_constructor = is_anonymous_constructor;
}

fn resolveEvent(context: *const Context, protocol: *const AST.Protocol, interface: *const AST.Interface, event: *AST.Message, core: bool, tmp: *mem.Arena) Error!void {
    try resolveMessage(context, protocol, interface, event, core, tmp);
}

fn resolveMessage(context: *const Context, protocol: *const AST.Protocol, interface: *const AST.Interface, message: *AST.Message, core: bool, tmp: *mem.Arena) Error!void {
    message.zig_name = try toZigFunctionName(context, tmp, message.name);

    for (message.args) |*arg| {
        try resolveArg(context, protocol, interface, message, arg, core, tmp);

        if (arg.type.tag == .fd) {
            message.fd_count += 1;
        }
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

    if (@"enum".is_bitfield) {
        @"enum".zig_int_type = "u32";

        var single_bit_entries: std.ArrayList(AST.Enum.BitfieldEntry) = .{ .items = &.{}, .capacity = 0 };
        var multi_bit_entries: std.ArrayList(AST.Enum.BitfieldEntry) = .{ .items = &.{}, .capacity = 0 };

        for (@"enum".entries, 0..) |*e, i| {
            const int_val: u32 = try resolveEnumValue(e.value);

            if (int_val > 0 and ((int_val & (int_val - 1)) == 0)) {
                try single_bit_entries.append(context.arena, .{ .n = @ctz(int_val), .name_index = @intCast(i) });
            } else {
                try multi_bit_entries.append(context.arena, .{ .n = int_val, .name_index = @intCast(i) });
            }
        }

        @"enum".single_bit_bitfield_entries = try single_bit_entries.toOwnedSlice(context.arena);
        @"enum".multi_bit_bitfield_entries = try multi_bit_entries.toOwnedSlice(context.arena);

        const lessThanFn = struct {
            pub fn f(_: void, a: AST.Enum.BitfieldEntry, b: AST.Enum.BitfieldEntry) bool {
                return a.n < b.n;
            }
        }.f;

        std.mem.sort(AST.Enum.BitfieldEntry, @"enum".single_bit_bitfield_entries, {}, lessThanFn);
    }
}

fn resolveEnumValue(value: []const u8) !u32 {
    var base: u8 = 10;
    var int_str = value;

    if (std.mem.startsWith(u8, value, "0x")) {
        base = 16;
        int_str = value[2..];
    }

    return try std.fmt.parseInt(u32, int_str, base);
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
