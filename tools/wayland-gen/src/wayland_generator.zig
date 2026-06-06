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

    const common_source = @embedFile("lib/common.zig");
    if (output_dir.createFile(context.io, "common.zig", .{})) |file| {
        defer file.close(context.io);
        var writer = file.writer(context.io, &output_buffer);

        try writer.interface.writeAll(common_source);
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

// const std = @import("std");
// const log = std.log.scoped(.@"wayland-gen");
// const mem = @import("mem");
// const clip = @import("clip");
// const builtin = @import("builtin");
//
// const parser = @import("parser.zig");
// const generator = @import("generator.zig");
// const types = @import("types.zig");
//
// const assert = std.debug.assert;
//
// const OptionParser = clip.OptionParser("wayland-gen", &.{
//     clip.option(@as([]const u8, ""), "wayland", 'w', "Wayland xml path"),
//     clip.arrayOption([]const u8, "protocol", 'p', "Protocol xml path"),
//     clip.option(@as([]const u8, ""), "out", 'o', "Output file path"),
//     clip.option(false, "help", 'h', "Print this help message"),
// });
//
// const use_debug_allocator = switch (builtin.mode) {
//     .Debug => true,
//     .ReleaseSafe => !builtin.link_libc, // Not ideal, but the best we have for now.
//     .ReleaseFast, .ReleaseSmall => !builtin.link_libc and builtin.single_threaded, // Also not ideal.
// };
// var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
//
// pub const IoContext = struct {
//     io: std.Io,
//     stderr_writer: *std.Io.Writer,
// };
//
// pub fn main(init: std.process.Init.Minimal) !void {
//     try mem.init();
//
//     var tmp = mem.getTemp();
//     defer tmp.release();
//
//     const gpa = if (use_debug_allocator)
//         debug_allocator.allocator()
//     else if (builtin.link_libc)
//         std.heap.c_allocator
//     else if (!builtin.single_threaded)
//         std.heap.smp_allocator
//     else
//         comptime unreachable;
//
//     defer {
//         if (use_debug_allocator) {
//             // _ = debug_allocator.detectLeaks();
//             _ = debug_allocator.deinit();
//         }
//     }
//
//     var threaded: std.Io.Threaded = .init(gpa, .{
//         .argv0 = .init(.{ .vector = init.args.vector }),
//         .environ = .{ .block = init.environ.block },
//     });
//     defer threaded.deinit();
//
//     const io = threaded.io();
//
//     var stderr_buf: [2048]u8 = undefined;
//     var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buf);
//     const stderr = &stderr_writer.interface;
//
//     var stdout_buf: [2048]u8 = undefined;
//     var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
//     const stdout = &stdout_writer.interface;
//
//     var options = try OptionParser.parse(init.args, gpa, tmp.allocator());
//     defer OptionParser.freeOptions(&options, gpa);
//
//     if (options.help) {
//         try OptionParser.usage(stdout);
//         try stdout_writer.flush();
//         std.process.exit(0);
//     }
//
//     var args_valid = true;
//     if (options.wayland.len == 0) {
//         log.err("Missing --wayland option", .{});
//         args_valid = false;
//     }
//
//     if (options.out.len == 0) {
//         log.err("Missing --out option", .{});
//         args_valid = false;
//     }
//
//     if (!args_valid) {
//         try OptionParser.usage(stderr);
//         try stderr_writer.flush();
//         std.process.exit(1);
//     }
//
//     var xml_arena = try mem.Arena.init(.{ .virtual = .{} });
//     var parse_arena = try mem.Arena.init(.{ .virtual = .{} });
//     var gen_arena = try mem.Arena.init(.{ .virtual = .{} });
//
//     const io_context: IoContext = .{
//         .io = io,
//         .stderr_writer = stderr,
//     };
//
//     var wayland_protocol = try parser.parse(&io_context, parse_arena.allocator(), &xml_arena, options.wayland);
//
//     const protocols = try parse_arena.allocator().alloc(types.Protocol, options.protocol.items.len);
//     for (options.protocol.items, protocols) |protocol_xml_file, *dst| {
//         dst.* = try parser.parse(&io_context, parse_arena.allocator(), &xml_arena, protocol_xml_file);
//     }
//
//     const result = try generator.generate(gen_arena.allocator(), &wayland_protocol, protocols);
//
//     try stderr.flush();
//     try stdout.flush();
//
//     const out_file = try std.Io.Dir.cwd().createFile(io, options.out, .{ .read = false });
//     defer out_file.close(io);
//
//     var out_buf: [mem.KiB * 8]u8 = undefined;
//     var out_writer = out_file.writer(io, &out_buf);
//     _ = try out_writer.interface.write(result);
//     try out_writer.interface.flush();
// }
