const std = @import("std");
const Allocator = std.mem.Allocator;

const clip = @import("clip");

var gpa: Allocator = undefined;
var arena: Allocator = undefined;
var io: std.Io = undefined;

const OptionParser = clip.OptionParser("asset_compiler", &.{
    clip.option(@as([]const u8, ""), "input_scan_dir", 'i', "Directory to scan for input files"),
    clip.option(@as([]const u8, ""), "output_dir", 'o', "Output directory"),
});

var stderr_buf: [2048]u8 = undefined;
var stderr_writer: std.Io.File.Writer = undefined;

var stdout_buf: [2048]u8 = undefined;
var stdout_writer: std.Io.File.Writer = undefined;

pub fn main(init: std.process.Init) !u8 {
    io = init.io;
    gpa = init.gpa;
    arena = init.arena.allocator();
    defer _ = init.arena.reset(.free_all);

    stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buf);
    defer stderr_writer.flush() catch unreachable;

    stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    defer stdout_writer.flush() catch unreachable;

    run(init) catch return 1;
    return 0;
}

pub fn run(init: std.process.Init) !void {
    const cwd = try std.process.currentPathAlloc(io, arena);

    var raw_arg_arena = std.heap.ArenaAllocator.init(gpa);
    const raw_args = try init.minimal.args.toSlice(raw_arg_arena.allocator());

    const args = OptionParser.parse(raw_args[1..], arena, &stderr_writer.interface) catch |e| switch (e) {
        error.OutOfMemory => @panic("OOM"),
        else => {
            try OptionParser.usage(&stderr_writer.interface);
            _ = raw_arg_arena.reset(.free_all);
            return error.ArgParseError;
        },
    };
    _ = raw_arg_arena.deinit();

    if (args.input_scan_dir.len == 0) {
        try stdout_writer.interface.print("error: missing argument 'input_scan_dir'\n", .{});
        try OptionParser.usage(&stdout_writer.interface);
        return error.MissingInputScanDir;
    }

    if (args.output_dir.len == 0) {
        try stdout_writer.interface.print("error: missing argument 'output_dir'\n", .{});
        try OptionParser.usage(&stdout_writer.interface);
        return error.MissingOutputDir;
    }

    var scan_path: []const u8 = "";
    const scan_dir = dir: {
        if (std.fs.path.isAbsolute(args.input_scan_dir)) {
            scan_path = copy(args.input_scan_dir);
        } else {
            scan_path = try std.fs.path.resolve(arena, &.{ cwd, args.input_scan_dir });
        }

        break :dir std.Io.Dir.cwd().openDir(io, args.input_scan_dir, .{ .iterate = true }) catch |e| {
            std.log.err("Unable to open input dir '{s}'", .{scan_path});
            std.log.err("{s}", .{@errorName(e)});
            return error.InvalidInputScanDir;
        };
    };
    errdefer scan_dir.close(io);

    var output_dir_path: []const u8 = "";
    const output_dir = dir: {
        if (std.fs.path.isAbsolute(args.output_dir)) {
            output_dir_path = copy(args.output_dir);
        } else {
            output_dir_path = try std.fs.path.resolve(arena, &.{ cwd, args.output_dir });
        }

        // TODO: Consider creating the directory if it does not exist
        break :dir std.Io.Dir.cwd().openDir(io, args.output_dir, .{ .iterate = true }) catch |e| {
            std.log.err("Unable to open input dir '{s}'", .{output_dir_path});
            std.log.err("{s}", .{@errorName(e)});
            return error.InvalidOutputDir;
        };
    };
    errdefer output_dir.close(io);

    std.log.debug("input_scan_dir: '{s}'", .{scan_path});
    std.log.debug("output_dir: '{s}'", .{args.output_dir});

    // Relative to scan_path
    var relative_input_paths: std.ArrayList([]const u8) = .empty;

    var walker = try scan_dir.walk(gpa);
    while (try walker.next(io)) |entry| {
        if (entry.kind == .file) {
            if (std.mem.eql(u8, ".aseprite", std.fs.path.extension(entry.basename))) {
                const input_path = try arena.dupe(u8, entry.path);
                try relative_input_paths.append(gpa, input_path);
            }
        }
    }
    walker.deinit();

    scan_dir.close(io);

    for (relative_input_paths.items) |relative_input_path| {
        std.log.debug("", .{});
        std.log.debug("input file: {s}", .{relative_input_path});

        const input_path = try std.fs.path.join(gpa, &.{ scan_path, relative_input_path });
        defer gpa.free(input_path);

        const tags = try asepriteTags(gpa, input_path);
        defer {
            for (tags) |t| gpa.free(t);
            gpa.free(tags);
        }

        var skip = false;
        var split_layers = false;
        for (tags) |t| {
            if (std.mem.eql(u8, "skip", t))
                skip = true
            else if (std.mem.eql(u8, "split_layers", t))
                split_layers = true;
        }

        if (!skip and !split_layers) {
            const output_files: []const []const u8 = if (split_layers) {
                unreachable;
            } else blk: {
                const out_file_name = try std.fmt.allocPrint(gpa, "{s}.bmp", .{std.fs.path.stem(relative_input_path)});
                defer gpa.free(out_file_name);

                const output_file = try std.fs.path.join(gpa, &.{
                    output_dir_path,
                    std.fs.path.dirname(relative_input_path) orelse "",
                    out_file_name,
                });
                break :blk &.{output_file};
            };

            for (output_files) |output_file| {
                std.log.debug("output file: {s}", .{output_file});
                if (!split_layers) {
                    try asepriteExportBMP(input_path, output_file);
                }
            }

            for (output_files) |of| gpa.free(of);
            if (split_layers) gpa.free(output_files);
        }
    }

    relative_input_paths.deinit(gpa);
    output_dir.close(io);
}

pub fn copy(str: []const u8) []const u8 {
    const result = arena.alloc(u8, str.len) catch @panic("OOM");
    @memcpy(result, str);
    return result;
}

pub const RunResult = struct {
    allocator: Allocator,
    exit_code: u8,
    stdout: []const u8,

    pub fn free(this: *RunResult) void {
        this.allocator.free(this.stdout);
    }
};

pub const RunError = std.process.RunError || error{};

pub fn aseprite(allocator: Allocator, args: []const []const u8) !RunResult {
    const argv = try allocator.alloc([]const u8, args.len + 1);
    defer allocator.free(argv);

    argv[0] = "aseprite";
    @memcpy(argv[1..], args);

    for (argv, 0..) |a, i| {
        if (i > 0) try stdout_writer.interface.writeByte(' ');
        try stdout_writer.interface.writeAll(a);
    }
    try stdout_writer.interface.writeByte('\n');
    try stdout_writer.flush();

    const rr = try std.process.run(allocator, io, .{ .argv = argv });
    defer allocator.free(rr.stderr);

    switch (rr.term) {
        .exited => |ec| {
            var exit_code = ec;
            if (std.mem.startsWith(u8, rr.stdout, "File not found:")) {
                exit_code = 1;
            }

            if (exit_code != 0) {
                std.log.err("asprite stdout:\n{s}", .{rr.stdout});
                std.log.err("asprite stderr:\n{s}", .{rr.stderr});
            }
            return .{ .allocator = allocator, .exit_code = exit_code, .stdout = rr.stdout };
        },
        .signal => return error.UnexpectedRunSignal,
        .stopped => return error.RunStopped,
        .unknown => return error.UnknownRunError,
    }
}

pub fn asepriteTags(allocator: Allocator, input_path: []const u8) ![]const []const u8 {
    var tags_rr = try aseprite(gpa, &.{ "-b", "--list-tags", input_path });
    defer tags_rr.free();

    if (tags_rr.exit_code != 0) {
        std.log.err("Asprite invocation failed", .{});
        return error.AsepriteNonZeroExitCode;
    }

    var tags: std.ArrayList([]const u8) = .empty;

    var line_it = std.mem.splitScalar(u8, tags_rr.stdout, '\n');
    while (line_it.next()) |tag| if (tag.len > 0) {
        const t = try allocator.dupe(u8, tag);
        try tags.append(allocator, t);
    };

    return tags.toOwnedSlice(allocator);
}

pub fn asepriteExportBMP(input_path: []const u8, output_path: []const u8) !void {
    var export_rr = try aseprite(gpa, &.{ "-b", input_path, "--save-as", output_path });
    defer export_rr.free();

    if (export_rr.exit_code != 0) {
        std.log.err("Asprite invocation failed", .{});
        return error.AsepriteNonZeroExitCode;
    }
}
