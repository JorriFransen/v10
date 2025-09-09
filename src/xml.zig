const std = @import("std");
const log = std.log.scoped(.xml);
const mem = @import("memory");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const File = struct {
    version: []const u8,
    encoding: []const u8,

    elements: std.ArrayList(Element),
};

pub const Element = struct {
    name: []const u8,
    self_closing: bool,

    attributes: std.ArrayList(Attribute),
    children: std.ArrayList(Element),
};

pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
};

const Parser = struct {
    tok_offset: usize = 0,
    current_token: Token = .{ .type = .invalid, .data = "" },
    buf: []const u8,

    const TokenType = enum {
        invalid,
        tag_open,
        end_tag_open,
        tag_end,
        self_closing_tag_end,
        identifier,
        string,
        @"=",
        @"?",
        comment,
        text,
        eof,
    };

    const Token = struct {
        type: TokenType,
        /// Slice into the file buffer
        data: []const u8,

        pub fn format(self: @This(), writer: *std.Io.Writer) !void {
            // writer.write("T({}, {s})", .{ self.type, self.data });
            _ = try writer.write("T(");
            _ = try writer.write(@tagName(self.type));
            _ = try writer.write(", \"");
            _ = try writer.write(self.data);
            _ = try writer.write("\")");
            try writer.flush();
        }
    };

    fn nextToken(this: *Parser) Token {
        assert(this.tok_offset < this.buf.len);
        const invalid_token = Token{ .type = .invalid, .data = "INVALID_TOKEN" };

        const start = this.tok_offset;
        const len: usize = 1;
        const c = this.buf[start];
        this.tok_offset += 1;

        const token_type: TokenType =
            switch (c) {
                else => {
                    log.err("Unexpected character: '{c}'", .{c});
                    return invalid_token;
                },

                '?' => .@"?",
                '<' => .tag_open,
            };

        return .{ .type = token_type, .data = this.buf[start .. start + len] };
    }
};

pub const XmlParseError =
    std.fs.File.OpenError ||
    std.fs.File.Reader.SizeError ||
    std.Io.Reader.ReadAllocError ||
    error{};

pub fn parse(allocator: Allocator, xml_path: []const u8) XmlParseError!File {
    const xml_file = try std.fs.cwd().openFile(xml_path, .{});
    var read_buf: [4096]u8 = undefined;
    var reader = xml_file.reader(&read_buf);

    var parser = Parser{
        .tok_offset = 0,
        .buf = try reader.interface.readAlloc(allocator, try reader.getSize()),
    };

    while (true) {
        const t = parser.nextToken();
        log.debug("{f}", .{t});
        if (t.type == .invalid or t.type == .eof) break;
    }

    unreachable;
}
