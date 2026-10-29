const std = @import("std");
const builtin = @import("builtin");

pub const FatalFn = *const fn (msg: []const u8, ra: ?usize) noreturn;

pub fn defaultFatalFn(msg: []const u8, ra: ?usize) noreturn {
    print: {
        const stderr = std.debug.lockStderr(&.{}).terminal();
        defer std.debug.unlockStderr();
        const writer = stderr.writer;

        writer.print("{s}\n", .{msg}) catch break :print;

        if (@errorReturnTrace()) |t| if (t.index > 0) {
            writer.writeAll("error return context:\n") catch break :print;
            std.debug.writeErrorReturnTrace(t, stderr) catch break :print;
            writer.writeAll("\nstack trace:\n") catch break :print;
        };

        std.debug.writeCurrentStackTrace(.{
            .first_address = ra orelse @returnAddress(),
            .allow_unsafe_unwind = true,
        }, stderr) catch break :print;
    }

    // TODO: Wait for other threads to finish panicking?

    if (@inComptime()) {
        @trap();
    }

    @breakpoint();
    @trap();
}

pub var fatal_fn: FatalFn = defaultFatalFn;

pub fn fatal(msg: []const u8, ra: ?usize) noreturn {
    fatal_fn(msg, ra);
}

pub const default_panic = std.debug.FullPanic(fatal);

pub fn assert(cond: bool) void {
    if (builtin.mode == .debug or builtin.mode == .safe) {
        if (!cond) {
            @branchHint(.cold);
            // @disableInstrumentation();

            fatal("Assertion failed!", @returnAddress());
            unreachable;
        }
    }
}
