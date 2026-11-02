const std = @import("std");

const os = @import("os/os.zig").current;

pub const windows_epoch_offset_sec = -11644473600;

pub const ns_per_us = 1000;
pub const ns_per_ms = 1000 * ns_per_us;
pub const ns_per_s = 1000 * ns_per_ms;

pub const us_per_ms = 1000;
pub const us_per_s = 1000 * us_per_ms;

pub const ms_per_s = 1000;

pub const Clock = enum {
    real,
    monotonic,
    cpu_thread,
    cpu_process,
};

/// Nanoseconds passed since UTC 1970-01-01 for .real clock and filesystem timestamps.
pub const Timestamp = struct {
    _ns: i96,

    pub const zero: Timestamp = .{ ._ns = 0 };

    pub inline fn now(clock: Clock) Timestamp {
        return os.getTime(clock);
    }

    pub inline fn fromNs(nsec: i96) Timestamp {
        return .{ ._ns = nsec };
    }

    pub inline fn durationTo(start: Timestamp, end: Timestamp) Timestamp {
        return .{ ._ns = end._ns - start._ns };
    }

    pub inline fn ns(this: Timestamp) i96 {
        return this._ns;
    }

    pub inline fn ms(this: Timestamp) i64 {
        return @intCast(@divTrunc(this._ns, ns_per_ms));
    }

    pub fn format(this: Timestamp, writer: *std.Io.Writer) !void {
        const std_duration = std.Io.Duration.fromNanoseconds(this._ns);
        try std_duration.format(writer);
    }
};
