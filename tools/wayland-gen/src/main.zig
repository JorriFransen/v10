const std = @import("std");
const log = std.log.scoped(.@"wayland-gen");
const mem = @import("mem");
const clip = @import("clip");
const builtin = @import("builtin");

const parser = @import("parser.zig");
const generator = @import("generator.zig");
const types = @import("types.zig");

const assert = std.debug.assert;

const OptionParser = clip.OptionParser("wayland-gen", &.{
    clip.option(@as([]const u8, ""), "wayland", 'w', "Wayland xml path"),
    clip.arrayOption([]const u8, "protocol", 'p', "Protocol xml path"),
    clip.option(@as([]const u8, ""), "out", 'o', "Output file path"),
    clip.option(false, "help", 'h', "Print this help message"),
});

const use_debug_allocator = switch (builtin.mode) {
    .Debug => true,
    .ReleaseSafe => !builtin.link_libc, // Not ideal, but the best we have for now.
    .ReleaseFast, .ReleaseSmall => !builtin.link_libc and builtin.single_threaded, // Also not ideal.
};
var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub const IoContext = struct {
    io: std.Io,
    stderr_writer: *std.Io.Writer,
};

pub fn main(init: std.process.Init.Minimal) !void {
    try mem.init();

    var tmp = mem.getTemp();
    defer tmp.release();

    const gpa = if (use_debug_allocator)
        debug_allocator.allocator()
    else if (builtin.link_libc)
        std.heap.c_allocator
    else if (!builtin.single_threaded)
        std.heap.smp_allocator
    else
        comptime unreachable;

    defer {
        if (use_debug_allocator) {
            // _ = debug_allocator.detectLeaks();
            _ = debug_allocator.deinit();
        }
    }

    var threaded: std.Io.Threaded = .init(gpa, .{
        .argv0 = .init(.{ .vector = init.args.vector }),
        .environ = .{ .block = init.environ.block },
    });
    defer threaded.deinit();

    const io = threaded.io();

    var stderr_buf: [2048]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buf);
    const stderr = &stderr_writer.interface;

    var stdout_buf: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    var options = try OptionParser.parse(init.args, gpa, tmp.allocator());
    defer OptionParser.freeOptions(&options, gpa);

    if (options.help) {
        try OptionParser.usage(stdout);
        try stdout_writer.flush();
        std.process.exit(0);
    }

    var args_valid = true;
    if (options.wayland.len == 0) {
        log.err("Missing --wayland option", .{});
        args_valid = false;
    }

    if (options.out.len == 0) {
        log.err("Missing --out option", .{});
        args_valid = false;
    }

    if (!args_valid) {
        try OptionParser.usage(stderr);
        try stderr_writer.flush();
        std.process.exit(1);
    }

    var xml_arena = try mem.Arena.init(.{ .virtual = .{} });
    var parse_arena = try mem.Arena.init(.{ .virtual = .{} });
    var gen_arena = try mem.Arena.init(.{ .virtual = .{} });

    const io_context: IoContext = .{
        .io = io,
        .stderr_writer = stderr,
    };

    var wayland_protocol = try parser.parse(&io_context, parse_arena.allocator(), &xml_arena, options.wayland);

    const protocols = try parse_arena.allocator().alloc(types.Protocol, options.protocol.items.len);
    for (options.protocol.items, protocols) |protocol_xml_file, *dst| {
        dst.* = try parser.parse(&io_context, parse_arena.allocator(), &xml_arena, protocol_xml_file);
    }

    const result = try generator.generate(gen_arena.allocator(), &wayland_protocol, protocols);

    try stderr.flush();
    try stdout.flush();

    const out_file = try std.Io.Dir.cwd().createFile(io, options.out, .{ .read = false });
    defer out_file.close(io);

    var out_buf: [mem.KiB * 8]u8 = undefined;
    var out_writer = out_file.writer(io, &out_buf);
    _ = try out_writer.interface.write(result);
    try out_writer.interface.flush();
}
