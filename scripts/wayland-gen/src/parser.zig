const std = @import("std");
const log = std.log.scoped(.@"wayland-gen.parser");
const xml = @import("xml");

const Parser = @This();

xml_path: []const u8,
file_reader: std.fs.File.Reader,
xml_stream_reader: xml.Reader.Streaming,
read_buf: [4096]u8,

var gpa_data = std.heap.DebugAllocator(.{}).init;
const gpa = gpa_data.allocator();

pub fn init(xml_path: []const u8) !Parser {
    var result: Parser = undefined;
    result.xml_path = xml_path;
    var xml_file = try std.fs.openFileAbsolute(xml_path, .{ .mode = .read_only });

    result.file_reader = xml_file.reader(&result.read_buf);

    result.xml_stream_reader = xml.Reader.Streaming.init(gpa, &result.file_reader.interface, .{});

    return result;
}

pub fn deinit(this: *Parser) void {
    this.xml_stream_reader.deinit();
    this.file_reader.file.close();
}

pub const Protocol = struct {
    name: []const u8,
    interfaces: []Interface,
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

const Description = struct {
    summary: []const u8 = "",
    text: []const u8 = "",
};

pub fn parse(this: *Parser) !Protocol {
    const reader = &this.xml_stream_reader.interface;

    while (true) {
        const node = try this.nextNode();

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
                    this.xmlErr(reader.location(), "Invalid element: '{s}', expected 'protocol'", .{name});
                    return error.MalformedXml;
                }

                return try this.parseProtocol();
            },
        }
    }

    log.err("Did not find protocol definition", .{});
    return error.MalformedXml;
}

fn parseProtocol(this: *Parser) !Protocol {
    const reader = &this.xml_stream_reader.interface;
    const attr_count = reader.attributeCount();

    if (attr_count != 1) {
        this.xmlErr(reader.location(), "Invalid attribute count", .{});
        return error.MalformedXml;
    }

    const attr_name = reader.attributeName(0);
    if (!std.mem.eql(u8, attr_name, "name")) {
        xmlErr(this, reader.location(), "Expected 'name' attribute, got '{s}'", .{attr_name});
    }

    const protocol_name = copyString(try reader.attributeValue(0));
    log.debug("Parsing protocol: {s}", .{protocol_name});

    var interfaces = std.ArrayList(Interface){};

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                log.debug("Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },

            .eof => {
                this.xmlErr(reader.location(), "Unexpected eof", .{});
                return error.MalformedXml;
            },

            .text => {}, // skip

            .element_start => {
                const elem_name = reader.elementName();
                if (std.mem.eql(u8, elem_name, "copyright")) {
                    try skipElement(this);
                } else if (std.mem.eql(u8, elem_name, "interface")) {
                    try interfaces.append(gpa, try parseInterface(this));
                } else {
                    this.xmlErr(reader.location(), "Unexpected element: '{s}'", .{elem_name});
                    return error.MalformedXml;
                }
            },
        }
    }

    return .{
        .name = protocol_name,
        .interfaces = interfaces.toOwnedSlice(gpa),
    };
}

fn parseInterface(this: *Parser) !Interface {
    const reader = &this.xml_stream_reader.interface;

    var name: []const u8 = undefined;
    var version: u32 = 0;
    var description: Description = .{};
    var requests: std.ArrayList(Request) = .{};
    var events: std.ArrayList(Event) = .{};
    var enums: std.ArrayList(Enum) = .{};

    const attr_count = reader.attributeCount();
    if (attr_count < 1) {
        this.xmlErr(reader.location(), "Missing name attribute", .{});
    }

    for (0..attr_count) |i| {
        const attr_name = reader.attributeName(i);
        const value = try reader.attributeValue(i);

        if (std.mem.eql(u8, attr_name, "name")) {
            name = copyString(value);
        } else if (std.mem.eql(u8, attr_name, "version")) {
            version = try std.fmt.parseInt(u32, value, 10);
        } else {
            this.xmlErr(reader.location(), "Invalid attribute: '{s}'", .{attr_name});
            return error.MalformedXml;
        }
    }

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                log.debug("Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },
            .eof => {
                this.xmlErr(reader.location(), "Unexpected eof", .{});
                return error.MalformedXml;
            },
            .text => {}, // skip

            .element_start => {
                const elem_name = reader.elementName();

                if (std.mem.eql(u8, elem_name, "description")) {
                    description = try this.parseDescription();
                } else if (std.mem.eql(u8, elem_name, "request")) {
                    try requests.append(gpa, try this.parseRequest());
                } else if (std.mem.eql(u8, elem_name, "event")) {
                    try events.append(gpa, try this.parseEvent());
                } else if (std.mem.eql(u8, elem_name, "enum")) {
                    try enums.append(gpa, try this.parseEnum());
                } else {
                    this.xmlErr(reader.location(), "Unexpected element in interface: '{s}'", .{elem_name});
                    return error.MalformedXml;
                }
            },
        }
    }

    return .{
        .name = name,
        .version = version,
        .summary = description.summary,
        .description = description.text,
        .requests = try requests.toOwnedSlice(gpa),
        .events = try events.toOwnedSlice(gpa),
        .enums = try enums.toOwnedSlice(gpa),
    };
}

fn parseRequest(this: *Parser) !Request {
    _ = this;
    unreachable;
}

fn parseEvent(this: *Parser) !Event {
    _ = this;
    unreachable;
}

fn parseEnum(this: *Parser) !Enum {
    _ = this;
    unreachable;
}

fn parseDescription(this: *Parser) !Description {
    const reader = &this.xml_stream_reader.interface;

    var summary: []const u8 = "";
    var text: []const u8 = "";

    const attr_count = reader.attributeCount();
    for (0..attr_count) |i| {
        const attr_name = reader.attributeName(i);
        const value = try reader.attributeValue(i);

        if (std.mem.eql(u8, attr_name, "summary")) {
            summary = copyString(value);
        } else {
            this.xmlErr(reader.location(), "Invalid attribute: '{s}'", .{attr_name});
            return error.MalformedXml;
        }
    }

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                log.debug("Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },
            .eof => {
                this.xmlErr(reader.location(), "Unexpected eof", .{});
                return error.MalformedXml;
            },
            .text => {
                text = copyString(try reader.text());
            },

            .element_end => {
                const name = reader.elementName();
                if (!std.mem.eql(u8, name, "description")) {
                    this.xmlErr(reader.location(), "Expected closing description element, got '{s}'", .{name});
                    return error.MalformedXml;
                }
                break;
            },
        }
    }

    return .{
        .summary = summary,
        .text = text,
    };
}

/// Skip the current element. Assumes the current node is element_start.
/// Returns the next node
fn skipElement(this: *Parser) !void {
    const reader = &this.xml_stream_reader.interface;

    // TODO: Temp alloc
    const start_name = copyString(reader.elementName());
    defer gpa.free(start_name);

    var node = try nextNode(this);
    while (true) {
        switch (node) {
            else => {
                log.debug("Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },

            .eof => {
                xmlErr(this, reader.location(), "Unexpected eof", .{});
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

        node = try nextNode(this);
    }
}

fn nextNode(parser: *Parser) !xml.Reader.Node {
    const reader = &parser.xml_stream_reader.interface;
    const node = reader.read() catch |e| switch (e) {
        error.MalformedXml => {
            const loc = reader.errorLocation();
            xmlErr(parser, loc, "{}", .{reader.errorCode()});
            return error.MalformedXml;
        },
        else => return e,
    };
    return node;
}

fn xmlErr(parser: *const Parser, loc: xml.Location, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrint(gpa, fmt, args) catch @panic("OOM");

    log.err("{s}:{}:{}: {s}", .{ parser.xml_path, loc.line, loc.column, msg });
}

fn copyString(str: []const u8) []const u8 {
    const buf = gpa.alloc(u8, str.len) catch @panic("OOM");
    @memcpy(buf, str);
    return buf;
}
