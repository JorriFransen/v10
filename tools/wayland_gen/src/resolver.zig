const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const mem = @import("mem");

const Context = @import("wayland_generator.zig").Context;

const AST = @import("ast.zig");

pub const Error = error{
    InterfaceNameWithoutPrefix,
    UnresolvedInterfaceName,
    UnresolvedEnumName,
} ||
    std.mem.Allocator.Error ||
    std.fmt.ParseIntError ||
    std.Io.Writer.Error ||
    mem.TempStringBuilder.Error;

pub fn resolveProtocol(context: *Context, protocol: *AST.Protocol, core: bool) Error!void {
    var interface_it = protocol.interfaces.iterator();
    while (interface_it.next()) |entry| {
        try resolveInterface(context, protocol, entry.value_ptr, core);
    }
}

fn resolveInterface(context: *Context, protocol: *AST.Protocol, interface: *AST.Interface, core: bool) Error!void {
    interface.zig_name = try toZigTypeName(context, context.arena, interface.name, true);

    for (interface.requests) |*message| {
        try resolveRequest(context, protocol, interface, message, core);
    }

    for (interface.events) |*message| {
        try resolveEvent(context, protocol, interface, message, core);
    }

    var enum_it = interface.enums.iterator();
    while (enum_it.next()) |entry| {
        try resolveEnum(context, protocol, interface, entry.value_ptr, core);
    }
}

fn resolveRequest(context: *Context, protocol: *AST.Protocol, interface: *AST.Interface, request: *AST.Message, core: bool) Error!void {
    try resolveMessage(context, protocol, interface, request, core);

    var return_type: ?[]const u8 = null;
    var is_anonymous_constructor = false;

    if (!request.is_destructor) {
        for (request.args) |*arg| {
            if (arg.type.tag == .n) {
                if (arg.interface_name) |return_type_interface| {
                    return_type = try toZigTypeName(context, context.arena, return_type_interface, true);
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

fn resolveEvent(context: *Context, protocol: *AST.Protocol, interface: *AST.Interface, event: *AST.Message, core: bool) Error!void {
    try resolveMessage(context, protocol, interface, event, core);
}

fn resolveMessage(context: *Context, protocol: *AST.Protocol, interface: *AST.Interface, message: *AST.Message, core: bool) Error!void {
    message.zig_name = try toCamelCase(context.arena, message.name);

    var sig_sb = mem.getScratchStringBuilder(context.arena);
    defer sig_sb.deinit();

    for (message.args) |*arg| {
        try resolveArg(context, protocol, interface, message, arg, core);

        if (arg.type.tag == .h) {
            message.fd_count += 1;
        }

        if (arg.type.allow_null) try sig_sb.writeByte('?');
        const tag_str = @tagName(arg.type.tag);
        assert(tag_str.len == 1);
        try sig_sb.writeByte(tag_str[0]);
    }

    var sig = sig_sb.currentString();
    if (sig.len == 0) {
        sig = "_";
    }

    const sig_entry = try context.signatures.getOrPut(sig);
    if (sig_entry.found_existing) {
        message.signature = sig_entry.key_ptr.*;
    } else {
        const types = try context.arena.alloc(AST.Type, message.args.len);
        for (message.args, types) |arg, *t| {
            t.* = arg.type;
        }

        const new_sig = try context.arena.dupe(u8, sig);
        sig_entry.key_ptr.* = new_sig;
        sig_entry.value_ptr.* = types;

        message.signature = new_sig;
    }

    if (message.is_destructor) {
        assert(!interface.has_destructor);
        interface.has_destructor = true;
    }
}

fn resolveArg(context: *const Context, protocol: *AST.Protocol, interface: *const AST.Interface, message: *const AST.Message, arg: *AST.Arg, core: bool) Error!void {
    _ = message;

    if (arg.enum_name) |enum_name| {
        var name_in_interface = enum_name;

        const enum_interface = if (std.mem.findScalar(u8, enum_name, '.')) |dot_idx| blk: {
            assert(enum_name.len > dot_idx + 1);
            const interface_name = enum_name[0..dot_idx];
            name_in_interface = enum_name[dot_idx + 1 ..];

            const enum_protocol = context.interface_to_protocol_map.get(interface_name) orelse {
                try context.stderr.print("Unable to resolve interface_name: '{s}'\n", .{interface_name});
                return error.UnresolvedInterfaceName;
            };

            const enum_interface = enum_protocol.interfaces.getPtr(interface_name) orelse {
                try context.stderr.print("Unable to resolve interface_name: '{s}'\n", .{interface_name});
                return error.UnresolvedInterfaceName;
            };

            break :blk enum_interface;
        } else interface;

        if (enum_interface.enums.getPtr(name_in_interface)) |enum_type| {
            arg.enum_type = enum_type;
        } else {
            try context.stderr.print("Unable to resolve enum type: '{s}'\n", .{name_in_interface});
            if (enum_interface != interface) {
                try context.stderr.print("\t in interface: '{s}'\n", .{enum_interface.name});
            }
            return error.UnresolvedEnumName;
        }
    }

    if (arg.interface_name) |interface_name| {
        arg.zig_interface_name = try toZigTypeName(context, context.arena, interface_name, true);
    }

    if (!core and (arg.type.tag == .n or arg.type.tag == .o)) {
        if (arg.interface_name) |interface_name| {
            if (!protocol.interfaces.contains(interface_name)) {
                if (context.interface_to_protocol_map.get(interface_name)) |in_prot| {
                    if (protocol.protocol_imports.get(in_prot.name) == null) {
                        try protocol.protocol_imports.put(context.gpa, in_prot.name, in_prot);
                    }
                    arg.import_name = in_prot.name;
                } else {
                    try context.stderr.print("Failed to find protocol for interface: {s}\n", .{interface_name});
                }
            }
        }
    }
}

fn resolveEnum(context: *const Context, protocol: *const AST.Protocol, interface: *const AST.Interface, @"enum": *AST.Enum, core: bool) Error!void {
    _ = protocol;
    _ = core;

    @"enum".interface = interface;
    @"enum".zig_name = try toZigTypeName(context, context.arena, @"enum".name, false);

    var int_type: ?[]const u8 = null;
    for (@"enum".entries) |*e| {
        if (int_type == null and e.value[0] == '-') {
            int_type = "c_int";
        }

        e.zig_name = try toCamelCase(context.arena, e.name);
    }

    @"enum".zig_int_type = int_type orelse "c_uint";

    if (@"enum".is_bitfield) {
        @"enum".zig_int_type = "u32";

        var tmp = mem.getScratch(context.arena);
        defer tmp.release();

        var single_bit_entries: std.ArrayList(AST.Enum.BitfieldEntry) = .empty;
        var multi_bit_entries: std.ArrayList(AST.Enum.BitfieldEntry) = .empty;

        for (@"enum".entries, 0..) |*e, i| {
            const int_val: u32 = try resolveEnumValue(e.value);

            if (int_val > 0 and ((int_val & (int_val - 1)) == 0)) {
                try single_bit_entries.append(tmp.a, .{ .n = @ctz(int_val), .entry_index = @intCast(i) });
            } else {
                try multi_bit_entries.append(tmp.a, .{ .n = int_val, .entry_index = @intCast(i) });
            }
        }

        @"enum".single_bit_bitfield_entries = try context.arena.dupe(AST.Enum.BitfieldEntry, single_bit_entries.items);
        @"enum".multi_bit_bitfield_entries = try context.arena.dupe(AST.Enum.BitfieldEntry, multi_bit_entries.items);

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

fn toZigTypeName(context: *const Context, allocator: Allocator, maybe_prefix_name: []const u8, strip_prefix: bool) ![]const u8 {
    var tmp = mem.getScratch(allocator);
    defer tmp.release();

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
        const first = try toZigTypeName(context, tmp.a, name[0..dot_idx], true);
        const second = try toZigTypeName(context, tmp.a, name[dot_idx + 1 ..], false);
        return try std.mem.concat(allocator, u8, &.{ first, ".", second });
    } else {
        return try toPascalCase(allocator, name);
    }
}

/// removes '_', does not uncapitalize the first character!
fn toCamelCase(allocator: Allocator, name: []const u8) ![]const u8 {
    var sb = mem.getScratchStringBuilder(allocator);
    defer sb.deinit();

    var cap_next = false;
    for (name) |c| {
        if (c == '_') {
            cap_next = true;
            continue;
        }

        if (cap_next) {
            cap_next = false;
            try sb.writeByte(std.ascii.toUpper(c));
        } else {
            try sb.writeByte(c);
        }
    }

    const result = try mem.arenaAllocPrint(allocator, "{f}", .{std.zig.fmtId(sb.currentString())});
    return result;
}

/// removes '_'
fn toPascalCase(allocator: Allocator, name: []const u8) ![]const u8 {
    var sb = mem.getScratchStringBuilder(allocator);
    defer sb.deinit();

    if (name.len > 0) {
        try sb.writeByte(std.ascii.toUpper(name[0]));
    }

    var cap_next = false;
    for (name[1..]) |c| {
        if (c == '_') {
            cap_next = true;
            continue;
        }

        if (cap_next) {
            cap_next = false;
            try sb.writeByte(std.ascii.toUpper(c));
        } else {
            try sb.writeByte(c);
        }
    }

    const result = try mem.arenaAllocPrint(allocator, "{f}", .{std.zig.fmtId(sb.currentString())});
    return result;
}
