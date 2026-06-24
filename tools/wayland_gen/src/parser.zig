pub const std = @import("std");
const assert = std.debug.assert;

pub const AST = @import("ast.zig");
pub const xml = @import("xml");
pub const mem = @import("mem");

pub const Context = @import("wayland_generator.zig").Context;

pub const Error = error{} || Parser.Error;

/// xml_temp_arena is used by the xml parser.
/// It will be reset for each node, so don't use it for anything else!
pub fn parse(context: *const Context, xml_temp_arena: *mem.Arena, err_writer: *std.Io.Writer, xml_path: []const u8) Error!AST.Protocol {
    var parser: Parser = undefined;
    try parser.init(context, xml_temp_arena, err_writer, xml_path);

    var result = try parser.parse();
    parser.deinit();

    result.xml_path = xml_path;

    return result;
}

const Parser = struct {
    context: *const Context,
    xml_file_path: []const u8,
    xml_file_reader: std.Io.File.Reader,
    xml_reader: xml.Reader,
    err_writer: *std.Io.Writer,
    read_buf: [mem.KiB * 8]u8,

    pub const Error = error{} ||
        std.Io.File.OpenError ||
        xml.Reader.Error ||
        std.fmt.ParseIntError;

    pub fn init(this: *Parser, context: *const Context, xml_tmp_arena: *mem.Arena, err_writer: *std.Io.Writer, xml_path: []const u8) !void {
        if (std.Io.Dir.cwd().openFile(context.io, xml_path, .{})) |xml_file| {
            this.context = context;
            this.xml_file_path = xml_path;
            this.xml_file_reader = xml_file.reader(context.io, &this.read_buf);
            this.xml_reader = xml.Reader.init(&this.xml_file_reader.interface, xml_path, xml_tmp_arena, err_writer);
            this.err_writer = err_writer;
        } else |e| return e;
    }

    pub fn deinit(this: *Parser) void {
        this.xml_file_reader.file.close(this.context.io);
        this.xml_reader.deinit();
    }

    pub fn parse(this: *Parser) Parser.Error!AST.Protocol {
        while (true) {
            switch (try this.nextNode()) {
                else => |n| {
                    this.xmlErr("Unexpected xml node type '{s}'", .{@tagName(n)});
                    return error.MalformedXml;
                },
                .eof => break,
                .xml_decl, .text => {}, // skip
                .tag_open => |tag| {
                    if (!std.mem.eql(u8, tag.name, "protocol")) {
                        this.xmlErr("Invalid element: '{s}', expected 'protocol'", .{tag.name});
                        return error.MalformedXml;
                    }
                    return try this.parseProtocol();
                },
            }
        }
        unreachable;
    }

    fn parseProtocol(this: *Parser) Parser.Error!AST.Protocol {
        const protocol_tag = this.xml_reader.current_node.tag_open;
        if (protocol_tag.attributes.len != 1) {
            this.xmlErr("Invalid attribute count", .{});
            return error.MalformedXml;
        }

        const attr = protocol_tag.attributes[0];
        if (!std.mem.eql(u8, attr.name, "name")) {
            this.xmlErr("Expected 'name' attribute, got '{s}'", .{attr.name});
        }

        const InterfaceEntry = struct {
            name: []const u8,
            interface: AST.Interface,
        };

        const protocol_name = try this.copyString(attr.value);
        var interfaces: std.MultiArrayList(InterfaceEntry) = .empty;

        while (true) {
            const node = try this.nextNode();
            switch (node) {
                else => {
                    this.xmlErr("Unexpected xml node type '{s}'", .{@tagName(node)});
                    return error.MalformedXml;
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
                        const interface = try this.parseInterface();
                        try interfaces.append(this.context.arena, .{
                            .interface = interface,
                            .name = interface.name,
                        });
                    } else if (std.mem.eql(u8, tag.name, "description")) {
                        assert(false);
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

        const ifa_slice = interfaces.toOwnedSlice();

        return .{
            .name = protocol_name,
            .interfaces = try .init(
                this.context.arena,
                ifa_slice.items(.name),
                ifa_slice.items(.interface),
            ),
            .protocol_imports = .empty,
        };
    }

    fn parseInterface(this: *Parser) Parser.Error!AST.Interface {
        var name_opt: ?[]const u8 = null;
        var version: u32 = 0;
        var description: AST.Description = .{};
        var requests: std.ArrayList(AST.Message) = .empty;
        var events: std.ArrayList(AST.Message) = .empty;
        var enums: std.array_hash_map.String(AST.Enum) = .empty;

        const interface_tag = this.xml_reader.current_node.tag_open;

        if (interface_tag.attributes.len < 1) {
            this.xmlErr("Invalid attribute count", .{});
        }

        for (interface_tag.attributes) |attr| {
            if (std.mem.eql(u8, attr.name, "name")) {
                name_opt = try this.copyString(attr.value);
            } else if (std.mem.eql(u8, attr.name, "version")) {
                version = try std.fmt.parseInt(u32, attr.value, 10);
            } else {
                this.xmlErr("Invalid attribute: '{s}'", .{attr.name});
                return error.MalformedXml;
            }
        }

        const name = name_opt orelse {
            this.xmlErr("Missing name attribute", .{});
            return error.MalformedXml;
        };

        while (true) {
            const node = try this.nextNode();
            switch (node) {
                else => {
                    this.xmlErr("Unexpected xml node: '{s}'", .{@tagName(node)});
                    return error.MalformedXml;
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
                        const request = try this.parseRequest();
                        try requests.append(this.context.arena, request);
                    } else if (std.mem.eql(u8, tag.name, "event")) {
                        try events.append(this.context.arena, try this.parseEvent());
                    } else if (std.mem.eql(u8, tag.name, "enum")) {
                        const e = try this.parseEnum();
                        try enums.putNoClobber(this.context.arena, e.name, e);
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
            .description = description,
            .requests = try requests.toOwnedSlice(this.context.arena),
            .events = try events.toOwnedSlice(this.context.arena),
            .enums = enums,
        };
    }

    fn parseRequest(this: *Parser) Parser.Error!AST.Message {
        var name: []const u8 = "";
        var is_destructor = false;
        var since: u32 = 0;
        var deprecated_since: ?u32 = null;
        var description = AST.Description{};
        var args = std.ArrayList(AST.Arg).empty;

        const req_tag = this.xml_reader.current_node.tag_open;

        if (req_tag.attributes.len < 1) {
            this.xmlErr("Missing name attribute", .{});
        }

        for (req_tag.attributes) |attr| {
            if (std.mem.eql(u8, attr.name, "name")) {
                name = try this.copyString(attr.value);
            } else if (std.mem.eql(u8, attr.name, "type")) {
                is_destructor = std.mem.eql(u8, attr.value, "destructor");
            } else if (std.mem.eql(u8, attr.name, "since")) {
                since = try std.fmt.parseInt(u32, attr.value, 10);
            } else if (std.mem.eql(u8, attr.name, "deprecated-since")) {
                deprecated_since = try std.fmt.parseInt(u32, attr.value, 10);
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
                    return error.MalformedXml;
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
                        try args.append(this.context.arena, try this.parseArg());
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
            .is_destructor = is_destructor,
            .since = since,
            .deprecated_since = deprecated_since,
            .description = description,
            .args = try args.toOwnedSlice(this.context.arena),
        };
    }

    fn parseEvent(this: *Parser) Parser.Error!AST.Message {
        var name: []const u8 = "";
        var is_destructor = false;
        var since: u32 = 0;
        var deprecated_since: ?u32 = null;
        var description = AST.Description{};
        var args = std.ArrayList(AST.Arg).empty;

        const event_tag = this.xml_reader.current_node.tag_open;

        if (event_tag.attributes.len < 1) {
            this.xmlErr("Missing name attribute", .{});
        }

        for (event_tag.attributes) |attr| {
            if (std.mem.eql(u8, attr.name, "name")) {
                name = try this.copyString(attr.value);
            } else if (std.mem.eql(u8, attr.name, "type")) {
                if (std.mem.eql(u8, attr.value, "destructor")) {
                    is_destructor = true;
                } else {
                    this.xmlErr("Invalid enum type attribute '{s}'", .{attr.value});
                    return error.MalformedXml;
                }
            } else if (std.mem.eql(u8, attr.name, "since")) {
                since = try std.fmt.parseInt(u32, attr.value, 10);
            } else if (std.mem.eql(u8, attr.name, "deprecated-since")) {
                deprecated_since = try std.fmt.parseInt(u32, attr.value, 10);
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
                    return error.MalformedXml;
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
                        try args.append(this.context.arena, try this.parseArg());
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

        return .{
            .name = name,
            .is_destructor = is_destructor,
            .since = since,
            .deprecated_since = deprecated_since,
            .description = description,
            .args = try args.toOwnedSlice(this.context.arena),
        };
    }

    fn parseArg(this: *Parser) Parser.Error!AST.Arg {
        var name: ?[]const u8 = "";
        var arg_type: ?AST.TypeTag = null;
        var allow_null = false;
        var interface_name_opt: ?[]const u8 = null;
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
                name = try this.copyString(attr.value);
            } else if (std.mem.eql(u8, attr.name, "type")) {
                arg_type = if (std.mem.eql(u8, attr.value, "int"))
                    .i
                else if (std.mem.eql(u8, attr.value, "uint"))
                    .u
                else if (std.mem.eql(u8, attr.value, "fixed"))
                    .f
                else if (std.mem.eql(u8, attr.value, "string"))
                    .s
                else if (std.mem.eql(u8, attr.value, "object"))
                    .o
                else if (std.mem.eql(u8, attr.value, "new_id"))
                    .n
                else if (std.mem.eql(u8, attr.value, "array"))
                    .a
                else if (std.mem.eql(u8, attr.value, "fd"))
                    .h
                else {
                    this.xmlErr("Invalid type '{s}'", .{attr.value});
                    return error.MalformedXml;
                };
            } else if (std.mem.eql(u8, attr.name, "allow-null")) {
                allow_null = std.mem.eql(u8, attr.value, "true");
            } else if (std.mem.eql(u8, attr.name, "interface")) {
                interface_name_opt = try this.copyString(attr.value);
            } else if (std.mem.eql(u8, attr.name, "enum")) {
                enum_name_opt = try this.copyString(attr.value);
            } else if (std.mem.eql(u8, attr.name, "summary")) {
                summary = try this.copyString(attr.value);
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
            .type = .{ .tag = arg_type.?, .allow_null = allow_null },
            .enum_name = enum_name_opt,
            .interface_name = interface_name_opt,
            .summary = summary,
        };
    }

    fn parseEnum(this: *Parser) Parser.Error!AST.Enum {
        var name: []const u8 = "";
        var is_bitfield = false;
        var since: u32 = 0;
        var deprecated_since: ?u32 = null;
        var description = AST.Description{};
        var entries = std.ArrayList(AST.Enum.Entry).empty;

        const enum_tag = this.xml_reader.current_node.tag_open;

        if (enum_tag.attributes.len < 1) {
            this.xmlErr("Missing name attribute", .{});
        }

        for (enum_tag.attributes) |attr| {
            if (std.mem.eql(u8, attr.name, "name")) {
                name = try this.copyString(attr.value);
            } else if (std.mem.eql(u8, attr.name, "bitfield")) {
                is_bitfield = std.mem.eql(u8, attr.value, "true");
            } else if (std.mem.eql(u8, attr.name, "since")) {
                since = try std.fmt.parseInt(u32, attr.value, 10);
            } else if (std.mem.eql(u8, attr.name, "deprecated-since")) {
                deprecated_since = try std.fmt.parseInt(u32, attr.value, 10);
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
                    return error.MalformedXml;
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
                        try entries.append(this.context.arena, try this.parseEnumEntry());
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
            .is_bitfield = is_bitfield,
            .since = since,
            .deprecated_since = deprecated_since,
            .description = description,
            .entries = try entries.toOwnedSlice(this.context.arena),
        };
    }

    fn parseEnumEntry(this: *Parser) Parser.Error!AST.Enum.Entry {
        var name: ?[]const u8 = "";
        var since: u32 = 0;
        var value_str: ?[]const u8 = null;
        var description: AST.Description = .{};

        const entry_tag = this.xml_reader.current_node.tag_open;

        if (entry_tag.attributes.len < 2) {
            this.xmlErr("Invalid attribute count", .{});
        }

        for (entry_tag.attributes) |attr| {
            if (std.mem.eql(u8, attr.name, "name")) {
                name = try this.copyString(attr.value);
                value_str = try this.copyString(attr.value);
            } else if (std.mem.eql(u8, attr.name, "since")) {
                since = try std.fmt.parseInt(u32, attr.value, 10);
            } else if (std.mem.eql(u8, attr.name, "value")) {
                value_str = try this.copyString(attr.value);
            } else if (std.mem.eql(u8, attr.name, "summary")) {
                description.summary = try this.copyString(attr.value);
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
            const orig_summary = description.summary;
            description = try this.parseDescription();
            if (orig_summary.len > 0) {
                assert(std.mem.eql(u8, orig_summary, description.summary));
            }
            node = try this.nextNode();
        }

        if (node != .tag_close or !std.mem.eql(u8, node.tag_close, "entry")) {
            this.xmlErr("Unexpected closing element '{s}', expected 'entry'", .{node.tag_close});
        }

        return .{
            .name = name.?,
            .since = since,
            .value = value_str.?,
            .description = description,
        };
    }

    fn parseDescription(this: *Parser) Parser.Error!AST.Description {
        var summary: []const u8 = "";
        var text: []const u8 = "";

        const desc_tag = this.xml_reader.current_node.tag_open;

        for (desc_tag.attributes) |attr| {
            if (std.mem.eql(u8, attr.name, "summary")) {
                summary = try this.copyString(attr.value);
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
                    return error.MalformedXml;
                },
                .comment => {}, // skip
                .eof => {
                    this.xmlErr("Unexpected eof", .{});
                    return error.MalformedXml;
                },

                .text => |t| {
                    text = try this.copyString(t);
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

    fn nextNode(this: *Parser) xml.Reader.Error!xml.Reader.Node {
        while (true) {
            const node = try this.xml_reader.next();

            if (node == .text and isWhite(node.text)) {
                // skip
            } else return node;
        }
    }

    fn skipElement(this: *Parser) Parser.Error!void {
        var tmp = mem.getTemp();
        defer tmp.release();

        const first_node = this.xml_reader.current_node.tag_open;

        const start_name = try copyStringAlloc(tmp.allocator(), first_node.name);

        var node = try this.nextNode();
        while (true) {
            switch (node) {
                else => {
                    this.xmlErr("Unexpected xml node type: '{s}'", .{@tagName(node)});
                    return error.MalformedXml;
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

    fn xmlErr(this: *Parser, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(this.context.arena, fmt, args) catch @panic("OOM");

        const loc = this.xml_reader.location;
        this.printErr("{s}:{}:{}: error: {s}\n", .{ this.xml_file_path, loc.line, loc.column, msg });
    }

    fn printErr(this: *Parser, comptime fmt: []const u8, args: anytype) void {
        this.err_writer.print(fmt, args) catch @panic("Err write failed");
        this.err_writer.flush() catch @panic("Err flush failed");
    }

    fn copyString(this: *Parser, str: []const u8) ![]const u8 {
        return copyStringAlloc(this.context.arena, str);
    }

    fn copyStringAlloc(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
        const buf = try allocator.alloc(u8, str.len);
        @memcpy(buf, str);
        return buf;
    }
};

fn isWhite(str: []const u8) bool {
    for (str) |c| if (!std.ascii.isWhitespace(c)) return false;
    return true;
}
