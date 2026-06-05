const std = @import("std");

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
            .protocol = prot,
            .core = core,
        };

        var file_writer = file.writer(context.io, &writer.write_buf);
        writer.file_writer = &file_writer.interface;

        try writer.emitProtocol();

        try file_writer.flush();
    } else |e| return e;
}

const Writer = struct {
    protocol: *const AST.Protocol,
    core: bool,

    file_writer: *std.Io.Writer = undefined,

    write_buf: [4096]u8 = undefined,

    pub fn emitProtocol(this: *const Writer) Error!void {
        try this.append(
            \\const std = @import("std");
            \\
            \\const common = @import("common.zig");
            \\const Object = common.Object;
            \\const RegisteredListener = common.RegisteredListener;
            \\const Interface = common.Interface;
            \\
            \\
        );

        if (this.core) {
            try this.append(
                \\const linux = @import("linux");
                \\
            );
        }

        for (this.protocol.interfaces, 0..) |*interface, interface_idx| {
            try this.emitInterface(interface);
            if (interface_idx < this.protocol.interfaces.len - 1) {
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

        try this.append("};\n");
    }

    fn emitStaticInterfaceData(this: *const Writer, interface: *const AST.Interface) Error!void {
        _ = interface;
        try this.appendi(1, "\npub const interface: Interface = .{};\n");
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
};
