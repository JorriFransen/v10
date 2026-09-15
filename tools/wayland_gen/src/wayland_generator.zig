const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("core");
const assert = core.assert;
const mem = core.mem;

const parser = @import("parser.zig");
const AST = @import("ast.zig");
const emit = @import("emit.zig");
const resolve = @import("resolver.zig");

const OptionParser = core.cli_arg_parser.Parser(&.{
    .string("", "wayland", 'w', "Wayland xml path"),
    .stringArray(&.{}, "protocols", 'p', "Protocol xml path"),
    .string("", "out", 'o', "Output directory path"),
    .bool(false, "help", 'h', "Print this help message"),
}, .{});

pub const Context = struct {
    io: std.Io,
    arena: Allocator,
    gpa: Allocator,
    args: OptionParser.Options,

    stderr: *std.Io.Writer,
    stdout: *std.Io.Writer,

    interface_to_protocol_map: std.StringHashMapUnmanaged(*const AST.Protocol),
    signatures: std.StringArrayHashMapUnmanaged([]AST.Type),
};

var stderr_buf: [2048]u8 = undefined;
var stderr_writer: std.Io.File.Writer = undefined;

var stdout_buf: [2048]u8 = undefined;
var stdout_writer: std.Io.File.Writer = undefined;

pub fn main(init: std.process.Init) !u8 {
    mem.init();
    defer mem.deinit();

    var arena_ = try mem.Arena.init(.{ .virtual = .{} });
    const arena = arena_.allocator();

    stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buf);
    defer stderr_writer.flush() catch unreachable;

    stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    defer stdout_writer.flush() catch unreachable;

    const raw_args = try init.minimal.args.toSlice(arena);

    const option_parser = OptionParser.init(raw_args[0], .{ .err_writer = &stderr_writer.interface });
    const args = option_parser.parse(arena, raw_args[1..]) catch |e| switch (e) {
        error.OutOfMemory => return e,
        else => {
            try option_parser.usage(&stderr_writer.interface);
            return 1;
        },
    };

    if (args.help) {
        try option_parser.help(&stdout_writer.interface);
        return 0;
    }

    var context = Context{
        .io = init.io,
        .arena = arena,
        .gpa = init.gpa,
        .args = args,
        .stderr = &stderr_writer.interface,
        .stdout = &stdout_writer.interface,
        .interface_to_protocol_map = .empty,
        .signatures = .empty,
    };
    defer {
        context.interface_to_protocol_map.deinit(context.gpa);
        context.signatures.deinit(context.gpa);
    }

    run(&context) catch {
        try option_parser.usage(&stderr_writer.interface);
        return 1;
    };
    return 0;
}

fn run(context: *Context) !void {
    var args_valid = true;

    if (context.args.wayland.len == 0) {
        try context.stderr.print("Missing --wayland option\n", .{});
        args_valid = false;
    }

    if (context.args.out.len == 0) {
        try context.stderr.print("Missing --out option\n", .{});
        args_valid = false;
    }

    if (!args_valid) {
        return error.InvalidArgs;
    }

    const output_dir = std.Io.Dir.openDirAbsolute(context.io, context.args.out, .{}) catch {
        try context.stderr.print("Invalid output directory: {s}\n", .{context.args.out});
        return error.OutputDirDoesNotExist;
    };
    defer output_dir.close(context.io);

    var output_buffer: [mem.KiB * 8]u8 = undefined;

    const client_source = @embedFile("lib/client.zig");
    if (output_dir.createFile(context.io, "client.zig", .{})) |file| {
        defer file.close(context.io);
        var writer = file.writer(context.io, &output_buffer);

        try writer.interface.writeAll(client_source);
        try writer.interface.flush();
    } else |e| return e;

    var core_protocol: AST.Protocol = undefined;

    if (std.Io.Dir.openFileAbsolute(context.io, context.args.wayland, .{})) |core_xml_file| {
        if (parser.parse(context, &stderr_writer.interface, context.args.wayland)) |prot| {
            core_protocol = prot;
        } else |e| {
            core_xml_file.close(context.io);
            try context.stderr.print("Core protocol parse failed: '{s}'\n", .{context.args.wayland});
            return e;
        }
        core_xml_file.close(context.io);

        errdefer core_protocol.deinit(context.gpa);

        // This could be in the parser, if it returned a Protocol by pointer!
        // As long as Protocol is returned by value this needs to be done here,
        //  to ensure the protocol pointer is stable.
        for (core_protocol.interfaces) |*interface| {
            try context.interface_to_protocol_map.putNoClobber(context.gpa, interface.name, &core_protocol);
        }

        resolve.resolveProtocol(context, &core_protocol, true) catch |e| {
            try context.stderr.print("Core protocol resolve failed: '{s}'\n", .{context.args.wayland});
            return e;
        };

        emit.emitProtocol(context, output_dir, &core_protocol, true) catch |e| {
            try context.stderr.print("Core protocol emit failed: '{s}'\n", .{context.args.wayland});
            return e;
        };
    } else |e| return e;

    defer core_protocol.deinit(context.gpa);

    var protocols: std.ArrayList(AST.Protocol) = .empty;
    defer protocols.deinit(context.gpa);

    for (context.args.protocols) |protocol_path| {
        if (std.Io.Dir.openFileAbsolute(context.io, protocol_path, .{})) |protocol_xml_file| {
            var protocol = parser.parse(context, &stderr_writer.interface, protocol_path) catch |e| {
                protocol_xml_file.close(context.io);
                try context.stderr.print("Protocol parse failed: '{s}'\n", .{protocol_path});
                return e;
            };

            protocol_xml_file.close(context.io);

            errdefer protocol.deinit(context.gpa);
            try protocols.append(context.gpa, protocol);
        } else |e| return e;
    }

    defer for (protocols.items) |*p| p.deinit(context.gpa);

    // This could be in the parser, if it returned a Protocol by pointer!
    // As long as Protocol is returned by value this needs to be done here,
    //  to ensure the protocol pointer is stable.
    for (protocols.items) |*protocol| {
        for (protocol.interfaces) |*interface| {
            try context.interface_to_protocol_map.putNoClobber(context.gpa, interface.name, protocol);
        }
    }

    for (protocols.items) |*protocol| {
        if (resolve.resolveProtocol(context, protocol, false)) {
            if (emit.emitProtocol(context, output_dir, protocol, false)) {
                //
            } else |e| {
                try context.stderr.print("Protocol emit failed: '{s}'\n", .{protocol.xml_path});
                return e;
            }
        } else |e| {
            try context.stderr.print("Protocol resolve failed: '{s}'\n", .{protocol.xml_path});
            return e;
        }
    }

    const root_template = @embedFile("lib/root_template.zig");
    if (output_dir.createFile(context.io, "root.zig", .{})) |file| {
        defer file.close(context.io);
        var writer = file.writer(context.io, &output_buffer);

        try writer.interface.writeAll(root_template);

        // Embedfile seems to add a newline?
        assert(root_template[root_template.len - 1] == '\n');

        for (protocols.items) |*protocol| {
            try writer.interface.print("pub const {s} = @import(\"{s}.zig\");\n", .{
                protocol.name,
                protocol.name,
            });
        }

        try writer.flush();
    } else |e| return e;

    try emit.emitTrampolines(context, output_dir, "trampolines.zig");
}
