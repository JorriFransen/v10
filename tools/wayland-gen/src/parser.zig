const std = @import("std");
const log = std.log.scoped(.@"wayland-gen.parser");
const xml = @import("zig_xml");
const types = @import("types.zig");
const mem = @import("mem");

const assert = std.debug.assert;

const Parser = @This();
const Allocator = std.mem.Allocator;

const Protocol = types.Protocol;
const Interface = types.Interface;
const Request = types.Request;
const Event = types.Event;
const Enum = types.Enum;
const Arg = types.Arg;
const Type = types.Type;

xml_file_path: []const u8,
xml_file_reader: std.fs.File.Reader,
xml_reader: xml.Reader.Streaming,

allocator: Allocator,

stderr_writer: std.fs.File.Writer,

current_interface_name: []const u8,

read_buf: [mem.KiB * 8]u8,
stderr_write_buf: [mem.KiB]u8,

/// Used for zig-xml and error printing
var gpa_data = std.heap.DebugAllocator(.{}).init;
const gpa = gpa_data.allocator();

pub fn deinit(this: *Parser) void {
    this.xml_reader.deinit();
    this.xml_file_reader.file.close();
}

const Description = struct {
    summary: []const u8 = "",
    text: []const u8 = "",

    pub fn free(this: *Description, allocator: Allocator) void {
        allocator.free(this.summary);
        allocator.free(this.text);
    }
};

pub fn parse(allocator: Allocator, xml_path: []const u8) !Protocol {
    var parser: Parser = .{
        .xml_file_path = xml_path,
        .xml_file_reader = undefined,
        .xml_reader = undefined,
        .allocator = allocator,
        .stderr_writer = undefined,
        .read_buf = undefined,
        .stderr_write_buf = undefined,
        .current_interface_name = undefined,
    };

    var xml_file = std.fs.cwd().openFile(xml_path, .{ .mode = .read_only }) catch |e| switch (e) {
        else => {
            log.err("Unable to open file: '{s}'", .{xml_path});
            return e;
        },
    };
    defer xml_file.close();

    parser.xml_file_reader = xml_file.reader(&parser.read_buf);
    parser.xml_reader = xml.Reader.Streaming.init(gpa, &parser.xml_file_reader.interface, .{ .namespace_aware = false, .assume_valid_utf8 = true });
    defer parser.xml_reader.deinit();

    parser.stderr_writer = std.fs.File.stderr().writer(&parser.stderr_write_buf);

    const reader = parser.getXmlReader();

    while (true) {
        const node = try parser.nextNode();

        switch (node) {
            else => {
                parser.xmlErr(reader.location(), "Unexpected xml node type '{s}'", .{@tagName(node)});
                unreachable;
            },
            .eof => break,

            .xml_declaration, .text => {}, // skip
            .element_start => {
                const name = reader.elementName();
                if (!std.mem.eql(u8, name, "protocol")) {
                    parser.xmlErr(reader.location(), "Invalid element: '{s}', expected 'protocol'", .{name});
                    return error.MalformedXml;
                }

                return try parser.parseProtocol();
            },
        }
    }

    parser.printErr("Did not find protocol definition", .{});
    return error.MalformedXml;
}

fn parseProtocol(this: *Parser) !Protocol {
    const reader = this.getXmlReader();
    const attr_count = reader.attributeCount();

    if (attr_count != 1) {
        this.xmlErr(reader.location(), "Invalid attribute count", .{});
        return error.MalformedXml;
    }

    const attr_name = reader.attributeName(0);
    if (!std.mem.eql(u8, attr_name, "name")) {
        xmlErr(this, reader.location(), "Expected 'name' attribute, got '{s}'", .{attr_name});
    }

    const protocol_name = copyString(this.allocator, try reader.attributeValue(0));
    var interfaces = std.ArrayList(Interface){};
    var description: Description = .{};

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                this.xmlErr(reader.location(), "Unexpected xml node type '{s}'", .{@tagName(node)});
                unreachable;
            },

            .eof => {
                this.xmlErr(reader.location(), "Unexpected eof", .{});
                return error.MalformedXml;
            },

            .comment, .text => {}, // skip

            .element_start => {
                const elem_name = reader.elementName();
                if (std.mem.eql(u8, elem_name, "copyright")) {
                    try skipElement(this);
                } else if (std.mem.eql(u8, elem_name, "interface")) {
                    try interfaces.append(this.allocator, try parseInterface(this));
                } else if (std.mem.eql(u8, elem_name, "description")) {
                    description = try this.parseDescription();
                } else {
                    this.xmlErr(reader.location(), "Unexpected element: '{s}'", .{elem_name});
                    return error.MalformedXml;
                }
            },

            .element_end => {
                const elem_name = reader.elementName();
                if (!std.mem.eql(u8, elem_name, "protocol")) {
                    this.xmlErr(reader.location(), "Unexpected closing element '{s}', expected: 'request'", .{elem_name});
                    return error.MalformedXml;
                }
                break;
            },
        }
    }

    return .{
        .name = protocol_name,
        .interfaces = try interfaces.toOwnedSlice(this.allocator),
        .summary = description.summary,
        .description = description.text,
    };
}

fn parseInterface(this: *Parser) !Interface {
    const reader = this.getXmlReader();

    var name_opt: ?[]const u8 = null;
    var version: u32 = 0;
    var description: Description = .{};
    var requests: std.ArrayList(Request) = .{};
    var events: std.ArrayList(Event) = .{};
    var enums: std.ArrayList(Enum) = .{};

    const attr_count = reader.attributeCount();
    if (attr_count < 1) {
        this.xmlErr(reader.location(), "Invalid attribute count", .{});
    }

    for (0..attr_count) |i| {
        const attr_name = reader.attributeName(i);
        const value = try reader.attributeValue(i);

        if (std.mem.eql(u8, attr_name, "name")) {
            name_opt = copyString(this.allocator, value);
        } else if (std.mem.eql(u8, attr_name, "version")) {
            version = try std.fmt.parseInt(u32, value, 10);
        } else {
            this.xmlErr(reader.location(), "Invalid attribute: '{s}'", .{attr_name});
            return error.MalformedXml;
        }
    }

    const name = name_opt orelse {
        this.xmlErr(reader.location(), "Missing name attirbute", .{});
        return error.MalformedXml;
    };
    this.current_interface_name = name;

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                this.xmlErr(reader.location(), "Unexpected xml node: '{s}'", .{@tagName(node)});
                unreachable;
            },
            .eof => {
                this.xmlErr(reader.location(), "Unexpected eof", .{});
                return error.MalformedXml;
            },

            .text, .comment => {}, // skip

            .element_start => {
                const elem_name = reader.elementName();

                if (std.mem.eql(u8, elem_name, "description")) {
                    description = try this.parseDescription();
                } else if (std.mem.eql(u8, elem_name, "request")) {
                    try requests.append(this.allocator, try this.parseRequest());
                } else if (std.mem.eql(u8, elem_name, "event")) {
                    if (try this.parseEvent()) |event| {
                        try events.append(this.allocator, event);
                    }
                } else if (std.mem.eql(u8, elem_name, "enum")) {
                    try enums.append(this.allocator, try this.parseEnum());
                } else {
                    this.xmlErr(reader.location(), "Unexpected element in interface: '{s}'", .{elem_name});
                    return error.MalformedXml;
                }
            },

            .element_end => {
                const elem_name = reader.elementName();
                if (!std.mem.eql(u8, elem_name, "interface")) {
                    this.xmlErr(reader.location(), "Unexpected closing element '{s}', expected: 'request'", .{elem_name});
                    return error.MalformedXml;
                }
                break;
            },
        }
    }

    return .{
        .name = name,
        .version = version,
        .summary = description.summary,
        .description = description.text,
        .requests = try requests.toOwnedSlice(this.allocator),
        .events = try events.toOwnedSlice(this.allocator),
        .enums = try enums.toOwnedSlice(this.allocator),
    };
}

fn parseRequest(this: *Parser) !Request {
    const reader = this.getXmlReader();

    var name: []const u8 = "";
    var destructor = false;
    var since: u32 = 0;
    var description = Description{};
    var args = std.ArrayList(Arg){};

    const attr_count = reader.attributeCount();
    if (attr_count < 1) {
        this.xmlErr(reader.location(), "Missing name attribute", .{});
    }

    for (0..attr_count) |i| {
        const attr_name = reader.attributeName(i);
        const value = try reader.attributeValue(i);

        if (std.mem.eql(u8, attr_name, "name")) {
            name = copyString(this.allocator, value);
        } else if (std.mem.eql(u8, attr_name, "type")) {
            destructor = std.mem.eql(u8, value, "destructor");
        } else if (std.mem.eql(u8, attr_name, "since")) {
            since = try std.fmt.parseInt(u32, value, 10);
        } else {
            this.xmlErr(reader.location(), "Invalid attribute: '{s}'", .{attr_name});
            return error.MalformedXml;
        }
    }

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                this.xmlErr(reader.location(), "Unexpected xml node type: '{s}'", .{@tagName(node)});
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
                } else if (std.mem.eql(u8, elem_name, "arg")) {
                    try args.append(this.allocator, try this.parseArg());
                } else {
                    this.xmlErr(reader.location(), "Unexpected element in request: '{s}'", .{elem_name});
                    return error.MalformedXml;
                }
            },

            .element_end => {
                const elem_name = reader.elementName();
                if (!std.mem.eql(u8, elem_name, "request")) {
                    this.xmlErr(reader.location(), "Unexpected closing element '{s}', expected: 'request'", .{elem_name});
                    return error.MalformedXml;
                }
                break;
            },
        }
    }

    return .{
        .name = name,
        .destructor = destructor,
        .since = since,
        .summary = description.summary,
        .description = description.text,
        .args = try args.toOwnedSlice(this.allocator),
    };
}

fn parseEvent(this: *Parser) !?Event {
    const reader = this.getXmlReader();

    var name: []const u8 = "";
    var destructor = false;
    var since: u32 = 0;
    var deprecated = false;
    var description = Description{};
    var args = std.ArrayList(Arg){};

    const attr_count = reader.attributeCount();
    if (attr_count < 1) {
        this.xmlErr(reader.location(), "Missing name attribute", .{});
    }

    for (0..attr_count) |i| {
        const attr_name = reader.attributeName(i);
        const value = try reader.attributeValue(i);

        if (std.mem.eql(u8, attr_name, "name")) {
            name = copyString(this.allocator, value);
        } else if (std.mem.eql(u8, attr_name, "type")) {
            if (std.mem.eql(u8, value, "destructor")) {
                destructor = true;
            } else {
                this.xmlErr(reader.location(), "Invalid enum type attribute '{s}'", .{value});
                return error.MalformedXml;
            }
        } else if (std.mem.eql(u8, attr_name, "since")) {
            since = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, attr_name, "deprecated-since")) {
            deprecated = true;
        } else {
            this.xmlErr(reader.location(), "Invalid attribute: '{s}'", .{attr_name});
            return error.MalformedXml;
        }
    }

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                this.xmlErr(reader.location(), "Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },
            .eof => {
                this.xmlErr(reader.location(), "Unexpected eof", .{});
                return error.MalformedXml;
            },

            .text, .comment => {}, // skip

            .element_start => {
                const elem_name = reader.elementName();

                if (std.mem.eql(u8, elem_name, "description")) {
                    description = try this.parseDescription();
                } else if (std.mem.eql(u8, elem_name, "arg")) {
                    try args.append(this.allocator, try this.parseArg());
                } else {
                    this.xmlErr(reader.location(), "Unexpected element in request: '{s}'", .{elem_name});
                    return error.MalformedXml;
                }
            },

            .element_end => {
                const elem_name = reader.elementName();
                if (!std.mem.eql(u8, elem_name, "event")) {
                    this.xmlErr(reader.location(), "Unexpected closing element '{s}', expected: 'event'", .{elem_name});
                    return error.MalformedXml;
                }
                break;
            },
        }
    }

    if (deprecated) {
        this.allocator.free(name);
        description.free(this.allocator);
        args.deinit(this.allocator);
        return null;
    } else {
        return .{
            .name = name,
            .destructor = destructor,
            .since = since,
            .summary = description.summary,
            .description = description.text,
            .args = try args.toOwnedSlice(this.allocator),
        };
    }
}

fn parseEnum(this: *Parser) !Enum {
    const reader = this.getXmlReader();

    var name: []const u8 = "";
    var bitfield = false;
    var since: u32 = 0;
    var description = Description{};
    var entries = std.ArrayList(Enum.Entry){};

    const attr_count = reader.attributeCount();
    if (attr_count < 1) {
        this.xmlErr(reader.location(), "Missing name attribute", .{});
    }

    for (0..attr_count) |i| {
        const attr_name = reader.attributeName(i);
        const value = try reader.attributeValue(i);

        if (std.mem.eql(u8, attr_name, "name")) {
            name = copyString(this.allocator, value);
        } else if (std.mem.eql(u8, attr_name, "bitfield")) {
            bitfield = std.mem.eql(u8, value, "true");
        } else if (std.mem.eql(u8, attr_name, "since")) {
            since = try std.fmt.parseInt(u32, value, 10);
        } else {
            this.xmlErr(reader.location(), "Invalid attribute: '{s}'", .{attr_name});
            return error.MalformedXml;
        }
    }

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                this.xmlErr(reader.location(), "Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },
            .eof => {
                this.xmlErr(reader.location(), "Unexpected eof", .{});
                return error.MalformedXml;
            },
            .text, .comment => {}, // skip

            .element_start => {
                const elem_name = reader.elementName();

                if (std.mem.eql(u8, elem_name, "description")) {
                    description = try this.parseDescription();
                } else if (std.mem.eql(u8, elem_name, "entry")) {
                    try entries.append(this.allocator, try this.parseEnumEntry());
                } else {
                    this.xmlErr(reader.location(), "Unexpected element in request: '{s}'", .{elem_name});
                    return error.MalformedXml;
                }
            },

            .element_end => {
                const elem_name = reader.elementName();
                if (!std.mem.eql(u8, elem_name, "enum")) {
                    this.xmlErr(reader.location(), "Unexpected closing element '{s}', expected: 'enum'", .{elem_name});
                    return error.MalformedXml;
                }
                break;
            },
        }
    }

    return .{
        .name = name,
        .bitfield = bitfield,
        .since = since,
        .summary = description.summary,
        .description = description.text,
        .entries = try entries.toOwnedSlice(this.allocator),
        .resolved_type = null,
    };
}

fn parseArg(this: *Parser) !Arg {
    const reader = this.getXmlReader();

    var name: ?[]const u8 = "";
    var arg_type: ?Type = null;
    var allow_null = false;
    var interface: ?[]const u8 = null;
    var enum_name_opt: ?[]const u8 = null;
    var summary: []const u8 = "";

    const attr_count = reader.attributeCount();
    if (attr_count < 2) {
        this.xmlErr(reader.location(), "Invalid attribute count", .{});
    }

    for (0..attr_count) |i| {
        const attr_name = reader.attributeName(i);
        const value = try reader.attributeValue(i);

        if (std.mem.eql(u8, attr_name, "name")) {
            name = copyString(this.allocator, value);
        } else if (std.mem.eql(u8, attr_name, "type")) {
            arg_type = std.meta.stringToEnum(Type, value) orelse {
                this.xmlErr(reader.location(), "Invalid type '{s}'", .{value});
                return error.MalformedXml;
            };
        } else if (std.mem.eql(u8, attr_name, "allow-null")) {
            allow_null = std.mem.eql(u8, value, "true");
        } else if (std.mem.eql(u8, attr_name, "interface")) {
            interface = copyString(this.allocator, value);
        } else if (std.mem.eql(u8, attr_name, "enum")) {
            enum_name_opt = copyString(this.allocator, value);
        } else if (std.mem.eql(u8, attr_name, "summary")) {
            summary = copyString(this.allocator, value);
        } else {
            this.xmlErr(reader.location(), "Invalid attribute: '{s}'", .{attr_name});
            return error.MalformedXml;
        }
    }

    if (name == null) {
        this.xmlErr(reader.location(), "Missing name attribute", .{});
        return error.MalformedXml;
    }

    if (arg_type == null) {
        this.xmlErr(reader.location(), "Missing type attribute", .{});
        return error.MalformedXml;
    }

    const end_node = try this.nextNode();
    const end_name = reader.elementName();
    if (end_node != .element_end or !std.mem.eql(u8, end_name, "arg")) {
        this.xmlErr(reader.location(), "Unexpected closing element '{s}', expected 'arg'", .{end_name});
    }

    return .{
        .name = name.?,
        .type = arg_type.?,
        .enum_name = enum_name_opt,
        .allow_null = allow_null,
        .interface = interface,
        .summary = summary,
    };
}

fn parseEnumEntry(this: *Parser) !Enum.Entry {
    const reader = this.getXmlReader();

    var name: ?[]const u8 = "";
    var since: u32 = 0;
    var value_str: ?[]const u8 = null;
    var summary: []const u8 = "";
    var description: []const u8 = "";

    const attr_count = reader.attributeCount();
    if (attr_count < 2) {
        this.xmlErr(reader.location(), "Invalid attribute count", .{});
    }

    for (0..attr_count) |i| {
        const attr_name = reader.attributeName(i);
        const value = try reader.attributeValue(i);

        if (std.mem.eql(u8, attr_name, "name")) {
            name = copyString(this.allocator, value);
            value_str = copyString(this.allocator, value);
        } else if (std.mem.eql(u8, attr_name, "since")) {
            since = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, attr_name, "value")) {
            value_str = copyString(this.allocator, value);
        } else if (std.mem.eql(u8, attr_name, "summary")) {
            summary = copyString(this.allocator, value);
        } else {
            this.xmlErr(reader.location(), "Invalid attribute: '{s}'", .{attr_name});
            return error.MalformedXml;
        }
    }

    if (name == null) {
        this.xmlErr(reader.location(), "Missing name attribute", .{});
        return error.MalformedXml;
    }

    if (value_str == null) {
        this.xmlErr(reader.location(), "Missing value attribute", .{});
        return error.MalformedXml;
    }

    var node = try this.nextNode();
    if (node == .element_start and std.mem.eql(u8, reader.elementName(), "description")) {
        const desc = try this.parseDescription();
        if (summary.len > 0) {
            assert(std.mem.eql(u8, summary, desc.summary));
        } else {
            summary = desc.summary;
        }
        description = desc.text;
        node = try this.nextNode();
    }

    const end_name = reader.elementName();
    if (node != .element_end or !std.mem.eql(u8, end_name, "entry")) {
        this.xmlErr(reader.location(), "Unexpected closing element '{s}', expected 'entry'", .{end_name});
    }

    return .{
        .name = name.?,
        .since = since,
        .value_str = value_str.?,
        .summary = summary,
        .description = description,
    };
}

fn parseDescription(this: *Parser) !Description {
    const reader = this.getXmlReader();

    var summary: []const u8 = "";
    var text: []const u8 = "";

    const attr_count = reader.attributeCount();
    for (0..attr_count) |i| {
        const attr_name = reader.attributeName(i);
        const value = try reader.attributeValue(i);

        if (std.mem.eql(u8, attr_name, "summary")) {
            summary = copyString(this.allocator, value);
        } else {
            this.xmlErr(reader.location(), "Invalid attribute: '{s}'", .{attr_name});
            return error.MalformedXml;
        }
    }

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                this.xmlErr(reader.location(), "Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },
            .comment => {}, // skip
            .eof => {
                this.xmlErr(reader.location(), "Unexpected eof", .{});
                return error.MalformedXml;
            },

            .text => {
                text = copyString(this.allocator, try reader.text());
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
    const reader = this.getXmlReader();

    // TODO: Temp alloc
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    const start_name = copyString(tmp.allocator(), reader.elementName());

    var node = try nextNode(this);
    while (true) {
        switch (node) {
            else => {
                this.xmlErr(reader.location(), "Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },

            .eof => {
                xmlErr(this, reader.location(), "Unexpected eof", .{});
                return error.MalformedXml;
            },

            .entity_reference, .text => {}, // skip

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

fn nextNode(this: *Parser) !xml.Reader.Node {
    const reader = this.getXmlReader();

    while (true) {
        const node = reader.read() catch |e| switch (e) {
            error.MalformedXml => {
                const loc = reader.errorLocation();
                xmlErr(this, loc, "{}", .{reader.errorCode()});
                return error.MalformedXml;
            },
            else => return e,
        };

        if (node == .text and isWhite(try reader.text())) {
            // skip
        } else {
            return node;
        }
    }
}

fn isWhite(str: []const u8) bool {
    for (str) |c| if (!std.ascii.isWhitespace(c)) return false;
    return true;
}

fn getXmlReader(this: *Parser) *xml.Reader {
    return &this.xml_reader.interface;
}

fn xmlErr(this: *Parser, loc: xml.Location, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrint(gpa, fmt, args) catch @panic("OOM");

    this.printErr("{s}:{}:{}: error: {s}\n", .{ this.xml_file_path, loc.line, loc.column, msg });
}

fn printErr(this: *Parser, comptime msg: []const u8, args: anytype) void {
    const writer = &this.stderr_writer.interface;

    writer.print(msg, args) catch @panic("Write failed");
    writer.flush() catch @panic("Flush failed");
}

fn copyString(allocator: Allocator, str: []const u8) []const u8 {
    const buf = allocator.alloc(u8, str.len) catch @panic("OOM");
    @memcpy(buf, str);
    return buf;
}
