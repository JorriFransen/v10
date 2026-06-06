const std = @import("std");
const clip = @import("clip");
const mem = @import("mem");

const parser = @import("parser.zig");
const AST = @import("ast.zig");
const emit = @import("emit.zig");
const resolve = @import("resolver.zig");

const OptionParser = clip.OptionParser("wayland-gen", &.{
    clip.option(@as([]const u8, ""), "wayland", 'w', "Wayland xml path"),
    clip.arrayOption([]const u8, "protocol", 'p', "Protocol xml path"),
    clip.option(@as([]const u8, ""), "out", 'o', "Output directory path"),
    clip.option(false, "help", 'h', "Print this help message"),
});

pub const Context = struct {
    io: std.Io,
    arena: std.mem.Allocator,
    args: std.process.Args,

    stderr: *std.Io.Writer,
    stdout: *std.Io.Writer,
};

var stderr_buf: [2048]u8 = undefined;
var stderr_writer: std.Io.File.Writer = undefined;

var stdout_buf: [2048]u8 = undefined;
var stdout_writer: std.Io.File.Writer = undefined;

pub fn main(init: std.process.Init) !u8 {
    mem.init();
    defer mem.deinit();
    defer _ = init.arena.reset(.free_all);

    stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buf);
    defer stderr_writer.flush() catch unreachable;

    stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    defer stdout_writer.flush() catch unreachable;

    const context = Context{
        .io = init.io,
        .arena = init.arena.allocator(),
        .args = init.minimal.args,
        .stderr = &stderr_writer.interface,
        .stdout = &stdout_writer.interface,
    };

    run(context) catch |e| {
        try context.stderr.print("{}", .{e});
        return 1;
    };
    return 0;
}

fn run(context: Context) !void {
    const cli_options = try OptionParser.parse(context.args, context.arena);

    if (cli_options.help) {
        try OptionParser.usage(context.stdout);
        return;
    }

    var args_valid = true;
    if (cli_options.wayland.len == 0) {
        try context.stderr.print("Missing --wayland option", .{});
        args_valid = false;
    }

    if (cli_options.out.len == 0) {
        try context.stderr.print("Missing --out option", .{});
        args_valid = false;
    }

    if (!args_valid) {
        try OptionParser.usage(context.stderr);
        return error.InvalidArgs;
    }

    const output_dir = std.Io.Dir.openDirAbsolute(context.io, cli_options.out, .{}) catch {
        try context.stderr.print("Invalid output directory: {s}", .{cli_options.out});
        return error.OutputDirDoesNotExist;
    };
    defer output_dir.close(context.io);

    var xml_tmp_arena = try mem.Arena.init(.{ .virtual = .{} });
    var output_buffer: [mem.KiB * 8]u8 = undefined;

    const client_source = @embedFile("lib/client.zig");
    if (output_dir.createFile(context.io, "client.zig", .{})) |file| {
        defer file.close(context.io);
        var writer = file.writer(context.io, &output_buffer);

        try writer.interface.writeAll(client_source);
        try writer.interface.flush();
    } else |e| return e;

    var core_protocol: AST.Protocol = undefined;

    if (std.Io.Dir.openFileAbsolute(context.io, cli_options.wayland, .{})) |core_xml_file| {
        if (parser.parse(context, &xml_tmp_arena, &stderr_writer.interface, cli_options.wayland)) |prot| {
            core_protocol = prot;
        } else |e| {
            core_xml_file.close(context.io);
            try context.stderr.print("Core protocol parse failed: '{s}'", .{cli_options.wayland});
            return e;
        }
        core_xml_file.close(context.io);

        resolve.resolveProtocol(&context, &core_protocol, true) catch |e| {
            try context.stderr.print("Core protocol resolve failed: '{s}'", .{cli_options.wayland});
            return e;
        };

        emit.emitProtocol(&context, output_dir, &core_protocol, true) catch |e| {
            try context.stderr.print("Core protocol emit failed: '{s}'", .{cli_options.wayland});
            return e;
        };
    } else |e| return e;

    var protocols: std.ArrayList(AST.Protocol) = .{ .items = &.{}, .capacity = 0 };

    for (cli_options.protocol.items) |protocol_path| {
        if (std.Io.Dir.openFileAbsolute(context.io, protocol_path, .{})) |protocol_xml_file| {
            if (parser.parse(context, &xml_tmp_arena, &stderr_writer.interface, protocol_path)) |prot| {
                protocol_xml_file.close(context.io);

                var protocol = prot;
                if (resolve.resolveProtocol(&context, &protocol, false)) {
                    if (emit.emitProtocol(&context, output_dir, &protocol, false)) {
                        try protocols.append(context.arena, protocol);
                    } else |e| {
                        try context.stderr.print("Protocol emit failed: '{s}'", .{protocol_path});
                        return e;
                    }
                } else |e| {
                    try context.stderr.print("Protocol resolve failed: '{s}'", .{protocol_path});
                    return e;
                }
            } else |e| {
                protocol_xml_file.close(context.io);
                try context.stderr.print("Protocol parse failed: '{s}'", .{protocol_path});
                return e;
            }
        } else |e| return e;
    }

    const root_template = @embedFile("lib/root_template.zig");
    if (output_dir.createFile(context.io, "root.zig", .{})) |file| {
        defer file.close(context.io);
        var writer = file.writer(context.io, &output_buffer);

        try writer.interface.writeAll(root_template);

        // Embedfile seems to add a newline?
        std.debug.assert(root_template[root_template.len - 1] == '\n');

        for (protocols.items) |*protocol| {
            try writer.interface.print("pub const {s} = @import(\"{s}.zig\");\n", .{
                protocol.name,
                protocol.name,
            });
        }

        try writer.flush();
    } else |e| return e;
}
