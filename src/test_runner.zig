// Modded from from https://gist.github.com/karlseguin/c6bea5b35e4e8d26af6f81c22cb5d76b

// in your build.zig, you can specify a custom test runner:
// const tests = b.addTest(.{
//   .target = target,
//   .optimize = optimize,
//   .test_runner = b.path("test_runner.zig"), // add this line
//   .root_source_file = b.path("src/main.zig"),
// });

const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");
const mem = @import("memory");

pub const std_options = std.Options{
    .log_level = @enumFromInt(@intFromEnum(options.test_log_level)),
};

const BORDER = "=" ** 80;

const Status = enum {
    pass,
    fail,
    skip,
    text,
};

fn getenvOwned(alloc: std.mem.Allocator, key: []const u8) ?[]u8 {
    const v = std.process.getEnvVarOwned(alloc, key) catch |err| {
        if (err == error.EnvironmentVariableNotFound) {
            return null;
        }
        std.log.warn("failed to get env var {s} due to err {}", .{ key, err });
        return null;
    };
    return v;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 12 }){};
    const alloc = gpa.allocator();
    const fail_first = blk: {
        if (getenvOwned(alloc, "TEST_FAIL_FIRST")) |e| {
            defer alloc.free(e);
            break :blk std.mem.eql(u8, e, "true");
        }
        break :blk false;
    };
    const filter = getenvOwned(alloc, "TEST_FILTER");
    defer if (filter) |f| alloc.free(f);

    try mem.init();
    defer mem.deinit();

    const printer = Printer.init();
    if (options.test_color)
        printer.fmt("\r\x1b[0K", .{}); // beginning of line and clear to end of line

    var pass: usize = 0;
    var fail: usize = 0;
    var skip: usize = 0;
    var leak: usize = 0;

    for (builtin.test_functions) |t| {
        std.testing.allocator_instance = .{};
        var status = Status.pass;

        if (filter) |f| {
            if (std.mem.indexOf(u8, t.name, f) == null) {
                continue;
            }
        }

        const name = if (options.test_full_name) t.name else (if (std.mem.lastIndexOf(u8, t.name, ".")) |idx| t.name[idx + 1 ..] else t.name);

        printer.fmt("Testing \"{s}\": ", .{name});
        const result = t.func();

        mem.resetTemp();

        if (std.testing.allocator_instance.deinit() == .leak) {
            leak += 1;
            printer.status(.fail, "\n{s}\n\"{s}\" - Memory Leak\n{s}\n", .{ BORDER, t.name, BORDER });
        }

        if (result) |_| {
            pass += 1;
        } else |err| {
            switch (err) {
                error.SkipZigTest => {
                    skip += 1;
                    status = .skip;
                },
                else => {
                    status = .fail;
                    fail += 1;
                    printer.status(.fail, "\n{s}\n\"{s}\" - {s}\n{s}\n", .{ BORDER, t.name, @errorName(err), BORDER });
                    if (@errorReturnTrace()) |trace| {
                        std.debug.dumpStackTrace(trace.*);
                    }
                    if (fail_first) {
                        break;
                    }
                },
            }
        }

        printer.status(status, "[{s}]\n", .{@tagName(status)});
    }

    const total_tests = pass + fail;
    const status: Status = if (fail == 0) .pass else .fail;
    printer.status(status, "\n{d} of {d} test{s} passed\n", .{ pass, total_tests, if (total_tests != 1) "s" else "" });
    if (skip > 0) {
        printer.status(.skip, "{d} test{s} skipped\n", .{ skip, if (skip != 1) "s" else "" });
    }
    if (leak > 0) {
        printer.status(.fail, "{d} test{s} leaked\n", .{ leak, if (leak != 1) "s" else "" });
    }
    std.process.exit(if (fail == 0) 0 else 1);
}

const Printer = struct {
    out: std.fs.File.DeprecatedWriter,

    fn init() Printer {
        return .{
            .out = std.fs.File.stderr().deprecatedWriter(),
        };
    }

    fn fmt(self: Printer, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.out, format, args) catch unreachable;
    }

    fn status(self: Printer, s: Status, comptime format: []const u8, args: anytype) void {
        const out = self.out;

        if (options.test_color) {
            const color = switch (s) {
                .pass => "\x1b[32m",
                .fail => "\x1b[31m",
                .skip => "\x1b[33m",
                else => "",
            };

            // TODO: ttyconf
            out.writeAll(color) catch @panic("writeAll failed?!");
        }

        std.fmt.format(out, format, args) catch @panic("std.fmt.format failed?!");

        if (options.test_color) self.fmt("\x1b[0m", .{});
    }
};
