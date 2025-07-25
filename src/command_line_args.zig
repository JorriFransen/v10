const std = @import("std");
const mem = @import("memory");
const clap = @import("clap");
const glfw = @import("glfw");

const ClapOptions = struct {
    glfw_platform: glfw.Platform = .any,
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
            const w = std.fs.File.stderr().deprecatedWriter();
            w.print(fmt, args) catch {};
            w.print("\n", .{}) catch {};
        }
    }.f;

    const usage = struct {
        pub fn f(writer: anytype, exe_name: []const u8) void {
            var adapter = writer.adaptToNewApi();
            writer.print("Usage: {s} ", .{exe_name}) catch {};
            clap.usage(&adapter.new_interface, clap.Help, &clap_params) catch {};
            writer.print("\n", .{}) catch {};
        }
    }.f;

    const help = struct {
        pub fn f(writer: anytype, exe_name: []const u8) void {
            var adapter = writer.adaptToNewApi();
            usage(writer, exe_name);
            clap.help(&adapter.new_interface, clap.Help, &clap_params, .{}) catch {};
        }
    }.f;

    var tmp = mem.get_temp();
    defer tmp.release();

    var arg_it = try std.process.ArgIterator.initWithAllocator(tmp.allocator());

    const exe_name = std.fs.path.basename(arg_it.next().?);
    var diag = clap.Diagnostic{};
    var result = clap.parseEx(clap.Help, &clap_params, parsers, &arg_it, .{
        .diagnostic = &diag,
        .allocator = tmp.allocator(),
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

        usage(std.fs.File.stderr().deprecatedWriter(), exe_name);
        return error.InvalidCommandLine;
    };
    defer result.deinit();

    if (result.args.help != 0) {
        help(std.fs.File.stdout().deprecatedWriter(), exe_name);
    }

    const default = ClapOptions{};
    return .{
        .help = result.args.help != 0,
        .glfw_platform = result.args.@"glfw-platform" orelse default.glfw_platform,
    };
}
