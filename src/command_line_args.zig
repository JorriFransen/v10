const std = @import("std");
const alloc = @import("alloc.zig");
const clap = @import("clap");
const glfw = @import("glfw");

const ClapOptions = struct {
    glfw_platform: glfw.Platform = .ANY,
    help: bool = false,
};
pub var clap_options: ClapOptions = undefined;

const clap_params = clap.parseParamsComptime(
    \\-h, --help                    Display this help and exit.
    \\--glfw-platform   <GLFWApi>   Select glfw window api.
);

const parsers = .{
    .GLFWApi = clap.parsers.enumeration(glfw.Platform),
};

const ClapParseResult = clap.Result(clap.Help, &clap_params, parsers);

pub fn parse() void {
    clap_options = parseCommandLine() catch |err| {
        std.debug.assert(err == error.InvalidCommandLine);
        std.process.exit(1);
    };
    if (clap_options.help) std.process.exit(0);
}

fn parseCommandLine() !ClapOptions {
    const printErr = struct {
        pub fn f(comptime fmt: []const u8, args: anytype) void {
            const w = std.io.getStdErr().writer();
            w.print(fmt, args) catch {};
            w.print("\n", .{}) catch {};
        }
    }.f;

    const usage = struct {
        pub fn f(writer: anytype, exe_name: []const u8) void {
            writer.print("Usage: {s} ", .{exe_name}) catch {};
            clap.usage(writer, clap.Help, &clap_params) catch {};
            writer.print("\n", .{}) catch {};
        }
    }.f;

    const help = struct {
        pub fn f(writer: anytype, exe_name: []const u8) void {
            usage(writer, exe_name);
            clap.help(writer, clap.Help, &clap_params, .{}) catch {};
        }
    }.f;

    // TODO(allocator): Use temporary allocator
    var arg_it = try std.process.ArgIterator.initWithAllocator(alloc.gpa);
    defer arg_it.deinit();

    const exe_name = std.fs.path.basename(arg_it.next().?);
    var diag = clap.Diagnostic{};
    var result = clap.parseEx(clap.Help, &clap_params, parsers, &arg_it, .{
        .diagnostic = &diag,
        // TODO(allocator): Use temporary allocator
        .allocator = alloc.gpa,
    }) catch |err| {
        const err_args = diag.name.longest();
        const prefix = switch (err_args.kind) {
            .positional => "",
            .short => "-",
            .long => "--",
        };
        const msg_args = .{ prefix, err_args.name };

        switch (err) {
            else => printErr("Error while parsing argument: {s}", .{@errorName(err)}),
            error.InvalidArgument => printErr("Invalid argument: '{s}{s}'", msg_args),
            error.MissingValue => printErr("Expected value for argument: '{s}{s}'", msg_args),
            error.DoesntTakeValue => printErr("Argument '{s}{s}', doesn't take value", msg_args),
        }

        usage(std.io.getStdErr().writer(), exe_name);
        return error.InvalidCommandLine;
    };
    defer result.deinit();

    if (result.args.help != 0) {
        help(std.io.getStdOut().writer(), exe_name);
    }

    const default = ClapOptions{};
    return .{
        .help = result.args.help != 0,
        .glfw_platform = result.args.@"glfw-platform" orelse default.glfw_platform,
    };
}
