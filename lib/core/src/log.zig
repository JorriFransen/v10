const std = @import("std");
const builtin = @import("builtin");

const assert = @import("debug.zig").assert;
const time = @import("time.zig");
const TimeParts = @import("timeparts.zig");

pub const Level = enum(u3) {
    err = 0,
    warn = 1,
    info = 2,
    debug = 3,

    pub const default: @This() = if (builtin.mode == .debug) .debug else .info;
};

pub const LockOrUnlock = enum {
    lock,
    unlock,
};

pub const ScopeLevel = struct {
    scope: @EnumLiteral(),
    level: Level,
};

pub const LockFn = *const fn (action: LockOrUnlock, buffer: ?[]u8) ?*std.Io.Writer;
pub const HeaderFn = *const fn (level: Level, scope: []const u8, writer: *std.Io.Writer) void;

pub var lock_fn: ?LockFn = null;
pub var header_fn: ?HeaderFn = null;

fn lock(action: LockOrUnlock, buffer: ?[]u8) ?*std.Io.Writer {
    const l = lock_fn orelse defaultLock;
    return l(action, buffer);
}

fn header(level: Level, scope: []const u8, writer: *std.Io.Writer) void {
    const h = header_fn orelse defaultHeader;
    h(level, scope, writer);
}

var _default_log_locked_stderr: ?std.Io.LockedStderr = null;
pub fn defaultLock(action: LockOrUnlock, buffer: ?[]u8) ?*std.Io.Writer {
    switch (action) {
        .lock => {
            assert(_default_log_locked_stderr == null);
            assert(buffer != null);

            const locked = std.debug.lockStderr(buffer.?);
            _default_log_locked_stderr = locked;
            return &locked.file_writer.interface;
        },

        .unlock => {
            assert(_default_log_locked_stderr != null);
            assert(buffer == null);

            if (_default_log_locked_stderr) |_| {
                std.debug.unlockStderr();
            }
            _default_log_locked_stderr = null;
            return null;
        },
    }
}

pub fn defaultHeader(level: Level, scope: []const u8, writer: *std.Io.Writer) void {
    const color: std.Io.Terminal.Color = switch (level) {
        .err => .red,
        .warn => .yellow,
        .info => .green,
        .debug => .magenta,
    };

    const tts = time.TimeStamp.now(.real);
    const tp = TimeParts.fromMsTimestamp(@intCast(tts.ms()));

    print: {
        writer.print("{f} ", .{std.fmt.alt(tp, .writeTime)}) catch break :print;

        c: {
            const t = (_default_log_locked_stderr orelse break :c).terminal();
            t.setColor(color) catch break :c;
            t.setColor(.bold) catch break :c;
        }

        writer.writeAll(@tagName(level)) catch break :print;

        c: {
            const t = (_default_log_locked_stderr orelse break :c).terminal();

            t.setColor(.dim) catch break :print;
            t.setColor(.bold) catch break :print;
        }

        if (!std.mem.eql(u8, scope, "default")) {
            writer.print("({s})", .{scope}) catch break :print;
        }

        writer.writeAll(": ") catch break :print;

        c: {
            const t = (_default_log_locked_stderr orelse break :c).terminal();
            t.setColor(.reset) catch break :c;
        }
    }
}

fn levelSufficient(comptime level: Level, comptime scope: @EnumLiteral()) bool {
    const root = @import("root");
    const scope_levels: []const ScopeLevel = if (@hasDecl(root, "log_scope_levels")) &root.log_scope_levels else &.{};

    const level_value = @backingInt(level);

    inline for (scope_levels) |scope_level| {
        if (scope_level.scope == scope) return level_value <= @backingInt(scope_level.level);
    }

    return level_value <= @backingInt(Level.default);
}

pub fn log(comptime level: Level, comptime scope: @EnumLiteral(), comptime fmt: []const u8, args: anytype) void {
    if (levelSufficient(level, scope)) {
        var buffer: [128]u8 = undefined;

        if (lock(.lock, &buffer)) |writer| {
            defer _ = lock(.unlock, null);

            header(level, @tagName(scope), writer);

            print: {
                writer.print(fmt, args) catch break :print;
                writer.writeByte('\n') catch break :print;
            }
        }
    }
}

pub fn scoped(comptime scope: @EnumLiteral()) type {
    return struct {
        pub fn err(comptime fmt: []const u8, args: anytype) void {
            @branchHint(.cold);
            log(.err, scope, fmt, args);
        }

        pub fn warn(comptime fmt: []const u8, args: anytype) void {
            log(.warn, scope, fmt, args);
        }

        pub fn info(comptime fmt: []const u8, args: anytype) void {
            log(.info, scope, fmt, args);
        }

        pub fn debug(comptime fmt: []const u8, args: anytype) void {
            log(.debug, scope, fmt, args);
        }
    };
}

pub const default = scoped(.default);
pub const err = default.err;
pub const warn = default.warn;
pub const info = default.info;
pub const debug = default.debug;
