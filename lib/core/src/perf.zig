const std = @import("std");

const time = @import("time.zig");

pub const Timestamp = struct {
    wall: time.TimeStamp,
    cpu: time.TimeStamp,

    pub inline fn now() Timestamp {
        return .{
            .wall = .now(.monotonic),
            .cpu = .now(.cpu_thread),
        };
    }

    pub inline fn untilNow(start: *const Timestamp) Duration {
        const n = now();
        return .{
            .wall = start.wall.durationTo(n.wall),
            .cpu = start.cpu.durationTo(n.cpu),
        };
    }
};

pub const Duration = struct {
    wall: time.TimeStamp = .zero,
    cpu: time.TimeStamp = .zero,

    pub inline fn add(this: *Duration, other: Duration) void {
        this.wall._ns += other.wall._ns;
        this.cpu._ns += other.cpu._ns;
    }

    pub inline fn eql(this: *const Duration, other: Duration) bool {
        return this.wall._ns == other.wall._ns and
            this.cpu._ns == other.cpu._ns;
    }

    pub fn format(this: *const Duration, writer: *std.Io.Writer) error{WriteFailed}!void {
        try writer.print("wall: {f}, cpu: {f}", .{ this.wall, this.cpu });
    }

    pub fn formatColumns(this: Duration, writer: *std.Io.Writer) error{WriteFailed}!void {
        var buf: [64]u8 = undefined;
        const fmt = "{s: >12}";

        const wall = std.fmt.bufPrint(&buf, "{f}", .{this.wall}) catch return error.WriteFailed;
        try writer.print("wall: " ++ fmt ++ ",    ", .{wall});
        const cpu = std.fmt.bufPrint(&buf, "{f}", .{this.cpu}) catch return error.WriteFailed;
        try writer.print("cpu: " ++ fmt, .{cpu});
    }
};

pub const VoidTimestamp = struct {
    pub inline fn now() VoidTimestamp {
        return .{};
    }
    pub inline fn untilNow(_: *const VoidTimestamp) VoidDuration {
        return .{};
    }
};

pub const VoidDuration = struct {
    pub inline fn add(_: *VoidDuration, _: VoidDuration) void {}
};
