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
    location: Location,

    const State = enum {
        start,
        xml_decl,
        tag,
        in_tag,
        text,
        eof,
    };

    pub const Node = union(enum) {
        start: void,
        xml_decl: Decl,
        tag_open: TagOpen,
        tag_close: []const u8,
        text: []const u8,
        comment: []const u8,
        eof: void,

        pub const Decl = struct {
            version: []const u8,
            encoding: []const u8 = "",
            standalone: []const u8 = "",
        };

        pub const TagOpen = struct {
            name: []const u8,
            attributes: []Attribute,
            self_closing: bool,
        };

        pub const Attribute = struct {
            name: []const u8,
            value: []const u8,
        };

        pub fn format(this: *const Node, w: *std.Io.Writer) !void {
            var tmp = mem.getTemp();
            defer tmp.release();
            const ta = tmp.allocator();

            _ = try w.write(@tagName(this.*));
            const info_str = switch (this.*) {
                .start, .eof => "",

                .xml_decl => |d| std.fmt.allocPrint(ta, ": version: '{s}', encoding: '{s}', standalone: '{s}'", .{
                    d.version, d.encoding, d.standalone,
                }) catch @panic("OOM"),

                .tag_open => |t| blk: {
                    const prefix = std.fmt.allocPrint(ta, ": name: '{s}', self_closing: {}", .{ t.name, t.self_closing }) catch @panic("OOM");
                    _ = try w.write(prefix);
                    if (t.attributes.len > 0) {
                        _ = try w.write(", attributes:");
                        for (t.attributes) |attr| {
                            const a_str = std.fmt.allocPrint(ta, " {s}='{s}'", .{ attr.name, attr.value }) catch @panic("OOM");
                            _ = try w.write(a_str);
                        }
                    }
                    break :blk "";
                },

                .tag_close => |t| std.fmt.allocPrint(ta, ": name: '{s}'", .{t}) catch @panic("OOM"),
                .text => |t| std.fmt.allocPrint(ta, ": \"{s}\"", .{t}) catch @panic("OOM"),
                .comment => |t| std.fmt.allocPrint(ta, ": \"{s}\"", .{t}) catch @panic("OOM"),
            };

            _ = try w.write(info_str);
            try w.flush();
        }
    };

    pub const Location = struct {
        path: []const u8,
        line: usize,
        column: usize,
    };

    /// The path is only used for location info
    pub fn init(reader: *std.Io.Reader, path: []const u8) Reader {
        return .{
            .state = .start,
            .reader = reader,
            .current_node = .{ .start = {} },
            .node_tmp = mem.getTemp(),
            .location = .{
                .path = path,
                .line = 1,
                .column = 1,
            },
        };
    }

    pub const Error =
        std.mem.Allocator.Error ||
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
                    this.state = .tag;
                    return this.current_node;
                },

                .tag => {
                    this.skipWhitespace();
                    try this.expect("<");

                    if (try this.match("/")) {
                        const tag_name = try this.parseIdentifier();
                        try this.expect(">");

                        this.current_node = .{ .tag_close = tag_name };
                        this.state = .in_tag;
                        return this.current_node;
                    } else if (try this.match("!--")) {
                        this.current_node = .{ .comment = try this.parseComment() };
                        this.state = .in_tag;
                        return this.current_node;
                    } else {
                        const tag_name = try this.parseIdentifier();
                        this.skipWhitespace();

                        var attributes = std.ArrayList(Node.Attribute){};

                        this.skipWhitespace();

                        var self_closing = false;
                        while (!try this.match(">")) {
                            const attr_name = try this.parseIdentifier();
                            try this.expect("=");
                            const attr_value = try this.parseString();

                            attributes.append(
                                this.node_tmp.allocator(),
                                .{ .name = attr_name, .value = attr_value },
                            ) catch @panic("OOM");

                            this.skipWhitespace();

                            if (try this.match("/>")) {
                                self_closing = true;
                                break;
                            }
                        }

                        this.current_node = .{ .tag_open = .{
                            .name = tag_name,
                            .attributes = attributes.items,
                            .self_closing = self_closing,
                        } };
                        this.state = .in_tag;
                        return this.current_node;
                    }
                },

                .in_tag => {
                    if ('<' == this.reader.peekByte() catch |e| switch (e) {
                        error.ReadFailed => return e,
                        error.EndOfStream => {
                            this.state = .eof;
                            continue;
                        },
                    }) {
                        this.state = .tag;
                        continue;
                    } else {
                        this.state = .text;
                        continue;
                    }
                },

                .text => {
                    this.current_node = .{ .text = try this.takeDelimiterExclusive('<') };
                    this.state = .in_tag;
                    return this.current_node;
                },

                .eof => {
                    this.current_node = .{ .eof = {} };
                    return this.current_node;
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
            this.toss(1);
            c = this.reader.peekByte() catch return;
        }
    }

    fn parseIdentifier(this: *Reader) Error![]const u8 {
        var tmp = mem.getScratch(this.node_tmp.arena);
        defer tmp.release();

        var buffer = std.ArrayList(u8){};

        const first = this.reader.peekByte() catch |e| switch (e) {
            error.EndOfStream => return error.MalformedXml,
            error.ReadFailed => return e,
        };
        if (!(std.ascii.isAlphabetic(first) or first == '_' or first == ':')) {
            this.printFatalError("Invalid character in identifier: '{c}'", .{first});
            return error.MalformedXml;
        }
        buffer.append(tmp.allocator(), first) catch @panic("OOM");
        this.toss(1);

        while (true) {
            const c = this.reader.peekByte() catch |e| switch (e) {
                error.EndOfStream => break,
                error.ReadFailed => return e,
            };
            if (!(std.ascii.isAlphanumeric(c) or
                c == '_' or
                c == '-' or
                c == ':' or
                c == '.')) break;
            buffer.append(tmp.allocator(), c) catch @panic("OOM");
            this.toss(1);
        }

        return this.dupe(buffer.items);
    }

    fn parseString(this: *Reader) Error![]const u8 {
        try this.expect("\"");
        return try this.takeDelimiterInclusive('"');
    }

    /// This assumes the leader <-- is already consumed
    fn parseComment(this: *Reader) Error![]const u8 {
        var buf = std.ArrayList(u8){};

        while (true) {
            const r = try this.takeDelimiterInclusive('-');
            try buf.appendSlice(this.node_tmp.allocator(), r);

            if (try this.match("->")) break;
        }

        return buf.items;
    }

    fn expect(this: *Reader, comptime str: []const u8) Error!void {
        const peek_opt = this.reader.peekArray(str.len) catch |e| switch (e) {
            error.EndOfStream => null,
            error.ReadFailed => return error.ReadFailed,
        };

        if (!(peek_opt != null and std.mem.eql(u8, peek_opt.?, str))) {
            this.printFatalError("Expected '{s}' got '{s}'", .{ str, peek_opt orelse "" });
            return error.MalformedXml;
        }

        this.toss(str.len);
    }

    fn match(this: *Reader, comptime str: []const u8) Error!bool {
        const peek_opt = this.reader.peekArray(str.len) catch |e| switch (e) {
            error.EndOfStream => null,
            error.ReadFailed => return error.ReadFailed,
        };

        if (peek_opt != null and std.mem.eql(u8, peek_opt.?, str)) {
            this.toss(str.len);
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

    fn takeDelimiterExclusive(this: *Reader, delim: u8) Error![]const u8 {
        var buf = std.ArrayList(u8){};
        var rest: []const u8 = "";

        flushed: {
            // TODO: Replace with takeDelimiterInclusive when fixed... (it takes too much!)
            rest = this.reader.peekDelimiterExclusive(delim) catch |e| switch (e) {
                error.EndOfStream => return error.MalformedXml,
                error.ReadFailed => return error.ReadFailed,
                error.StreamTooLong => {
                    try buf.appendSlice(this.node_tmp.allocator(), this.reader.buffered());
                    this.tossBuffered();
                    break :flushed;
                },
            };
        }
        try buf.appendSlice(this.node_tmp.allocator(), rest);
        this.toss(rest.len);

        return buf.items;
    }

    fn takeDelimiterInclusive(this: *Reader, delim: u8) Error![]const u8 {
        const result = try this.takeDelimiterExclusive(delim);
        this.toss(1);
        return result;
    }

    fn toss(this: *Reader, n: usize) void {
        this.updateLocation(n);
        this.reader.toss(n);
    }

    fn tossBuffered(this: *Reader) void {
        this.toss(this.reader.bufferedLen());
    }

    fn updateLocation(this: *Reader, n: usize) void {
        for (this.reader.buffered()[0..n]) |c| {
            if (c == '\n') {
                this.location.line += 1;
                this.location.column = 1;
            } else {
                this.location.column += 1;
            }
        }
    }

    fn dupe(this: *Reader, data: []const u8) []const u8 {
        const new = this.node_tmp.allocator().alloc(u8, data.len) catch @panic("OOM");
        @memcpy(new, data);
        return new;
    }

    fn printFatalError(this: *Reader, comptime fmt: []const u8, args: anytype) void {
        const tmp = &this.node_tmp;
        var write_buf: [512]u8 = undefined;
        var writer = std.fs.File.stderr().writer(&write_buf);

        _ = writer.interface.write(
            tmpPrint(tmp, "{s}:{}:{}: ", .{
                this.location.path,
                this.location.line,
                this.location.column,
            }),
        ) catch unreachable;
        _ = writer.interface.write(tmpPrint(tmp, fmt, args)) catch unreachable;
        writer.interface.flush() catch unreachable;
    }
};

inline fn tmpPrint(tmp: *mem.TempArena, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(tmp.allocator(), fmt, args) catch @panic("OOM");
}
