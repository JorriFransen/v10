const std = @import("std");
const log = std.log.scoped(.@"wayland-gen");
const mem = @import("mem");
const clip = @import("clip");

const parser = @import("parser.zig");
const generator = @import("generator.zig");

const assert = std.debug.assert;

var gpa_data = std.heap.DebugAllocator(.{}){};
const gpa = gpa_data.allocator();

const OptionParser = clip.OptionParser("wayland-gen", &.{
    clip.option(@as([]const u8, ""), "out", 'o', "Output file path"),
    clip.option(false, "help", 'h', "Print this help message"),
});

pub fn main() !void {
    try mem.init();

    var tmp = mem.getTemp();
    defer tmp.release();

    const options = try OptionParser.parse(gpa, tmp.allocator());
    if (options.help) {
        try OptionParser.usage(std.fs.File.stdout());
    }

    if (options.out.len == 0) {
        log.err("Missing --out option", .{});
        try OptionParser.usage(std.fs.File.stderr());
        std.process.exit(1);
    }

    const xml_path = "wayland.xml";

    var parse_arena = try mem.Arena.init(.{ .virtual = .{} });
    var gen_arena = try mem.Arena.init(.{ .virtual = .{} });

    var wayland_protocol = try parser.parse(parse_arena.allocator(), xml_path);

    const result = try generator.generate(gen_arena.allocator(), &wayland_protocol);
    parse_arena.reset();

    const out_file = try std.fs.cwd().createFile(options.out, .{ .read = false });
    defer out_file.close();

    var out_buf: [1024]u8 = undefined;
    var out_writer = out_file.writer(&out_buf);
    _ = try out_writer.interface.write(result);
}
