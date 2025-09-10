const std = @import("std");
const log = std.log.scoped(.xml);
const mem = @import("mem");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const Reader = struct {
    reader: *std.Io.Reader,
    state: State,
    current_node: Node,
    node_tmp: mem.TempArena,

    const State = enum {
        start,
        xml_decl,
        tag_open,
        in_tag,
        text,
        eof,
    };

    pub const Node = union(enum) {
        start: void,
        xml_decl: Decl,
        tag: Tag,
        text: []const u8,
        eof: void,

        pub const Decl = struct {
            version: []const u8,
            encoding: []const u8 = "",
            standalone: []const u8 = "",
        };

        pub const Tag = struct {
            name: []const u8,
            attributes: []Attribute,
            self_closing: bool,
        };

        pub const Attribute = struct {
            name: []const u8,
            value: []const u8,
        };

        pub fn format(this: *const Node, w: *std.Io.Writer) !void {
            _ = try w.write(@tagName(this.*));

            switch (this.*) {
                .start => {},
                .xml_decl => |d| {
                    _ = try w.write(": version: ");
                    _ = try w.write(d.version);
                    if (d.encoding.len > 0) {
                        _ = try w.write(", encoding: ");
                        _ = try w.write(d.encoding);
                    }
                    if (d.standalone.len > 0) {
                        _ = try w.write(", standalone: ");
                        _ = try w.write(d.standalone);
                    }
                },
                .tag => |t| {
                    _ = try w.write(": name: ");
                    _ = try w.write(t.name);
                    _ = try w.write(", self_closing: ");
                    _ = try w.write(if (t.self_closing) "true" else "false");
                    if (t.attributes.len > 0) {
                        _ = try w.write(", attributes:");
                        for (t.attributes) |attr| {
                            _ = try w.write(" ");
                            _ = try w.write(attr.name);
                            _ = try w.write("=\"");
                            _ = try w.write(attr.value);
                            _ = try w.write("\"");
                        }
                    }
                },
                .text => |t| {
                    _ = try w.write(": \"");
                    _ = try w.write(t);
                    _ = try w.write("\"");
                },
                .eof => {
                    unreachable;
                },
            }

            try w.flush();
        }
    };

    pub fn init(reader: *std.Io.Reader) Reader {
        return .{
            .state = .start,
            .reader = reader,
            .current_node = .{ .start = {} },
            .node_tmp = mem.getTemp(),
        };
    }

    pub const Error =
        std.Io.Reader.Error ||
        error{MalformedXml};

    pub fn next(this: *Reader) Error!Node {
        this.node_tmp.release();

        while (true) {
            switch (this.state) {
                .start => {
                    try this.expect("<?xml");
                    this.state = .xml_decl;
                    continue;
                },

                .xml_decl => {
                    var result: Node.Decl = .{ .version = undefined };

                    this.skipWhitespace();
                    while (!try this.peek('?')) {
                        const attr_name = try this.parseIdentifier();
                        try this.expect("=");

                        if (std.mem.eql(u8, attr_name, "version")) {
                            result.version = try this.parseString();
                        } else if (std.mem.eql(u8, attr_name, "encoding")) {
                            result.encoding = try this.parseString();
                        } else if (std.mem.eql(u8, attr_name, "standalone")) {
                            result.standalone = try this.parseString();
                        }
                        this.skipWhitespace();
                    }

                    try this.expect("?>");
                    this.current_node = .{ .xml_decl = result };
                    this.state = .tag_open;
                    return this.current_node;
                },

                .tag_open => {
                    this.skipWhitespace();
                    try this.expect("<");
                    const tag_name = try this.parseIdentifier();
                    this.skipWhitespace();

                    var attributes = std.ArrayList(Node.Attribute){};

                    var self_closing = false;
                    while (!try this.match(">")) {
                        const attr_name = try this.parseIdentifier();
                        try this.expect("=");
                        const attr_value = try this.parseString();

                        attributes.append(
                            this.node_tmp.allocator(),
                            .{ .name = attr_name, .value = attr_value },
                        ) catch @panic("OOM");

                        if (try this.match("/>")) {
                            self_closing = true;
                            break;
                        }
                    }

                    this.current_node = .{ .tag = .{
                        .name = tag_name,
                        .attributes = attributes.items,
                        .self_closing = self_closing,
                    } };
                    this.state = .in_tag;
                    return this.current_node;
                },

                .in_tag => {
                    if (try this.peek('<')) {
                        unreachable;
                    } else {
                        this.state = .text;
                        continue;
                    }
                },

                .text => {
                    var text_buf = std.ArrayList(u8){};

                    while (true) {
                        // TODO: Replace with takeDelimiterInclusive when fixed... (it takes too much!)
                        const result = this.reader.peekDelimiterExclusive('<') catch |e| switch (e) {
                            error.EndOfStream => return error.MalformedXml,
                            error.ReadFailed => return error.ReadFailed,
                            error.StreamTooLong => {
                                text_buf.appendSlice(this.node_tmp.allocator(), this.reader.buffered()) catch @panic("OOM");
                                this.reader.tossBuffered();
                                continue;
                            },
                        };
                        text_buf.appendSlice(this.node_tmp.allocator(), result) catch @panic("OOM");
                        this.reader.toss(result.len);
                        break;
                    }

                    this.current_node = .{ .text = text_buf.items };
                    this.state = .tag_open;
                    return this.current_node;
                },

                .eof => {
                    return .{ .eof = {} };
                },
            }
        }
    }

    pub fn done(this: *Reader) bool {
        return this.current_node == .eof;
    }

    fn skipWhitespace(this: *Reader) void {
        var c = this.reader.peekByte() catch return;
        while (std.ascii.isWhitespace(c)) {
            this.reader.toss(1);
            c = this.reader.peekByte() catch return;
        }
    }

    fn parseIdentifier(this: *Reader) Error![]const u8 {
        var tmp = mem.getScratch(this.node_tmp.arena);
        defer tmp.release();

        var buffer = std.ArrayList(u8){};

        while (true) {
            const c = this.reader.peekByte() catch |e| switch (e) {
                error.EndOfStream => break,
                error.ReadFailed => return e,
            };
            if (!std.ascii.isAlphabetic(c)) break;
            buffer.append(tmp.allocator(), c) catch @panic("OOM");
            this.reader.toss(1);
        }

        return this.dupe(buffer.items);
    }

    fn parseString(this: *Reader) Error![]const u8 {
        try this.expect("\"");

        const result = this.reader.takeDelimiterInclusive('"') catch |e| switch (e) {
            error.EndOfStream, error.StreamTooLong => return error.MalformedXml,
            error.ReadFailed => return error.ReadFailed,
        };

        return this.dupe(result[0 .. result.len - 1]);
    }

    fn expect(this: *Reader, comptime str: []const u8) Error!void {
        const peek_opt = this.reader.peekArray(str.len) catch |e| switch (e) {
            error.EndOfStream => null,
            error.ReadFailed => return error.ReadFailed,
        };

        if (!(peek_opt != null and std.mem.eql(u8, peek_opt.?, str))) {
            log.err("Expected '{s}' got '{s}'", .{ str, peek_opt orelse "" });
            return error.MalformedXml;
        }

        this.reader.toss(str.len);
    }

    fn match(this: *Reader, comptime str: []const u8) Error!bool {
        const peek_opt = this.reader.peekArray(str.len) catch |e| switch (e) {
            error.EndOfStream => null,
            error.ReadFailed => return error.ReadFailed,
        };

        if (peek_opt != null and std.mem.eql(u8, peek_opt.?, str)) {
            this.reader.toss(str.len);
            return true;
        }

        return false;
    }

    fn peek(this: *Reader, char: u8) Error!bool {
        const actual = this.reader.peekByte() catch |e| switch (e) {
            error.EndOfStream => return error.MalformedXml,
            else => return e,
        };

        return actual == char;
    }

    fn dupe(this: *Reader, data: []const u8) []const u8 {
        const new = this.node_tmp.allocator().alloc(u8, data.len) catch @panic("OOM");
        @memcpy(new, data);
        return new;
    }
};
