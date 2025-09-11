const std = @import("std");
const log = std.log.scoped(.@"wayland-gen");
const mem = @import("mem");
const clip = @import("clip");

const parser = @import("parser.zig");
const generator = @import("generator.zig");
const types = @import("types.zig");

const assert = std.debug.assert;

var gpa_data = std.heap.DebugAllocator(.{}){};
const gpa = gpa_data.allocator();

const OptionParser = clip.OptionParser("wayland-gen", &.{
    clip.option(@as([]const u8, ""), "wayland", 'w', "Wayland xml path"),
    clip.arrayOption([]const u8, "protocol", 'p', "Protocol xml path"),
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
        try OptionParser.usage(std.fs.File.stderr());
        std.process.exit(1);
    }

    var parse_arena = try mem.Arena.init(.{ .virtual = .{} });
    var gen_arena = try mem.Arena.init(.{ .virtual = .{} });

    // {
    //     const xml_path = "vendor/wayland/wayland.xml";
    //     const xml_file = try std.fs.cwd().openFile(xml_path, .{});
    //     defer xml_file.close();
    //
    //     var read_buf: [512]u8 = undefined;
    //     var reader = xml_file.reader(&read_buf);
    //
    //     const Xml = @import("xml");
    //     var xml_reader = Xml.Reader.init(&reader.interface, xml_path);
    //
    //     while (!xml_reader.done()) {
    //         const node = try xml_reader.next();
    //         log.debug("node: {f}", .{node});
    //     }
    // }

    const wlp_p_st = std.time.nanoTimestamp();
    var wayland_protocol = try parser.parse(parse_arena.allocator(), options.wayland);
    const wlp_p_et = std.time.nanoTimestamp();

    const protocols = try parse_arena.allocator().alloc(types.Protocol, options.protocol.items.len);
    const ppts = try parse_arena.allocator().alloc([2]i128, options.protocol.items.len);
    for (options.protocol.items, protocols, ppts) |protocol_xml_file, *dst, *t| {
        t.*[0] = std.time.nanoTimestamp();
        dst.* = try parser.parse(parse_arena.allocator(), protocol_xml_file);
        t.*[1] = std.time.nanoTimestamp();
    }

    const result = try generator.generate(gen_arena.allocator(), &wayland_protocol, protocols);

    const out_file = try std.fs.cwd().createFile(options.out, .{ .read = false });
    defer out_file.close();

    var out_buf: [1024]u8 = undefined;
    var out_writer = out_file.writer(&out_buf);
    _ = try out_writer.interface.write(result);

    const wlp_p = wlp_p_et - wlp_p_st;
    log.info("parse: {s: <60} {: >10} ({:.5}s)", .{ options.wayland, wlp_p, sec(wlp_p) });
    var total_parse = wlp_p;
    for (options.protocol.items, ppts) |pn, pt| {
        const p = pt[1] - pt[0];
        log.info("parse: {s: <60} {: >10} ({:.5}s)", .{ pn, p, sec(p) });
        total_parse += p;
    }
    log.info("Total parse time: {s: <69} {: >10} ({:.5}s)", .{ "", total_parse, sec(total_parse) });
}

inline fn sec(ns: i128) f64 {
    return @as(f64, @floatFromInt(ns)) / std.time.ns_per_s;
}
