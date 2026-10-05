const std = @import("std");

const os = @import("os/os.zig").current;

pub const Clock = enum {
    real,
    monotonic,
    cpu_thread,
    cpu_process,
};

pub const TimeStamp = struct {
    _ns: i96,

    pub const zero: TimeStamp = .{ ._ns = 0 };

    pub inline fn now(clock: Clock) TimeStamp {
        return os.getTime(clock);
    }

    pub inline fn fromNs(nsec: i96) TimeStamp {
        return .{ ._ns = nsec };
    }

    pub inline fn durationTo(start: TimeStamp, end: TimeStamp) TimeStamp {
        return .{ ._ns = end._ns - start._ns };
    }

    pub inline fn ns(this: TimeStamp) i96 {
        return this._ns;
    }

    pub inline fn ms(this: TimeStamp) i64 {
        return @intCast(@divTrunc(this._ns, std.time.ns_per_ms));
    }

    pub fn format(this: TimeStamp, writer: *std.Io.Writer) !void {
        const std_duration = std.Io.Duration.fromNanoseconds(this._ns);
        try std_duration.format(writer);
    }
};
