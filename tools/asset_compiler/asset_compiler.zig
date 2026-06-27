const std = @import("std");
const log = std.log.scoped(.asset_compiler);
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");

const compile_options = @import("options");
const clip = @import("clip");

const OptionParser = clip.OptionParser("asset_compiler", &.{
    clip.option(@as([]const u8, ""), "input_scan_dir", 'i', "Directory to scan for input files"),
    clip.option(@as([]const u8, ""), "output_dir", 'o', "Output directory"),
    clip.option(false, "verbose", 'v', "Verbose outout"),
});

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,
    arena: Allocator,

    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,

    verbose: bool = false,
};

var total_aseprite_time: std.Io.Duration = .zero;

pub fn main(init: std.process.Init) !u8 {
    var stderr_buf: [2048]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buf);

    var stdout_buf: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    defer {
        stderr_writer.flush() catch {};
        stdout_writer.flush() catch {};
    }

    var arg_arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arg_arena.deinit();

    const raw_args = try init.minimal.args.toSlice(arg_arena.allocator());

    const context_arena = init.arena.allocator();

    const args = OptionParser.parse(raw_args[1..], context_arena, &stderr_writer.interface) catch |e| switch (e) {
        error.OutOfMemory => @panic("OOM"),
        else => {
            try OptionParser.usage(&stderr_writer.interface);
            return error.ArgParseError;
        },
    };

    if (args.input_scan_dir.len == 0) {
        try stderr_writer.interface.print("error: missing argument 'input_scan_dir'\n", .{});
        try OptionParser.usage(&stderr_writer.interface);
        return error.MissingInputScanDir;
    }

    if (args.output_dir.len == 0) {
        try stderr_writer.interface.print("error: missing argument 'output_dir'\n", .{});
        try OptionParser.usage(&stderr_writer.interface);
        return error.MissingOutputDir;
    }

    const context = Context{
        .io = init.io,
        .gpa = init.gpa,
        .arena = init.arena.allocator(),
        .stdout = &stdout_writer.interface,
        .stderr = &stderr_writer.interface,
        .verbose = args.verbose,
    };

    run(&context, args) catch return 1;
    return 0;
}

pub fn run(context: *const Context, options: OptionParser.Options) !void {
    const start_time = std.Io.Timestamp.now(context.io, .real);

    const cwd = try std.process.currentPathAlloc(context.io, context.arena);

    var scan_path: []const u8 = "";
    const scan_dir = dir: {
        if (std.fs.path.isAbsolute(options.input_scan_dir)) {
            scan_path = try context.arena.dupe(u8, options.input_scan_dir);
        } else {
            scan_path = try std.fs.path.resolve(context.arena, &.{ cwd, options.input_scan_dir });
        }

        break :dir std.Io.Dir.cwd().openDir(context.io, options.input_scan_dir, .{ .iterate = true }) catch |e| {
            std.log.err("Unable to open input dir '{s}'", .{scan_path});
            std.log.err("{s}", .{@errorName(e)});
            return error.InvalidInputScanDir;
        };
    };
    errdefer scan_dir.close(context.io);

    var output_dir_path: []const u8 = "";
    const output_dir = dir: {
        if (std.fs.path.isAbsolute(options.output_dir)) {
            output_dir_path = try context.arena.dupe(u8, options.output_dir);
        } else {
            output_dir_path = try std.fs.path.resolve(context.arena, &.{ cwd, options.output_dir });
        }

        // TODO: Consider creating the directory if it does not exist
        break :dir std.Io.Dir.cwd().openDir(context.io, options.output_dir, .{ .iterate = true }) catch |e| {
            std.log.err("Unable to open input dir '{s}'", .{output_dir_path});
            std.log.err("{s}", .{@errorName(e)});
            return error.InvalidOutputDir;
        };
    };
    errdefer output_dir.close(context.io);

    log.debug("input_scan_dir: '{s}'", .{scan_path});
    log.debug("output_dir: '{s}'", .{output_dir_path});

    // Relative to scan_path
    var relative_input_paths: std.ArrayList([]const u8) = .empty;
    var input_timestamps: std.ArrayList(std.Io.Timestamp) = .empty;

    var walker = try scan_dir.walk(context.gpa);
    while (try walker.next(context.io)) |entry| {
        if (entry.kind == .file) {
            if (std.mem.eql(u8, ".aseprite", std.fs.path.extension(entry.basename))) {
                const input_path = try context.arena.dupe(u8, entry.path);
                try relative_input_paths.append(context.arena, input_path);

                const stat = try scan_dir.statFile(context.io, entry.path, .{});
                try input_timestamps.append(context.arena, stat.mtime);
            }
        }
    }
    walker.deinit();

    scan_dir.close(context.io);

    for (relative_input_paths.items, input_timestamps.items) |relative_input_path, input_timestamp| {
        log.debug("", .{});
        log.debug("classify input file: {s}", .{relative_input_path});

        const abs_input_path = try std.fs.path.join(context.gpa, &.{ scan_path, relative_input_path });
        defer context.gpa.free(abs_input_path);

        const tags = try asepriteTags(context, context.gpa, abs_input_path);
        defer {
            for (tags) |t| context.gpa.free(t);
            context.gpa.free(tags);
        }

        var tag_skip = false;
        var tag_split_layers = false;
        for (tags) |t| {
            if (std.mem.eql(u8, "skip", t))
                tag_skip = true
            else if (std.mem.eql(u8, "split_layers", t))
                tag_split_layers = true;
        }

        log.debug("classification: skip:{} split_layers:{}", .{ tag_skip, tag_split_layers });

        if (!tag_skip) {
            const rel_dir_path = std.fs.path.dirname(relative_input_path) orelse "";

            const abs_output_file_path_opt: ?[]const u8 = if (tag_split_layers) blk: {
                const layers = try asepriteLayers(context, context.gpa, abs_input_path);
                defer {
                    for (layers) |l| context.gpa.free(l);
                    context.gpa.free(layers);
                }

                const output_prefix = std.fs.path.stem(relative_input_path);

                for (layers) |l| {
                    const out_file_name = try std.fmt.allocPrint(context.gpa, "{s}_{s}.bmp", .{ output_prefix, l });
                    defer context.gpa.free(out_file_name);

                    const abs_file_path = try std.fs.path.join(context.gpa, &.{ output_dir_path, rel_dir_path, out_file_name });
                    errdefer context.gpa.free(abs_file_path);

                    const status = try outputFileStatus(context, abs_file_path, input_timestamp);
                    switch (status) {
                        .missing, .outOfDate => break :blk abs_file_path,
                        .upToDate => context.gpa.free(abs_file_path),
                    }
                }

                break :blk null;
            } else blk: {
                const out_file_name = try std.fmt.allocPrint(context.gpa, "{s}.bmp", .{std.fs.path.stem(relative_input_path)});
                defer context.gpa.free(out_file_name);

                const abs_file_path = try std.fs.path.join(context.gpa, &.{ output_dir_path, rel_dir_path, out_file_name });
                errdefer context.gpa.free(abs_file_path);

                const status = try outputFileStatus(context, abs_file_path, input_timestamp);

                switch (status) {
                    .missing, .outOfDate => break :blk abs_file_path,
                    .upToDate => {
                        context.gpa.free(abs_file_path);
                        break :blk null;
                    },
                }
            };

            if (abs_output_file_path_opt) |abs_output_path| {
                log.debug("emit for: {s}", .{abs_input_path});
                if (!tag_split_layers) {
                    try asepriteExportBMP(context, abs_input_path, abs_output_path);
                } else {
                    try asepriteExportSplitLayerBMP(context, abs_input_path, output_dir_path);
                }

                context.gpa.free(abs_output_path);
            } else {
                log.debug("skip emit for: {s}", .{abs_input_path});
            }
        }
    }

    output_dir.close(context.io);

    const total_time = start_time.untilNow(context.io, .real);
    log.info("aseprite time: {f}", .{total_aseprite_time});
    log.info("total time   : {f}", .{total_time});
}

pub const OutputFileStatus = enum(u2) {
    missing,
    outOfDate,
    upToDate,
};

pub fn outputFileStatus(context: *const Context, abs_path: []const u8, input_timestamp: std.Io.Timestamp) !OutputFileStatus {
    assert(std.fs.path.isAbsolute(abs_path));

    log.debug("checking output file: {s}", .{abs_path});

    const result: OutputFileStatus = if (std.Io.Dir.statFile(undefined, context.io, abs_path, .{})) |stat|
        if (stat.mtime.nanoseconds <= input_timestamp.nanoseconds)
            .outOfDate
        else
            .upToDate
    else |_|
        .missing;

    log.debug("status: {s}", .{@tagName(result)});
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

pub fn aseprite(context: *const Context, allocator: Allocator, args: []const []const u8) !RunResult {
    const argv = try allocator.alloc([]const u8, args.len + 1);
    defer allocator.free(argv);

    argv[0] = compile_options.aseprite_exe_path;
    @memcpy(argv[1..], args);

    if (context.verbose) {
        for (argv, 0..) |a, i| {
            if (i > 0) try context.stdout.writeByte(' ');
            try context.stdout.writeAll(a);
        }
    }

    const start_time = std.Io.Timestamp.now(context.io, .real);
    const result_or_err = std.process.run(allocator, context.io, .{ .argv = argv });
    const duration = start_time.untilNow(context.io, .real);
    total_aseprite_time.nanoseconds += duration.nanoseconds;

    if (context.verbose) {
        try context.stdout.print(" ({f})\n", .{duration});
        try context.stdout.flush();
    }

    const result = try result_or_err;

    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |ec| {
            var exit_code = ec;
            if (std.mem.startsWith(u8, result.stdout, "File not found:")) {
                exit_code = 1;
            }

            if (exit_code != 0) {
                std.log.err("asprite stdout:\n{s}", .{result.stdout});
                std.log.err("asprite stderr:\n{s}", .{result.stderr});
            }
            return .{ .allocator = allocator, .exit_code = exit_code, .stdout = result.stdout };
        },
        .signal => return error.UnexpectedRunSignal,
        .stopped => return error.RunStopped,
        .unknown => return error.UnknownRunError,
    }
}

pub fn asepriteTags(context: *const Context, allocator: Allocator, abs_input_path: []const u8) ![]const []const u8 {
    assert(std.fs.path.isAbsolute(abs_input_path));

    var tags_rr = try aseprite(context, context.gpa, &.{ "-b", "--list-tags", abs_input_path });
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
pub fn asepriteLayers(context: *const Context, allocator: Allocator, abs_input_path: []const u8) ![]const []const u8 {
    assert(std.fs.path.isAbsolute(abs_input_path));

    var layers_rr = try aseprite(context, context.gpa, &.{ "-b", "--all-layers", "--list-layer-hierarchy", abs_input_path });
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
    defer stack.deinit(context.gpa);

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
                try stack.append(context.gpa, layer_name[indent * 2 ..]);
            } else {
                const folder = try std.mem.concat(context.gpa, u8, stack.items);
                defer context.gpa.free(folder);
                std.mem.replaceScalar(u8, folder, '/', '_');

                const full_layer_name = try std.mem.concat(allocator, u8, &.{ folder, layer_name[indent * 2 ..] });
                try layers.append(allocator, full_layer_name);
            }
        }
    }

    return layers.toOwnedSlice(allocator);
}

pub fn asepriteExportBMP(context: *const Context, abs_input_path: []const u8, abs_output_path: []const u8) !void {
    assert(std.fs.path.isAbsolute(abs_input_path));
    assert(std.fs.path.isAbsolute(abs_output_path));

    var export_rr = try aseprite(context, context.gpa, &.{ "-b", abs_input_path, "--save-as", abs_output_path });
    defer export_rr.free();

    if (export_rr.exit_code != 0) {
        std.log.err("Asprite invocation failed", .{});
        return error.AsepriteNonZeroExitCode;
    }
}

pub fn asepriteExportSplitLayerBMP(context: *const Context, abs_input_path: []const u8, abs_output_dir_path: []const u8) !void {
    assert(std.fs.path.isAbsolute(abs_input_path));
    assert(std.fs.path.isAbsolute(abs_output_dir_path));

    const out_dir_param = try std.fmt.allocPrint(context.gpa, "out_dir={s}", .{abs_output_dir_path});
    defer context.gpa.free(out_dir_param);

    const script_path = try std.fs.path.join(context.gpa, &.{ compile_options.aseprite_script_path, "extract_layers_recursive.lua" });
    defer context.gpa.free(script_path);

    var export_rr = try aseprite(context, context.gpa, &.{
        "-b",
        abs_input_path,
        "--script-param",
        out_dir_param,
        "--script",
        script_path,
    });
    defer export_rr.free();

    if (export_rr.exit_code != 0) {
        std.log.err("Asprite invocation failed", .{});
        return error.AsepriteNonZeroExitCode;
    }
}
