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

pub var fatal_fn: ?FatalFn = null;

pub fn fatal(msg: []const u8, ra: ?usize) noreturn {
    const f = fatal_fn orelse defaultFatalFn;
    f(msg, ra);
}

pub const default_panic = struct {
    pub fn call(msg: []const u8, ra: ?usize) noreturn {
        fatal(msg, ra);
    }

    pub fn sentinelMismatch(expected: anytype, found: @TypeOf(expected)) noreturn {
        @branchHint(.cold);
        std.debug.panicExtra(@returnAddress(), "sentinel mismatch: expected {any}, found {any}", .{
            expected, found,
        });
    }

    pub fn unwrapError(err: anyerror) noreturn {
        @branchHint(.cold);
        std.debug.panicExtra(@returnAddress(), "attempt to unwrap error: {s}", .{@errorName(err)});
    }

    pub fn outOfBounds(index: usize, len: usize) noreturn {
        @branchHint(.cold);
        std.debug.panicExtra(@returnAddress(), "index out of bounds: index {d}, len {d}", .{ index, len });
    }

    pub fn startGreaterThanEnd(start: usize, end: usize) noreturn {
        @branchHint(.cold);
        std.debug.panicExtra(@returnAddress(), "start index {d} is larger than end index {d}", .{ start, end });
    }

    pub fn inactiveUnionField(active: anytype, accessed: @TypeOf(active)) noreturn {
        @branchHint(.cold);
        std.debug.panicExtra(@returnAddress(), "access of union field '{s}' while field '{s}' is active", .{
            @tagName(accessed), @tagName(active),
        });
    }

    pub fn sliceCastLenRemainder(src_len: usize) noreturn {
        @branchHint(.cold);
        std.debug.panicExtra(@returnAddress(), "slice length '{d}' does not divide exactly into destination elements", .{src_len});
    }

    pub fn reachedUnreachable() noreturn {
        @branchHint(.cold);
        call("reached unreachable code", @returnAddress());
    }

    pub fn unwrapNull() noreturn {
        @branchHint(.cold);
        call("attempt to use null value", @returnAddress());
    }

    pub fn castToNull() noreturn {
        @branchHint(.cold);
        call("cast causes pointer to be null", @returnAddress());
    }

    pub fn incorrectAlignment() noreturn {
        @branchHint(.cold);
        call("incorrect alignment", @returnAddress());
    }

    pub fn invalidErrorCode() noreturn {
        @branchHint(.cold);
        call("invalid error code", @returnAddress());
    }

    pub fn unexpectedErrorCode(err: anyerror) noreturn {
        @branchHint(.cold);
        std.debug.panicExtra(@returnAddress(), "unexpected error code, found error.{s}", .{@errorName(err)});
    }

    pub fn integerOutOfBounds() noreturn {
        @branchHint(.cold);
        call("integer does not fit in destination type", @returnAddress());
    }

    pub fn integerOverflow() noreturn {
        @branchHint(.cold);
        call("integer overflow", @returnAddress());
    }

    pub fn shlOverflow() noreturn {
        @branchHint(.cold);
        call("left shift overflowed bits", @returnAddress());
    }

    pub fn shrOverflow() noreturn {
        @branchHint(.cold);
        call("right shift overflowed bits", @returnAddress());
    }

    pub fn divideByZero() noreturn {
        @branchHint(.cold);
        call("division by zero", @returnAddress());
    }

    pub fn exactDivisionRemainder() noreturn {
        @branchHint(.cold);
        call("exact division produced remainder", @returnAddress());
    }

    pub fn integerPartOutOfBounds() noreturn {
        @branchHint(.cold);
        call("integer part of floating point value out of bounds", @returnAddress());
    }

    pub fn corruptSwitch() noreturn {
        @branchHint(.cold);
        call("switch on corrupt value", @returnAddress());
    }

    pub fn shiftRhsTooBig() noreturn {
        @branchHint(.cold);
        call("shift amount is greater than the type size", @returnAddress());
    }

    pub fn invalidEnumValue() noreturn {
        @branchHint(.cold);
        call("invalid enum value", @returnAddress());
    }

    pub fn forLenMismatch() noreturn {
        @branchHint(.cold);
        call("for loop over objects with non-equal lengths", @returnAddress());
    }

    pub fn copyLenMismatch() noreturn {
        @branchHint(.cold);
        call("source and destination arguments have non-equal lengths", @returnAddress());
    }

    pub fn memcpyAlias() noreturn {
        @branchHint(.cold);
        call("@memcpy arguments alias", @returnAddress());
    }

    pub fn noreturnReturned() noreturn {
        @branchHint(.cold);
        call("'noreturn' function returned", @returnAddress());
    }

    pub fn loadUninstantiableType() noreturn {
        @branchHint(.cold);
        call("attempt to load uninstantiable type", @returnAddress());
    }
};

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
