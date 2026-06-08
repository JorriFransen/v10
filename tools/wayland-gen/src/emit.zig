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
            \\const wl = @import("wayland.zig");
            \\const client = @import("client.zig");
            \\
            \\pub inline fn dispatch(display: *wl.Display, message: *const client.Message, object: *wl.Object) void {
            \\    _ = display;
            \\    _ = message;
            \\    _ = object;
            \\    unreachable;
            \\}
        );

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
                \\server_object_ids: [16]u32 = undefined,
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
                \\
            );
        }

        try this.emitStaticInterfaceData(interface);

        if (interface.requests.len > 0) {
            try this.append("\n");
            for (interface.requests, 0..) |*request, i| {
                if (i > 0) try this.append("\n");
                try this.emitRequest(interface, request);
            }
        }

        if (!interface.has_destructor) {
            try this.appendif(1,
                \\
                \\pub inline fn destroy(self: *{s}) void {{
                \\    client.proxyDestroy(@ptrCast(self));
                \\}}
                \\
            , .{interface.zig_name});
        }

        if (interface.events.len > 0) {
            try this.emitInterfaceListener(interface);
        }

        for (interface.enums) |*@"enum"| {
            if (@"enum".is_bitfield)
                try this.emitBitfield(@"enum")
            else
                try this.emitEnum(@"enum");
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
            try this.append(" .{\n");
            try this.appendif(3,
                \\.name = "{s}",
                \\.fd_count = {},
                \\
            , .{
                request.name,
                request.fd_count,
            });
            try this.appendi(2, "}");
        }
        if (interface.requests.len > 0) {
            try this.append(" },\n");
        } else {
            try this.append("},\n");
        }

        try this.appendi(2, ".events = &.{");
        for (interface.events, 0..) |*event, i| {
            if (i > 0) try this.append(",");
            try this.append(" .{\n");
            try this.appendif(3,
                \\.name = "{s}",
                \\.fd_count = {},
                \\
            , .{
                event.name,
                event.fd_count,
            });
            try this.appendi(2, "}");
        }
        if (interface.events.len > 0) {
            try this.append(" },\n");
        } else {
            try this.append("},\n");
        }

        try this.appendi(1, "};\n");
    }

    fn emitRequest(this: *const Writer, interface: *const AST.Interface, request: *const AST.Message) Error!void {
        try this.appendif(1, "pub fn {s}(this: *{s}", .{
            request.zig_name,
            interface.zig_name,
        });

        for (request.args) |*arg| {
            if (arg.type.tag != .new_id) {
                try this.appendf(", {s}: {f}", .{ arg.zig_name, fmtArgTypeToZigType(this, arg, this.protocol) });
            } else if (arg.interface_name == null) {
                assert(request.is_anonymous_constructor);
                try this.append(", string_name: []const u8, version: u32");
            }
        }

        try this.append(") ");

        if (request.zig_constructor_interface) |constructor_interface_name| {
            try this.appendf("*{s}", .{constructor_interface_name});
        } else if (request.is_anonymous_constructor) {
            try this.append("*Object");
        } else {
            try this.append("void");
        }

        try this.append(" {\n");

        try this.appendi(2, "_ = this;\n");
        for (request.args) |*arg| {
            if (arg.type.tag != .new_id) {
                try this.appendif(2, "_ = {s};\n", .{arg.zig_name});
            } else if (arg.interface_name == null) {
                assert(request.is_anonymous_constructor);
                try this.appendi(2,
                    \\_ = string_name;
                    \\_ = version;
                    \\
                );
            }
        }
        try this.appendi(2, "unreachable;\n");

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
                    fmtArgTypeToZigType(this, &arg, this.protocol),
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

pub inline fn fmtArgTypeToZigType(context: *const Writer, arg: *const AST.Arg, protocol: *const AST.Protocol) FmtArgTypeToZigType {
    return .{
        .context = context,
        .arg = arg,
        .protocol = protocol,
    };
}
const FmtArgTypeToZigType = struct {
    context: *const Writer,
    arg: *const AST.Arg,

    /// Protocol in which this arguments is emitted in
    protocol: *const AST.Protocol,

    pub fn format(this: FmtArgTypeToZigType, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const arg_type = this.arg.type;

        if (arg_type.allow_null) try writer.writeByte('?');

        if (this.arg.zig_enum_name) |enum_name|
            try writer.writeAll(enum_name)
        else if (this.arg.zig_interface_name) |interface_name| {
            try writer.writeByte('*');

            if (!this.context.core) {
                if (this.arg.import_name) |import_name| {
                    try writer.print("{s}.", .{import_name});
                }
            }

            try writer.writeAll(interface_name);
        } else {
            const type_str = if (this.arg.zig_enum_name) |enum_name|
                enum_name
            else if (this.arg.zig_interface_name) |interface_name|
                interface_name
            else switch (arg_type.tag) {
                .int => "i32",
                .uint => "u32",
                .fixed => "Fixed",
                .string => "[]const u8",
                .object => "*Object",
                .new_id => "*Object",
                .array => "[]u32",
                .fd => "linux.fd_t",
            };

            try writer.writeAll(type_str);
        }
    }
};
