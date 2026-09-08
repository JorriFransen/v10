const std = @import("std");

pub const Timestamp = struct {
    wall: std.Io.Timestamp,
    cpu: std.Io.Timestamp,

    pub fn now(io: std.Io) Timestamp {
        return .{
            .wall = std.Io.Timestamp.now(io, .awake),
            .cpu = std.Io.Timestamp.now(io, .cpu_thread),
        };
    }

    pub fn untilNow(start: *const Timestamp, io: std.Io) Duration {
        const n = now(io);
        return .{
            .wall = start.wall.durationTo(n.wall),
            .cpu = start.cpu.durationTo(n.cpu),
        };
    }
};

pub const Duration = struct {
    wall: std.Io.Duration,
    cpu: std.Io.Duration,

    pub const zero = Duration{ .wall = .zero, .cpu = .zero };

    pub inline fn add(this: *Duration, other: Duration) void {
        this.wall.nanoseconds += other.wall.nanoseconds;
        this.cpu.nanoseconds += other.cpu.nanoseconds;
    }

    pub inline fn eql(this: *const Duration, other: Duration) bool {
        return this.wall.nanoseconds == other.wall.nanoseconds and
            this.cpu.nanoseconds == other.cpu.nanoseconds;
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
