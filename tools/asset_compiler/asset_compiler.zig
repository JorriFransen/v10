const std = @import("std");
const assert = std.debug.assert;
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
            scan_path = try arena.dupe(u8, args.input_scan_dir);
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
            output_dir_path = try arena.dupe(u8, args.output_dir);
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

        if (!skip) {
            const output_files: []const []const u8 = if (split_layers) {
                const layers = try asepriteLayers(gpa, input_path);
                defer {
                    for (layers) |l| gpa.free(l);
                    gpa.free(layers);
                }

                for (layers) |l| {
                    std.log.debug("layer: '{s}'", .{l});
                }

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

            if (!split_layers) {
                assert(output_files.len == 1);
                std.log.debug("output file: {s}", .{output_files[0]});
                try asepriteExportBMP(input_path, output_files[0]);
            } else {
                unreachable;
            }

            for (output_files) |of| gpa.free(of);
            if (split_layers) gpa.free(output_files);
        }
    }

    relative_input_paths.deinit(gpa);
    output_dir.close(io);
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
    errdefer {
        for (tags.items) |t| allocator.free(t);
        tags.deinit(allocator);
    }

    var line_it = std.mem.splitScalar(u8, tags_rr.stdout, '\n');
    while (line_it.next()) |line| {
        const tag = std.mem.trimEnd(u8, line, "\r");
        if (tag.len > 0) {
            const t = try allocator.dupe(u8, tag);
            try tags.append(allocator, t);
        }
    }

    return tags.toOwnedSlice(allocator);
}

// Flattens the hierarchy, replacing / with -
pub fn asepriteLayers(allocator: Allocator, input_path: []const u8) ![]const []const u8 {
    var layers_rr = try aseprite(gpa, &.{ "-b", "--all-layers", "--list-layer-hierarchy", input_path });
    defer layers_rr.free();

    if (layers_rr.exit_code != 0) {
        std.log.err("Asprite invocation failed", .{});
        return error.AsepriteNonZeroExitCode;
    }

    var layers: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (layers.items) |l| allocator.free(l);
        layers.deinit(allocator);
    }

    var stack: std.ArrayList([]const u8) = .empty;
    defer stack.deinit(gpa);

    var line_it = std.mem.splitScalar(u8, layers_rr.stdout, '\n');
    while (line_it.next()) |line| {
        const layer_name = std.mem.trimEnd(u8, line, "\r");

        if (layer_name.len > 0) {
            var indent: usize = 0;
            for (layer_name) |c| {
                if (c != ' ') break;
                indent += 1;
            }
            assert(indent % 2 == 0);
            indent /= 2;

            while (indent < stack.items.len) {
                _ = stack.pop();
            }

            if (layer_name[layer_name.len - 1] == '/') {
                try stack.append(gpa, layer_name[indent * 2 ..]);
            } else {
                const folder = try std.mem.concat(gpa, u8, stack.items);
                defer gpa.free(folder);
                std.mem.replaceScalar(u8, folder, '/', '_');

                const full_layer_name = try std.mem.concat(allocator, u8, &.{ folder, layer_name[indent * 2 ..] });
                try layers.append(allocator, full_layer_name);
            }
        }
    }

    return layers.toOwnedSlice(allocator);
}

pub fn asepriteExportBMP(input_path: []const u8, output_path: []const u8) !void {
    var export_rr = try aseprite(gpa, &.{ "-b", input_path, "--save-as", output_path });
    defer export_rr.free();

    if (export_rr.exit_code != 0) {
        std.log.err("Asprite invocation failed", .{});
        return error.AsepriteNonZeroExitCode;
    }
}
