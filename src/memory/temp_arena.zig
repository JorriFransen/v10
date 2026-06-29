const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const mem = @import("memory.zig");
const Arena = @import("arena.zig").Arena;
const TempArena = @This();

arena: *Arena,
reset_to: usize,
a: Allocator,

pub fn init(arena: *Arena) TempArena {
    return .{
        .arena = arena,
        .reset_to = arena.used,
        .a = arena.allocator(),
    };
}

pub fn release(this: *TempArena) void {
    assert(this.arena.used >= this.reset_to);
    this.arena.used = this.reset_to;
}

pub const StringBuilder = struct {
    /// This TempArena should be dedicated to this StringBuilder
    tmp: TempArena,

    pub const Error = error{} || Arena.Error;

    /// tmp_arena should be dedicated to this StringBuilder
    pub fn init(tmp_arena: TempArena) StringBuilder {
        return .{ .tmp = tmp_arena };
    }

    pub fn deinit(this: *StringBuilder) void {
        this.tmp.release();
    }

    pub fn currentString(this: *const StringBuilder) []const u8 {
        const result = this.tmp.arena.data[this.tmp.reset_to..this.tmp.arena.used];
        return result;
    }

    pub fn write(this: *StringBuilder, str: []const u8) Error!void {
        const available = this.tmp.arena.data.len - this.tmp.arena.used;

        if (str.len > available) {
            try this.tmp.arena.grow(this.tmp.arena.used + str.len);
        }

        @memcpy(this.tmp.arena.data[this.tmp.arena.used .. this.tmp.arena.used + str.len], str);
        this.tmp.arena.used += str.len;
    }

    pub fn writeByte(this: *StringBuilder, byte: u8) Error!void {
        try this.write(&.{byte});
    }

    pub fn print(this: *StringBuilder, comptime fmt: []const u8, args: anytype) Error!void {
        var tmp = mem.getScratch(this.tmp.a);
        defer tmp.release();

        const str = try std.fmt.allocPrint(tmp.a, fmt, args);

        try this.write(str);
    }
};
