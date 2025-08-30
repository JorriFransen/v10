const std = @import("std");
const log = std.log.scoped(.@"wayland-gen");
const xml = @import("xml");
const mem = @import("mem");

const assert = std.debug.assert;

var gpa_data = std.heap.DebugAllocator(.{}).init;
const gpa = gpa_data.allocator();

pub fn main() !void {
    const xml_path = "/usr/share/wayland/wayland.xml";
    const interfaces = try parse(xml_path);
    _ = interfaces;
}

pub const ParseContext = struct {
    xml_path: []const u8,
    reader: *xml.Reader,

    interfaces: std.ArrayList(Interface) = .{},
};

pub const Interface = struct {
    name: []const u8,
    version: u32,
    summary: []const u8,
    description: []const u8,

    requests: []Request,
    events: []Event,
    enums: []Enum,
};

pub const Request = struct {
    name: []const u8,
    since: u32,
    summary: []const u8,
    description: []const u8,
    args: []Arg,
};

pub const Event = struct {
    name: []const u8,
    since: u32,
    summary: []const u8,
    description: []const u8,
    args: []Arg,
};

pub const Enum = struct {
    name: []const u8,
    bitfield: bool,
    since: u32,
    summary: []const u8,
    description: []const u8,
    entries: []Entry,

    pub const Entry = struct {
        name: []const u8,
    };
};

pub const Arg = struct {
    name: []const u8,
    type: Type,
    interface: ?[]const u8, // Only for "object" and "new_id"
    summary: []const u8,
};

pub const Type = enum {
    int,
    uint,
    fixed,
    string,
    object,
    new_id,
    array,
    fd,
};

fn parse(xml_path: []const u8) ![]Interface {
    const xml_file = try std.fs.openFileAbsolute(xml_path, .{ .mode = .read_only });
    defer xml_file.close();

    var read_buf: [4096]u8 = undefined;
    var file_reader = xml_file.reader(&read_buf);

    var streaming_reader = xml.Reader.Streaming.init(gpa, &file_reader.interface, .{});
    defer streaming_reader.deinit();

    const reader = &streaming_reader.interface;

    var ctx = ParseContext{ .reader = reader, .xml_path = xml_path };

    while (true) {
        const node = try nextNode(&ctx);

        switch (node) {
            else => {
                log.debug("Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },
            .eof => break,

            .xml_declaration, .text => {}, // skip
            .element_start => {
                const name = reader.elementName();
                if (!std.mem.eql(u8, name, "protocol")) {
                    xmlErr(&ctx, reader.location(), "Invalid element: '{s}', expected 'protocol'", .{name});
                    return error.MalformedXml;
                }

                try parseProtocol(&ctx);
            },
        }
    }

    return ctx.interfaces.toOwnedSlice(gpa);
}

fn parseProtocol(ctx: *const ParseContext) !void {
    const reader = ctx.reader;
    const attr_count = reader.attributeCount();

    if (attr_count != 1) {
        xmlErr(ctx, reader.location(), "Invalid attribute count", .{});
        return error.MalformedXml;
    }

    const attr_name = reader.attributeName(0);
    if (!std.mem.eql(u8, attr_name, "name")) {
        xmlErr(ctx, reader.location(), "Expected 'name' attribute, got '{s}'", .{attr_name});
    }

    const protocol_name = try reader.attributeValue(0);
    log.debug("Parsing protocol: {s}", .{protocol_name});

    while (true) {
        const node = try nextNode(ctx);
        switch (node) {
            else => {
                log.debug("Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },

            .eof => {
                xmlErr(ctx, reader.location(), "Unexpected eof", .{});
                return error.MalformedXml;
            },

            .text => {}, // skip

            .element_start => {
                const elem_name = reader.elementName();
                if (std.mem.eql(u8, elem_name, "copyright")) {
                    try skipElement(ctx);
                } else if (std.mem.eql(u8, elem_name, "interface")) {
                    log.debug("Found interface!", .{});
                    // ParseInterface();
                    unreachable;
                } else {
                    log.debug("Unhandled node: {} ({s})", .{ node, reader.elementName() });
                    unreachable;
                }
            },
        }
    }
}

/// Skip the current element. Assumes the current node is element_start.
/// Returns the next node
fn skipElement(ctx: *const ParseContext) !void {
    const reader = ctx.reader;

    // TODO: Temp alloc
    const start_name = copyString(reader.elementName());
    defer gpa.free(start_name);

    var node = try nextNode(ctx);
    while (true) {
        switch (node) {
            else => {
                log.debug("Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },

            .eof => {
                xmlErr(ctx, reader.location(), "Unexpected eof", .{});
                return error.MalformedXml;
            },

            .text => {}, // skip

            .element_end => {
                const end_name = reader.elementName();
                if (std.mem.eql(u8, start_name, end_name)) {
                    break;
                }
            },
        }

        node = try nextNode(ctx);
    }
}

fn nextNode(ctx: *const ParseContext) !xml.Reader.Node {
    const node = ctx.reader.read() catch |e| switch (e) {
        error.MalformedXml => {
            const loc = ctx.reader.errorLocation();
            xmlErr(ctx, loc, "{}", .{ctx.reader.errorCode()});
            return error.MalformedXml;
        },
        else => return e,
    };
    return node;
}

fn xmlErr(ctx: *const ParseContext, loc: xml.Location, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrint(gpa, fmt, args) catch @panic("OOM");

    log.err("{s}:{}:{}: {s}", .{ ctx.xml_path, loc.line, loc.column, msg });
}

fn copyString(str: []const u8) []const u8 {
    const buf = gpa.alloc(u8, str.len) catch @panic("OOM");
    @memcpy(buf, str);
    return buf;
}
