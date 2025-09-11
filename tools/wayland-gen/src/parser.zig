const std = @import("std");
const log = std.log.scoped(.@"wayland-gen.parser");
const xml = @import("xml");
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
xml_reader: xml.Reader,

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

/// xml_temp_arena is used by the xml parser.
/// It will be reset for each node, so don't use it for anyting else!
pub fn parse(allocator: Allocator, xml_temp_arena: *mem.Arena, xml_path: []const u8) !Protocol {
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
    parser.xml_reader = .init(&parser.xml_file_reader.interface, xml_path, xml_temp_arena);
    defer parser.xml_reader.deinit();

    parser.stderr_writer = std.fs.File.stderr().writer(&parser.stderr_write_buf);

    while (true) {
        const node = try parser.nextNode();

        switch (node) {
            else => {
                parser.xmlErr("Unexpected xml node type '{s}'", .{@tagName(node)});
                unreachable;
            },
            .eof => break,

            .xml_decl, .text => {}, // skip
            .tag_open => |tag| {
                if (!std.mem.eql(u8, tag.name, "protocol")) {
                    parser.xmlErr("Invalid element: '{s}', expected 'protocol'", .{tag.name});
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
    const protocol_tag = this.xml_reader.current_node.tag_open;
    if (protocol_tag.attributes.len != 1) {
        this.xmlErr("Invalid attribute count", .{});
        return error.MalformedXml;
    }

    const attr = protocol_tag.attributes[0];
    if (!std.mem.eql(u8, attr.name, "name")) {
        this.xmlErr("Expected 'name' attribute, got '{s}'", .{attr.name});
    }

    const protocol_name = copyString(this.allocator, attr.value);
    var interfaces = std.ArrayList(Interface){};
    var description: Description = .{};

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                this.xmlErr("Unexpected xml node type '{s}'", .{@tagName(node)});
                unreachable;
            },

            .eof => {
                this.xmlErr("Unexpected eof", .{});
                return error.MalformedXml;
            },

            .comment, .text => {}, // skip

            .tag_open => |tag| {
                if (std.mem.eql(u8, tag.name, "copyright")) {
                    try this.skipElement();
                } else if (std.mem.eql(u8, tag.name, "interface")) {
                    try interfaces.append(this.allocator, try this.parseInterface());
                } else if (std.mem.eql(u8, tag.name, "description")) {
                    description = try this.parseDescription();
                } else {
                    this.xmlErr("Unexpected element: '{s}'", .{tag.name});
                    return error.MalformedXml;
                }
            },

            .tag_close => |tag| {
                if (!std.mem.eql(u8, tag, "protocol")) {
                    this.xmlErr("Unexpected closing element '{s}', expected: 'request'", .{tag});
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
    var name_opt: ?[]const u8 = null;
    var version: u32 = 0;
    var description: Description = .{};
    var requests: std.ArrayList(Request) = .{};
    var events: std.ArrayList(Event) = .{};
    var enums: std.ArrayList(Enum) = .{};

    const interface_tag = this.xml_reader.current_node.tag_open;

    if (interface_tag.attributes.len < 1) {
        this.xmlErr("Invalid attribute count", .{});
    }

    for (interface_tag.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "name")) {
            name_opt = copyString(this.allocator, attr.value);
        } else if (std.mem.eql(u8, attr.name, "version")) {
            version = try std.fmt.parseInt(u32, attr.value, 10);
        } else {
            this.xmlErr("Invalid attribute: '{s}'", .{attr.name});
            return error.MalformedXml;
        }
    }

    const name = name_opt orelse {
        this.xmlErr("Missing name attirbute", .{});
        return error.MalformedXml;
    };
    this.current_interface_name = name;

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                this.xmlErr("Unexpected xml node: '{s}'", .{@tagName(node)});
                unreachable;
            },
            .eof => {
                this.xmlErr("Unexpected eof", .{});
                return error.MalformedXml;
            },

            .text, .comment => {}, // skip

            .tag_open => |tag| {
                if (std.mem.eql(u8, tag.name, "description")) {
                    description = try this.parseDescription();
                } else if (std.mem.eql(u8, tag.name, "request")) {
                    try requests.append(this.allocator, try this.parseRequest());
                } else if (std.mem.eql(u8, tag.name, "event")) {
                    if (try this.parseEvent()) |event| {
                        try events.append(this.allocator, event);
                    }
                } else if (std.mem.eql(u8, tag.name, "enum")) {
                    try enums.append(this.allocator, try this.parseEnum());
                } else {
                    this.xmlErr("Unexpected element in interface: '{s}'", .{tag.name});
                    return error.MalformedXml;
                }
            },

            .tag_close => |tag| {
                if (!std.mem.eql(u8, tag, "interface")) {
                    this.xmlErr("Unexpected closing element '{s}', expected: 'request'", .{tag});
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
    var name: []const u8 = "";
    var destructor = false;
    var since: u32 = 0;
    var description = Description{};
    var args = std.ArrayList(Arg){};

    const req_tag = this.xml_reader.current_node.tag_open;

    if (req_tag.attributes.len < 1) {
        this.xmlErr("Missing name attribute", .{});
    }

    for (req_tag.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "name")) {
            name = copyString(this.allocator, attr.value);
        } else if (std.mem.eql(u8, attr.name, "type")) {
            destructor = std.mem.eql(u8, attr.value, "destructor");
        } else if (std.mem.eql(u8, attr.name, "since")) {
            since = try std.fmt.parseInt(u32, attr.value, 10);
        } else {
            this.xmlErr("Invalid attribute: '{s}'", .{attr.name});
            return error.MalformedXml;
        }
    }

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                this.xmlErr("Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },
            .eof => {
                this.xmlErr("Unexpected eof", .{});
                return error.MalformedXml;
            },
            .text => {}, // skip

            .tag_open => |tag| {
                if (std.mem.eql(u8, tag.name, "description")) {
                    description = try this.parseDescription();
                } else if (std.mem.eql(u8, tag.name, "arg")) {
                    try args.append(this.allocator, try this.parseArg());
                } else {
                    this.xmlErr("Unexpected element in request: '{s}'", .{tag.name});
                    return error.MalformedXml;
                }
            },

            .tag_close => |tag| {
                if (!std.mem.eql(u8, tag, "request")) {
                    this.xmlErr("Unexpected closing element '{s}', expected: 'request'", .{tag});
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
    var name: []const u8 = "";
    var destructor = false;
    var since: u32 = 0;
    var deprecated = false;
    var description = Description{};
    var args = std.ArrayList(Arg){};

    const event_tag = this.xml_reader.current_node.tag_open;

    if (event_tag.attributes.len < 1) {
        this.xmlErr("Missing name attribute", .{});
    }

    for (event_tag.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "name")) {
            name = copyString(this.allocator, attr.value);
        } else if (std.mem.eql(u8, attr.name, "type")) {
            if (std.mem.eql(u8, attr.value, "destructor")) {
                destructor = true;
            } else {
                this.xmlErr("Invalid enum type attribute '{s}'", .{attr.value});
                return error.MalformedXml;
            }
        } else if (std.mem.eql(u8, attr.name, "since")) {
            since = try std.fmt.parseInt(u32, attr.value, 10);
        } else if (std.mem.eql(u8, attr.name, "deprecated-since")) {
            deprecated = true;
        } else {
            this.xmlErr("Invalid attribute: '{s}'", .{attr.name});
            return error.MalformedXml;
        }
    }

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                this.xmlErr("Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },
            .eof => {
                this.xmlErr("Unexpected eof", .{});
                return error.MalformedXml;
            },

            .text, .comment => {}, // skip

            .tag_open => |tag| {
                if (std.mem.eql(u8, tag.name, "description")) {
                    description = try this.parseDescription();
                } else if (std.mem.eql(u8, tag.name, "arg")) {
                    try args.append(this.allocator, try this.parseArg());
                } else {
                    this.xmlErr("Unexpected element in request: '{s}'", .{tag.name});
                    return error.MalformedXml;
                }
            },

            .tag_close => |tag| {
                if (!std.mem.eql(u8, tag, "event")) {
                    this.xmlErr("Unexpected closing element '{s}', expected: 'event'", .{tag});
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
    var name: []const u8 = "";
    var bitfield = false;
    var since: u32 = 0;
    var description = Description{};
    var entries = std.ArrayList(Enum.Entry){};

    const enum_tag = this.xml_reader.current_node.tag_open;

    if (enum_tag.attributes.len < 1) {
        this.xmlErr("Missing name attribute", .{});
    }

    for (enum_tag.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "name")) {
            name = copyString(this.allocator, attr.value);
        } else if (std.mem.eql(u8, attr.name, "bitfield")) {
            bitfield = std.mem.eql(u8, attr.value, "true");
        } else if (std.mem.eql(u8, attr.name, "since")) {
            since = try std.fmt.parseInt(u32, attr.value, 10);
        } else {
            this.xmlErr("Invalid attribute: '{s}'", .{attr.name});
            return error.MalformedXml;
        }
    }

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                this.xmlErr("Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },
            .eof => {
                this.xmlErr("Unexpected eof", .{});
                return error.MalformedXml;
            },
            .text, .comment => {}, // skip

            .tag_open => |tag| {
                if (std.mem.eql(u8, tag.name, "description")) {
                    description = try this.parseDescription();
                } else if (std.mem.eql(u8, tag.name, "entry")) {
                    try entries.append(this.allocator, try this.parseEnumEntry());
                } else {
                    this.xmlErr("Unexpected element in request: '{s}'", .{tag.name});
                    return error.MalformedXml;
                }
            },

            .tag_close => |tag| {
                if (!std.mem.eql(u8, tag, "enum")) {
                    this.xmlErr("Unexpected closing element '{s}', expected: 'enum'", .{tag});
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
    var name: ?[]const u8 = "";
    var arg_type: ?Type = null;
    var allow_null = false;
    var interface: ?[]const u8 = null;
    var enum_name_opt: ?[]const u8 = null;
    var summary: []const u8 = "";

    const arg_tag = this.xml_reader.current_node.tag_open;
    if (!arg_tag.self_closing) {
        this.xmlErr("Expected self closing arg tag", .{});
        return error.MalformedXml;
    }

    if (arg_tag.attributes.len < 2) {
        this.xmlErr("Invalid attribute count", .{});
    }

    for (arg_tag.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "name")) {
            name = copyString(this.allocator, attr.value);
        } else if (std.mem.eql(u8, attr.name, "type")) {
            arg_type = std.meta.stringToEnum(Type, attr.value) orelse {
                this.xmlErr("Invalid type '{s}'", .{attr.value});
                return error.MalformedXml;
            };
        } else if (std.mem.eql(u8, attr.name, "allow-null")) {
            allow_null = std.mem.eql(u8, attr.value, "true");
        } else if (std.mem.eql(u8, attr.name, "interface")) {
            interface = copyString(this.allocator, attr.value);
        } else if (std.mem.eql(u8, attr.name, "enum")) {
            enum_name_opt = copyString(this.allocator, attr.value);
        } else if (std.mem.eql(u8, attr.name, "summary")) {
            summary = copyString(this.allocator, attr.value);
        } else {
            this.xmlErr("Invalid attribute: '{s}'", .{attr.name});
            return error.MalformedXml;
        }
    }

    if (name == null) {
        this.xmlErr("Missing name attribute", .{});
        return error.MalformedXml;
    }

    if (arg_type == null) {
        this.xmlErr("Missing type attribute", .{});
        return error.MalformedXml;
    }

    const end_node = try this.nextNode();
    if (end_node != .tag_close or !std.mem.eql(u8, end_node.tag_close, "arg")) {
        this.xmlErr("Unexpected closing element '{s}', expected 'arg'", .{end_node.tag_close});
        return error.MalformedXml;
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
    var name: ?[]const u8 = "";
    var since: u32 = 0;
    var value_str: ?[]const u8 = null;
    var summary: []const u8 = "";
    var description: []const u8 = "";

    const entry_tag = this.xml_reader.current_node.tag_open;

    if (entry_tag.attributes.len < 2) {
        this.xmlErr("Invalid attribute count", .{});
    }

    for (entry_tag.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "name")) {
            name = copyString(this.allocator, attr.value);
            value_str = copyString(this.allocator, attr.value);
        } else if (std.mem.eql(u8, attr.name, "since")) {
            since = try std.fmt.parseInt(u32, attr.value, 10);
        } else if (std.mem.eql(u8, attr.name, "value")) {
            value_str = copyString(this.allocator, attr.value);
        } else if (std.mem.eql(u8, attr.name, "summary")) {
            summary = copyString(this.allocator, attr.value);
        } else {
            this.xmlErr("Invalid attribute: '{s}'", .{attr.name});
            return error.MalformedXml;
        }
    }

    if (name == null) {
        this.xmlErr("Missing name attribute", .{});
        return error.MalformedXml;
    }

    if (value_str == null) {
        this.xmlErr("Missing value attribute", .{});
        return error.MalformedXml;
    }

    var node = try this.nextNode();
    if (node == .tag_open and std.mem.eql(u8, node.tag_open.name, "description")) {
        const desc = try this.parseDescription();
        if (summary.len > 0) {
            assert(std.mem.eql(u8, summary, desc.summary));
        } else {
            summary = desc.summary;
        }
        description = desc.text;
        node = try this.nextNode();
    }

    if (node != .tag_close or !std.mem.eql(u8, node.tag_close, "entry")) {
        this.xmlErr("Unexpected closing element '{s}', expected 'entry'", .{node.tag_close});
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
    var summary: []const u8 = "";
    var text: []const u8 = "";

    const desc_tag = this.xml_reader.current_node.tag_open;

    for (desc_tag.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "summary")) {
            summary = copyString(this.allocator, attr.value);
        } else {
            this.xmlErr("Invalid attribute: '{s}'", .{attr.name});
            return error.MalformedXml;
        }
    }

    while (true) {
        const node = try this.nextNode();
        switch (node) {
            else => {
                this.xmlErr("Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },
            .comment => {}, // skip
            .eof => {
                this.xmlErr("Unexpected eof", .{});
                return error.MalformedXml;
            },

            .text => |t| {
                text = copyString(this.allocator, t);
            },

            .tag_close => |tag| {
                if (!std.mem.eql(u8, tag, "description")) {
                    this.xmlErr("Expected closing description element, got '{s}'", .{tag});
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

/// Skip the current element. Assumes the current node is tag_open.
fn skipElement(this: *Parser) !void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    const first_node = this.xml_reader.current_node.tag_open;

    const start_name = copyString(tmp.allocator(), first_node.name);

    var node = try this.nextNode();
    while (true) {
        switch (node) {
            else => {
                this.xmlErr("Unexpected xml node type: '{s}'", .{@tagName(node)});
                unreachable;
            },

            .eof => {
                this.xmlErr("Unexpected eof", .{});
                return error.MalformedXml;
            },

            // .entity_reference => {}, // skip
            .text => {}, // skip

            .tag_close => |tag| {
                const eq = std.mem.eql(u8, start_name, tag);
                if (eq) {
                    break;
                }
            },
        }

        node = try this.nextNode();
    }
}

fn nextNode(this: *Parser) !xml.Reader.Node {
    while (true) {
        const node = try this.xml_reader.next();

        if (node == .text and isWhite(node.text)) {
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

fn xmlErr(this: *Parser, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrint(gpa, fmt, args) catch @panic("OOM");

    const loc = this.xml_reader.location;
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
