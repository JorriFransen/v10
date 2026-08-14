pub const DynLib = @import("dynlib.zig");
pub const TimeParts = @import("timeparts.zig").TimeParts;

pub const arch = @import("arch/arch.zig").arch;
pub const clip = @import("clip.zig");
pub const intrinsics = @import("intrinsics.zig");
pub const lib = @import("lib/lib.zig");
pub const math = @import("math.zig");
pub const mem = @import("mem/mem.zig");
pub const meta = @import("meta.zig");
pub const os = @import("os/os.zig");
pub const xml = @import("xml.zig");

const std = @import("std");

pub const default_log_level: std.log.Level = std.log.default_level;

pub const default_std_options: std.Options = .{
    .log_level = default_log_level,
    .logFn = defaultLog,
};

pub fn defaultLog(comptime level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);
    var buffer: [64]u8 = undefined;
    const stderr = std.debug.lockStderr(&buffer).terminal();
    defer std.debug.unlockStderr();
    return defaultLogFileTerminal(level, scope, format, args, stderr) catch {};
}
pub fn defaultLogFileTerminal(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
    t: std.Io.Terminal,
) !void {
    const color = switch (level) {
        .err => .red,
        .warn => .yellow,
        .info => .green,
        .debug => .magenta,
    };
    const ts = std.Io.Timestamp.now(std.Options.debug_io, .real);
    const tp = TimeParts.fromMsTimestamp(@bitCast(ts.toMilliseconds()));

    try t.writer.print("{f} ", .{std.fmt.alt(tp, .writeTime)});

    try t.setColor(color);
    try t.setColor(.bold);
    try t.writer.writeAll(level.asText());

    try t.setColor(.dim);
    try t.setColor(.bold);
    if (scope != .default) try t.writer.print("({t})", .{scope});
    try t.writer.writeAll(": ");

    try t.setColor(.reset);
    try t.writer.print(format ++ "\n", args);
}

pub fn assert(cond: bool) void {
    if (@inComptime()) {
        if (!cond) {
            @trap();
        }
    } else {
        if (!cond) {
            @branchHint(.cold);
            std.debug.dumpCurrentStackTrace(.{ .first_address = @returnAddress() });
            @breakpoint();
        }
    }
}

test {
    const t = std.testing;

    t.refAllDecls(clip);
    t.refAllDecls(mem);
}
