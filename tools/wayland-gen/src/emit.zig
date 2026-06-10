const std = @import("std");
const assert = std.debug.assert;

const mem = @import("mem");

const AST = @import("ast.zig");

const generator = @import("wayland_generator.zig");

pub const Error = error{} ||
    std.mem.Allocator.Error ||
    std.Io.File.OpenError ||
    std.Io.File.Writer.Error ||
    std.Io.Writer.Error;

pub fn emitProtocol(context: *const generator.Context, dir: std.Io.Dir, prot: *const AST.Protocol, core: bool) Error!void {
    const file_name = try std.fmt.allocPrint(context.arena, "{s}.zig", .{prot.name});
    if (dir.createFile(context.io, file_name, .{ .truncate = true })) |file| {
        defer file.close(context.io);

        var writer: Writer = .{
            .context = context,
            .protocol = prot,
            .core = core,
        };

        var file_writer = file.writer(context.io, &writer.write_buf);
        writer.file_writer = &file_writer.interface;

        try writer.emitProtocol();

        try file_writer.flush();
    } else |e| return e;
}

pub fn emitTrampolines(context: *const generator.Context, dir: std.Io.Dir, sub_path: []const u8) Error!void {
    if (dir.createFile(context.io, sub_path, .{ .truncate = true })) |file| {
        defer file.close(context.io);

        var writer: Writer = .{
            .context = context,
            .protocol = undefined,
            .core = undefined,
        };

        var file_writer = file.writer(context.io, &writer.write_buf);
        writer.file_writer = &file_writer.interface;

        try writer.append(
            \\const std = @import("std");
            \\const assert = std.debug.assert;
            \\
            \\const linux = @import("linux");
            \\
            \\const client = @import("client.zig");
            \\const Display = client.Display;
            \\const Message = client.Message;
            \\const Object = client.Object;
            \\const Fixed = client.Fixed;
            \\const RegisteredListener = client.RegisteredListener;
            \\
            \\pub inline fn dispatch(display: *Display, message: *const Message, object: *Object) void {
            \\    const event = &object.interface.events[message.header.op];
            \\
            \\    const first_listener_node = object.listeners.first;
            \\
            \\    _ = switch (event.signature) {
            \\
        );

        var tmp_arena = std.heap.ArenaAllocator.init(context.arena);
        defer tmp_arena.deinit();
        const tmp = tmp_arena.allocator();

        var sig_it = context.signatures.iterator();
        while (sig_it.next()) |entry| {
            const trampoline_name_raw = try std.mem.concat(tmp, u8, &.{ "trampoline_", entry.key_ptr.* });
            try writer.appendif(2, ".{f} => {f}(display, object, first_listener_node, message", .{
                std.zig.fmtId(entry.key_ptr.*),
                std.zig.fmtId(trampoline_name_raw),
            });
            try writer.append("),\n");
        }

        try writer.append(
            \\    };
            \\
            \\    if (event.is_destructor) client.markZombieObject(object);
            \\}
            \\
        );

        sig_it = context.signatures.iterator();
        while (sig_it.next()) |entry| {
            const sig = entry.key_ptr.*;
            const types = entry.value_ptr.*;

            const trampoline_name_raw = try std.mem.concat(tmp, u8, &.{ "trampoline_", sig });

            try writer.appendf("\ninline fn {f}(display: *Display, object: *Object, first_listener_node: ?*const std.SinglyLinkedList.Node, message: *const Message) u32 {{\n", .{std.zig.fmtId(trampoline_name_raw)});
            try writer.appendi(1, "_ = .{display};\n");
            try writer.appendi(1, "const HandlerType = *const fn (?*anyopaque, *Object");

            var regular_arg_count: usize = 0;
            var fd_arg_count: usize = 0;
            var newid_arg_count: usize = 0;

            for (types) |t| {
                try writer.appendf(", {s}{s}", .{
                    if (t.allow_null) "?" else "",
                    basicTypeString(t.tag),
                });

                switch (t.tag) {
                    .n => newid_arg_count += 1,
                    .h => fd_arg_count += 1,
                    else => regular_arg_count += 1,
                }
            }
            try writer.append(") void;\n\n");

            if (fd_arg_count + newid_arg_count == 0) {
                try writer.appendi(1, "if (object.zombie or first_listener_node == null) return 0;\n\n");
            }

            if (regular_arg_count + newid_arg_count > 0) try writer.appendi(1, "var arg_offset: usize = 0;\n\n");

            var object_index: u32 = 0;

            for (types, 1..) |t, n| {
                switch (t.tag) {
                    .i => try writer.appendif(1, "const arg{} = message.getIntArg(&arg_offset)", .{n}),
                    .u => try writer.appendif(1, "const arg{} = message.getUIntArg(&arg_offset)", .{n}),
                    .f => try writer.appendif(1, "const arg{} = message.getFixedArg(&arg_offset)", .{n}),
                    .s => try writer.appendif(1, "const arg{} = message.getStringArg(&arg_offset)", .{n}),
                    .a => try writer.appendif(1, "const arg{} = message.getArrayArg(&arg_offset)", .{n}),
                    .o => {
                        object_index += 1;
                        try writer.appendif(1, "const arg{} = message.getObjectArg(&arg_offset, display)", .{n});
                    },
                    .n => {
                        try writer.appendif(1, "const arg{}_interface = object.interface.events[message.header.op].object_types[{}];\n", .{ n, object_index });
                        object_index += 1;
                        try writer.appendif(1, "const arg{} = message.getNewIdArg(&arg_offset, display, arg{}_interface, object.version)", .{ n, n });
                    },
                    .h => try writer.appendif(1, "const arg{} = message.getFDArg(display)", .{n}),
                }
                try writer.append(";\n");
            }

            if (fd_arg_count + newid_arg_count != 0) {
                try writer.appendi(1, "\nif (object.zombie or first_listener_node == null) {\n");
                for (types, 1..) |t, i| {
                    if (t.tag == .h) try writer.appendif(2, "linux.close(arg{}) catch @panic(\"unhandled fd close failed\");\n", .{i});
                }
                try writer.appendi(1,
                    \\    return 0;
                    \\}
                    \\
                );
            }

            try writer.appendi(1,
                \\
                \\var listener_count: u32 = 0;
                \\var cnode = first_listener_node;
                \\
                \\while (cnode) |node| {
                \\    const next = node.next;
                \\    const listener: *const RegisteredListener = @fieldParentPtr("node", node);
                \\    assert(message.header.op < listener.implementation.len);
                \\    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);
                \\
                \\    listener_count += 1;
                \\    handler(listener.user_data, @ptrCast(object)
            );

            for (types, 1..) |t, n| {
                if (!t.allow_null) {
                    switch (t.tag) {
                        .o => try writer.appendf(", arg{}.?", .{n}),
                        else => try writer.appendf(", arg{}", .{n}),
                    }
                } else {
                    try writer.appendf(", arg{}", .{n});
                }
            }

            try writer.append(");\n");
            try writer.appendi(1,
                \\    cnode = next;
                \\}
                \\
                \\return listener_count;
                \\
            );
            try writer.append("}\n");
        }

        try writer.append("\npub const Signature = enum {\n");

        sig_it = context.signatures.iterator();
        while (sig_it.next()) |entry| {
            try writer.appendif(1, "{f},\n", .{std.zig.fmtId(entry.key_ptr.*)});
        }
        try writer.append("};\n");

        try file_writer.flush();
    } else |e| return e;
}

const Writer = struct {
    context: *const generator.Context,
    protocol: *const AST.Protocol,
    core: bool,

    file_writer: *std.Io.Writer = undefined,

    write_buf: [4096]u8 = undefined,

    pub fn emitProtocol(this: *const Writer) Error!void {
        try this.append(
            \\const std = @import("std");
            \\
            \\const client = @import("client.zig");
            \\pub const Object = client.Object;
            \\pub const RegisteredListener = client.RegisteredListener;
            \\pub const Interface = client.Interface;
            \\pub const Fixed = client.Fixed;
            \\
            \\const trampolines = @import("trampolines.zig");
            \\const Signature = trampolines.Signature;
            \\
        );

        if (this.core) {
            try this.append(
                \\const linux = @import("linux");
                \\
                \\
            );
        } else {
            var it = this.protocol.protocol_imports.iterator();
            while (it.next()) |entry| {
                const name = entry.key_ptr.*;
                try this.appendf("const {s} = @import(\"{s}.zig\");\n", .{ name, name });
            }
            try this.append("\n");
        }

        var interface_it = this.protocol.interfaces.iterator();
        var interface_idx: usize = 0;
        while (interface_it.next()) |entry| : (interface_idx += 1) {
            try this.emitInterface(entry.value_ptr);
            if (interface_idx < this.protocol.interfaces.count() - 1) {
                try this.append("\n");
            }
        }
    }

    fn emitInterface(this: *const Writer, interface: *const AST.Interface) Error!void {
        try this.appendf("pub const {s} = struct {{\n", .{interface.zig_name});

        try this.appendi(1, "object: Object,\n");

        if (this.core and std.mem.eql(u8, "Display", interface.zig_name)) {
            try this.appendi(1,
                \\
                \\fd: linux.fd_t,
                \\
                \\objects: [64]Object = undefined,
                \\free_objects: std.SinglyLinkedList = .{},
                \\
                \\server_objects: [16]Object = undefined,
                \\
                \\listeners: [32]RegisteredListener = std.mem.zeroes([32]RegisteredListener),
                \\free_listeners: std.SinglyLinkedList = .{},
                \\
                \\send_payload_used: usize = 0,
                \\send_payload_buf: [2048]u8 = undefined,
                \\send_fds_used: usize = 0,
                \\send_fds_buf: [32]linux.fd_t = undefined,
                \\
                \\receive_payload_used: usize = 0,
                \\receive_payload_buf: [4096]u8 = undefined,
                \\receive_fds_used: usize = 0,
                \\receive_fds_buf: [32]linux.fd_t = undefined,
                \\fd_dispatch_index: usize = 0,
                \\
            );
        }

        try this.emitStaticInterfaceData(interface);

        if (this.core and std.mem.eql(u8, interface.name, "wl_registry")) {
            try this.appendi(1,
                \\
                \\pub inline fn bindTyped(this: *Registry, comptime InterfaceType: type, name: u32, version: u32) *InterfaceType {
                \\    return @ptrCast(this.bind(name, &InterfaceType.interface, @min(version, InterfaceType.interface.version)));
                \\}
                \\
            );
        }

        if (interface.requests.len > 0) {
            try this.append("\n");
            for (interface.requests, 0..) |*request, i| {
                if (i > 0) try this.append("\n");
                try this.emitRequest(interface, request, @intCast(i));
            }
        }

        if (!interface.has_destructor) {
            try this.appendif(1,
                \\
                \\pub inline fn destroy(self: *{s}) void {{
                \\    client.markZombieObject(&self.object);
                \\    client.destroyClientObject(&self.object);
                \\}}
                \\
            , .{interface.zig_name});
        }

        if (interface.events.len > 0) {
            try this.emitInterfaceListener(interface);
        }

        var enum_it = interface.enums.iterator();
        while (enum_it.next()) |entry| {
            const e = entry.value_ptr;
            if (e.is_bitfield)
                try this.emitBitfield(e)
            else
                try this.emitEnum(e);
        }

        try this.append("};\n");
    }

    fn emitStaticInterfaceData(this: *const Writer, interface: *const AST.Interface) Error!void {
        try this.appendi(1, "\npub const interface: Interface = .{\n");
        try this.appendif(2,
            \\.name = "{s}",
            \\.version = {},
            \\.requests = &.{{
        , .{
            interface.name,
            interface.version,
        });
        for (interface.requests, 0..) |*request, i| {
            if (i > 0) try this.append(",");
            try this.emitStaticMessageData(interface, request, false);
        }
        if (interface.requests.len > 0) {
            try this.append(" },\n");
        } else {
            try this.append("},\n");
        }

        try this.appendi(2, ".events = &.{");
        for (interface.events, 0..) |*event, i| {
            if (i > 0) try this.append(",");
            try this.emitStaticMessageData(interface, event, true);
        }
        if (interface.events.len > 0) {
            try this.append(" },\n");
        } else {
            try this.append("},\n");
        }

        try this.appendi(1, "};\n");
    }

    fn emitStaticMessageData(this: *const Writer, interface: *const AST.Interface, message: *const AST.Message, object_types: bool) Error!void {
        try this.append(" .{\n");
        try this.appendif(3,
            \\.name = "{s}",
            \\.signature = .{f},
            \\.fd_count = {},
            \\.object_types = &.{{
        , .{
            message.name,
            std.zig.fmtId(message.signature),
            message.fd_count,
        });

        if (object_types) {
            var obj_type_count: usize = 0;
            for (message.args) |*arg| {
                if (arg.zig_interface_name) |_| {
                    if (obj_type_count > 0) try this.append(",");
                    try this.appendf(" &{f}.interface", .{fmtArgTypeToZigType(this, arg, interface, false)});
                    obj_type_count += 1;
                }
            }
            if (obj_type_count > 0) try this.append(" ");
        }

        try this.append("},\n");
        try this.appendif(3, ".is_destructor = {s},\n", .{
            if (message.is_destructor) "true" else "false",
        });

        try this.appendi(2, "}");
    }

    fn emitRequest(this: *const Writer, interface: *const AST.Interface, request: *const AST.Message, opcode: u32) Error!void {
        try this.appendif(1, "pub fn {s}(this: *{s}", .{
            request.zig_name,
            interface.zig_name,
        });

        var constructor_interface_string: []const u8 = "null";
        var version_string: []const u8 = "this.object.version";
        var returns_value = true;

        // signature args
        for (request.args) |*arg| {
            if (arg.type.tag != .n) {
                try this.appendf(", {s}: {f}", .{ arg.zig_name, fmtArgTypeToZigType(this, arg, interface, true) });
            } else {
                if (arg.interface_name == null) {
                    assert(request.is_anonymous_constructor);
                    try this.append(", target_interface: *const Interface, version: u32");
                    constructor_interface_string = "target_interface";
                    version_string = "version";
                } else {
                    constructor_interface_string = arg.zig_interface_name.?;
                    assert(std.mem.eql(u8, constructor_interface_string, request.zig_constructor_interface.?));
                }
            }
        }

        try this.append(") ");

        if (request.zig_constructor_interface) |constructor_interface_name| {
            assert(std.mem.eql(u8, constructor_interface_name, constructor_interface_string));
            try this.appendf("*{s}", .{constructor_interface_name});
        } else if (request.is_anonymous_constructor) {
            try this.append("*Object");
        } else {
            try this.append("void");
            returns_value = false;
        }

        try this.append(" {\n");

        try this.appendif(
            2,
            "{s} = client.proxyMarshalArrayFlags(@ptrCast(this), {}, {s}{s}{s}, {s}, &.{{\n",
            .{
                if (returns_value) "const result" else "_",
                opcode,
                if (request.zig_constructor_interface != null) "&" else "",
                constructor_interface_string,
                if (request.zig_constructor_interface != null) ".interface" else "",
                version_string,
            },
        );

        for (request.args) |*arg| {
            var emit_close = true;

            if (arg.type.tag == .n and request.is_anonymous_constructor) {
                emit_close = false;
            } else {
                try this.appendif(3, ".{{ .{s}{s}{s} = ", .{
                    if (arg.type.allow_null) "@\"?" else "",
                    @tagName(arg.type.tag),
                    if (arg.type.allow_null) "\"" else "",
                });
            }

            switch (arg.type.tag) {
                .n => {
                    if (request.is_anonymous_constructor) {
                        try this.appendi(3,
                            \\.{ .s = target_interface.name },
                            \\.{ .u = version },
                            \\.{ .n = 0 },
                            \\
                        );
                    } else {
                        try this.append("0");
                    }
                },
                .o => try this.appendf("@ptrCast({s})", .{arg.zig_name}),
                .i, .u => {
                    if (arg.enum_type) |enum_type| {
                        if (enum_type.is_bitfield) {
                            try this.appendf("@bitCast({s})", .{arg.zig_name});
                        } else {
                            try this.appendf("@intFromEnum({s})", .{arg.zig_name});
                        }
                    } else {
                        try this.appendf("{s}", .{arg.zig_name});
                    }
                },
                else => {
                    try this.appendf("{s}", .{arg.zig_name});
                },
            }

            if (emit_close) try this.append(" },\n");
        }

        try this.appendi(2, "});\n");

        if (request.is_destructor) {
            try this.appendi(2, "client.markZombieObject(&this.object);\n");
        }

        if (returns_value) {
            try this.appendi(2, "return @ptrCast(result.?);\n");
        }

        try this.appendi(1, "}\n");
    }

    fn emitInterfaceListener(this: *const Writer, interface: *const AST.Interface) Error!void {
        assert(interface.events.len > 0);

        try this.appendi(1, "\npub const Listener = extern struct {\n");
        for (interface.events) |event| {
            try this.appendif(2, "{s}: ?*const fn (data: ?*anyopaque, {f}: *{s}", .{
                event.zig_name,
                fmtTypeNameToVarName(interface.zig_name),
                interface.zig_name,
            });

            for (event.args) |arg| {
                try this.appendf(", {s}: {f}", .{
                    arg.zig_name,
                    fmtArgTypeToZigType(this, &arg, interface, true),
                });
            }

            try this.append(") void,\n");
        }
        try this.appendi(1, "};\n\n");

        try this.appendif(1,
            \\pub inline fn addListener(this: *{s}, listener: *const Listener, data: ?*anyopaque) void {{
            \\    client.proxyAddListener(@ptrCast(this), @ptrCast(listener), data);
            \\}}
            \\
        , .{interface.zig_name});
    }

    fn emitBitfield(this: *const Writer, @"enum": *const AST.Enum) Error!void {
        try this.appendif(1, "\npub const {s} = packed struct(u32) {{\n", .{
            @"enum".zig_name,
        });

        var current_bit_offset: usize = 0;
        var pad_count: usize = 0;
        for (@"enum".single_bit_bitfield_entries) |e| {
            if (current_bit_offset < e.n) {
                try this.appendif(2, "_pad_{}: u{} = 0,\n", .{ pad_count, e.n - current_bit_offset });
                pad_count += 1;
                unreachable; // Verify!
            }
            try this.appendif(2, "{s}: bool = false,\n", .{@"enum".entries[e.name_index].zig_name});

            current_bit_offset = e.n + 1;
        }

        if (current_bit_offset < 32) {
            const rem = 32 - current_bit_offset;
            try this.appendif(2, "_pad_{}: u{} = 0,\n", .{ pad_count, rem });
        }

        if (@"enum".multi_bit_bitfield_entries.len > 0) {
            try this.append("\n");

            for (@"enum".multi_bit_bitfield_entries) |mbe| {
                try this.appendif(2, "pub const {s}: {s} = .{{", .{
                    @"enum".entries[mbe.name_index].zig_name,
                    @"enum".zig_name,
                });

                const bits: std.bit_set.Integer(32) = .{ .mask = mbe.n };

                var set_count: usize = 0;
                for (@"enum".single_bit_bitfield_entries) |sbe| {
                    if (bits.isSet(sbe.n)) {
                        if (set_count > 0) {
                            try this.append(",");
                        }
                        set_count += 1;
                        try this.appendf(" .{s} = true", .{@"enum".entries[sbe.name_index].zig_name});
                    }
                }
                if (set_count > 0) try this.append(" };\n") else try this.append("};\n");
            }
        }

        try this.appendi(1, "};\n");
    }

    fn emitEnum(this: *const Writer, @"enum": *const AST.Enum) Error!void {
        try this.appendif(1, "\npub const {s} = enum({s}) {{\n", .{
            @"enum".zig_name,
            @"enum".zig_int_type,
        });

        for (@"enum".entries) |*e| {
            try this.appendif(2, "{s} = {s},\n", .{ e.zig_name, e.value });
        }

        try this.appendi(1, "};\n");
    }

    inline fn append(this: *const Writer, str: []const u8) !void {
        try this.file_writer.writeAll(str);
    }

    inline fn appendf(this: *const Writer, comptime fmt: []const u8, args: anytype) !void {
        try this.file_writer.print(fmt, args);
    }

    fn appendi(this: *const Writer, indent: usize, str: []const u8) !void {
        var it = std.mem.splitScalar(u8, str, '\n');

        const first = it.first();
        if (first.len > 0) {
            for (0..indent) |_| try this.append("    ");
            try this.append(first);
        }

        while (it.next()) |line| {
            try this.append("\n");
            if (line.len > 0) {
                for (0..indent) |_| try this.append("    ");
                try this.append(line);
            }
        }
    }

    fn appendif(this: *const Writer, indent: usize, comptime fmt: []const u8, args: anytype) !void {
        var tmp = mem.getTemp();
        defer tmp.release();

        const str = try std.fmt.allocPrint(tmp.allocator(), fmt, args);
        try this.appendi(indent, str);
    }
};

pub inline fn fmtTypeNameToVarName(type_name: []const u8) FmtTypeNameToVarName {
    return .{ .type_name = type_name };
}

const FmtTypeNameToVarName = struct {
    type_name: []const u8,

    pub fn format(this: FmtTypeNameToVarName, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const first = this.type_name[0];
        if (std.ascii.isUpper(first)) {
            try writer.writeByte(std.ascii.toLower(first));
        }

        try writer.writeAll(this.type_name[1..]);
    }
};

pub inline fn fmtArgTypeToZigType(context: *const Writer, arg: *const AST.Arg, from_interface: *const AST.Interface, pointer: bool) FmtArgTypeToZigType {
    return .{
        .context = context,
        .arg = arg,
        .from_interface = from_interface,
        .pointer = pointer,
    };
}
const FmtArgTypeToZigType = struct {
    context: *const Writer,
    arg: *const AST.Arg,
    from_interface: *const AST.Interface,
    pointer: bool,

    pub fn format(this: FmtArgTypeToZigType, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const arg_type = this.arg.type;

        if (this.pointer) {
            if (arg_type.allow_null) try writer.writeByte('?');

            if (this.arg.zig_interface_name) |_| {
                try writer.writeByte('*');
            }
        }

        if (!this.context.core) {
            if (this.arg.import_name) |import_name| {
                try writer.print("{s}.", .{import_name});
            }
        }

        if (this.arg.enum_type) |enum_type| {
            if (enum_type.interface != this.from_interface) {
                try writer.print("{s}.", .{enum_type.interface.zig_name});
            }
            try writer.writeAll(enum_type.zig_name);
        } else if (this.arg.zig_interface_name) |interface_name| {
            try writer.writeAll(interface_name);
        } else {
            try writer.writeAll(basicTypeString(arg_type.tag));
        }
    }
};

inline fn basicTypeString(tag: AST.TypeTag) []const u8 {
    return switch (tag) {
        .i => "i32",
        .u => "u32",
        .f => "Fixed",
        .s => "[]const u8",
        .o => "*Object",
        .n => "*Object",
        .a => "[]u32",
        .h => "linux.fd_t",
    };
}
