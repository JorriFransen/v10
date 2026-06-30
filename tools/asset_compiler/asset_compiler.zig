const std = @import("std");
const log = std.log.scoped(.asset_compiler);
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");

const mem = @import("mem");

const compile_options = @import("options");
const clip = @import("clip");

// Note: If any of these functions start making "temporary" allocations they need
//        to be wrapped like 'pathResolve'.
const pathJoin = std.fs.path.join;
const extension = std.fs.path.extension;
const dirname = std.fs.path.dirname;
const stem = std.fs.path.stem;
const pathIsAbsolute = std.fs.path.isAbsolute;

const OptionParser = clip.OptionParser("asset_compiler", &.{
    clip.option(@as([]const u8, ""), "input_scan_dir", 'i', "Directory to scan for input files"),
    clip.option(@as([]const u8, ""), "output_dir", 'o', "Output directory"),
    clip.option(@as([]const u8, ".timestamps"), "timestamp_file_path", 't', "Timestamp file path relative to output_dir"),
    clip.option(false, "verbose", 'v', "Verbose outout"),
});

pub const Context = struct {
    io: std.Io,
    arena: Allocator,
    gpa: Allocator,

    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,

    verbose: bool = false,

    scan_dir_path: []const u8 = undefined,
    output_dir_path: []const u8 = undefined,
};

var total_aseprite_time: std.Io.Duration = .zero;

var timestamp_file_buf: [4096]u8 = undefined;

pub fn main(init: std.process.Init) !u8 {
    mem.init();
    defer mem.deinit();

    var stderr_buf: [2048]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buf);

    var stdout_buf: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    defer {
        stderr_writer.flush() catch {};
        stdout_writer.flush() catch {};
    }

    var arena_data = try mem.Arena.init(.{ .virtual = .{} });
    const arena = arena_data.allocator();

    const args: OptionParser.Options = blk: {
        var arg_tmp = mem.getScratch(arena);
        defer arg_tmp.release();

        const raw_args = try init.minimal.args.toSlice(arg_tmp.a);
        break :blk OptionParser.parse(
            raw_args[1..],
            arena,
            arg_tmp.a,
            &stderr_writer.interface,
        ) catch |e| switch (e) {
            error.OutOfMemory => @panic("OOM"),
            else => {
                try OptionParser.usage(&stderr_writer.interface);
                return error.ArgParseError;
            },
        };
    };

    var context = Context{
        .io = init.io,
        .arena = arena,
        .gpa = init.gpa,
        .stdout = &stdout_writer.interface,
        .stderr = &stderr_writer.interface,
        .verbose = args.verbose,
    };

    run(&context, args) catch return 1;
    return 0;
}

pub fn run(context: *Context, options: OptionParser.Options) !void {
    const start_time = std.Io.Timestamp.now(context.io, .real);

    if (options.input_scan_dir.len == 0) {
        try context.stderr.print("error: missing argument 'input_scan_dir'\n", .{});
        try OptionParser.usage(context.stderr);
        return error.MissingInputScanDir;
    }

    if (options.output_dir.len == 0) {
        try context.stderr.print("error: missing argument 'output_dir'\n", .{});
        try OptionParser.usage(context.stderr);
        return error.MissingOutputDir;
    }

    const cwd = try std.process.currentPathAlloc(context.io, context.arena);

    const scan_dir = dir: {
        if (pathIsAbsolute(options.input_scan_dir)) {
            context.scan_dir_path = try context.arena.dupe(u8, options.input_scan_dir);
        } else {
            context.scan_dir_path = try pathResolve(context.arena, &.{ cwd, options.input_scan_dir });
        }

        break :dir std.Io.Dir.cwd().openDir(context.io, options.input_scan_dir, .{ .iterate = true }) catch |e| {
            std.log.err("Unable to open input dir '{s}'", .{context.scan_dir_path});
            std.log.err("{s}", .{@errorName(e)});
            return error.InvalidInputScanDir;
        };
    };
    errdefer scan_dir.close(context.io);

    const output_dir = dir: {
        if (pathIsAbsolute(options.output_dir)) {
            context.output_dir_path = try context.arena.dupe(u8, options.output_dir);
        } else {
            context.output_dir_path = try pathResolve(context.arena, &.{ cwd, options.output_dir });
        }

        // TODO: Consider creating the directory if it does not exist
        break :dir std.Io.Dir.cwd().openDir(context.io, options.output_dir, .{ .iterate = true }) catch |e| {
            std.log.err("Unable to open input dir '{s}'", .{context.output_dir_path});
            std.log.err("{s}", .{@errorName(e)});
            return error.InvalidOutputDir;
        };
    };
    errdefer output_dir.close(context.io);

    log.debug("input_scan_dir: '{s}'", .{context.scan_dir_path});
    log.debug("output_dir: '{s}'", .{context.output_dir_path});

    var tmp = mem.getScratch(context.arena);
    defer tmp.release();

    var ts_file_opt = try readTimestampFile(context, &output_dir, options.timestamp_file_path);
    defer if (ts_file_opt) |*ts_file| ts_file.deinit(context);

    const input_files = try collectInputFiles(context, context.arena, &scan_dir, context.scan_dir_path);
    scan_dir.close(context.io);

    var files_to_compile: std.ArrayList(*InputFile) = .empty;
    defer files_to_compile.deinit(context.gpa);

    var all_output_files: std.StringHashMapUnmanaged(void) = .empty;
    defer all_output_files.deinit(context.gpa);

    if (ts_file_opt) |ts_file| {
        for (input_files) |*input_file| {
            if (ts_file.timestamp.nanoseconds <= input_file.timestamp.nanoseconds) {
                try files_to_compile.append(context.gpa, input_file);
            } else if (ts_file.outputs_per_input.get(input_file.path)) |old_output_files| {
                const up_to_date = blk: {
                    for (old_output_files) |output_file_path| {
                        const status = try outputFileStatus(context, &output_dir, output_file_path, input_file.timestamp);
                        switch (status) {
                            .missing, .outOfDate => break :blk false,
                            .upToDate => {},
                        }
                    }
                    break :blk true;
                };

                if (up_to_date) {
                    if (old_output_files.len == 0) {
                        verbose(context, "skipping: {s}", .{input_file.abs_path});
                    }
                    input_file.outputs = old_output_files;

                    for (old_output_files) |output_file_path| {
                        try all_output_files.putNoClobber(context.gpa, output_file_path, undefined);
                    }
                } else {
                    try files_to_compile.append(context.gpa, input_file);
                }
            }
        }
    } else {
        for (input_files) |*input_file| {
            try files_to_compile.append(context.gpa, input_file);
        }
    }

    for (files_to_compile.items) |input_file| {
        log.debug("", .{});

        tmp.release();

        const tags = try asepriteTags(context, tmp.a, input_file.abs_path);

        // TODO: Do this while parsing tags in fn asepriteTags()
        var tag_skip = false;
        var tag_split_layers = false;

        if (input_file.skip) {
            tag_skip = true;
        } else {
            for (tags) |t| {
                if (std.mem.eql(u8, "skip", t))
                    tag_skip = true
                else if (std.mem.eql(u8, "split_layers", t))
                    tag_split_layers = true;
            }
        }

        var output_file_paths: []const []const u8 = &.{};

        if (!tag_skip) {
            verbose(context, "compiling: {s}", .{input_file.abs_path});

            const rel_dir_path = dirname(input_file.path) orelse "";

            output_file_paths = if (tag_split_layers) blk: {
                const layers = try asepriteLayers(context, tmp.a, input_file.abs_path);

                const output_filename_prefix = stem(input_file.path);

                const result = try context.arena.alloc([]const u8, layers.len);

                for (layers, result) |l, *output_file_name| {
                    const name = try mem.arenaAllocPrint(tmp.a, "{s}_{s}.bmp", .{ output_filename_prefix, l });
                    output_file_name.* = try pathJoin(context.arena, &.{ rel_dir_path, name });
                }

                const abs_out_dir = try pathJoin(tmp.a, &.{ context.output_dir_path, rel_dir_path });
                try asepriteExportSplitLayerBMP(context, input_file.abs_path, abs_out_dir);

                break :blk result;
            } else blk: {
                const out_file_name = try std.fmt.allocPrint(tmp.a, "{s}.bmp", .{stem(input_file.path)});
                const rel_out_path = try pathJoin(context.arena, &.{ rel_dir_path, out_file_name });
                const abs_file_path = try pathJoin(tmp.a, &.{ context.output_dir_path, rel_out_path });

                try asepriteExportBMP(context, input_file.abs_path, abs_file_path);
                break :blk try context.arena.dupe([]const u8, &.{rel_out_path});
            };
        } else {
            log.info("skipping: {s}", .{input_file.abs_path});
        }

        input_file.outputs = output_file_paths;
        for (output_file_paths) |ofp| {
            try all_output_files.putNoClobber(context.gpa, ofp, undefined);
            log.debug(" output file: {s}", .{ofp});
        }
    }

    try writeTimestampFile(context, &output_dir, options.timestamp_file_path, input_files);

    // TODO: Attempt to remove any file in the output dir that's missing from all_output_files

    output_dir.close(context.io);

    const total_time = start_time.untilNow(context.io, .real);
    verbose(context, "aseprite time: {f}", .{total_aseprite_time});
    verbose(context, "total time   : {f}", .{total_time});
}

pub const TimestampFile = struct {
    timestamp: std.Io.Timestamp,
    outputs_per_input: std.StringHashMapUnmanaged([]const []const u8),

    pub fn deinit(this: *TimestampFile, context: *const Context) void {
        this.outputs_per_input.deinit(context.gpa);
    }
};

fn readTimestampFile(context: *const Context, output_dir: *const std.Io.Dir, rel_path: []const u8) !?TimestampFile {
    var tmp = mem.getScratch(context.arena);
    defer tmp.release();

    const timestamp: std.Io.Timestamp = if (output_dir.statFile(context.io, rel_path, .{})) |stat|
        stat.mtime
    else |_| {
        verbose(context, "missing timestamp file, compile everything", .{});
        return null;
    };

    var outputs_per_input: std.StringHashMapUnmanaged([]const []const u8) = .empty;

    verbose(context, "reading timestamp file", .{});

    if (output_dir.openFile(context.io, rel_path, .{})) |timestamp_file| {
        defer timestamp_file.close(context.io);

        var file_reader = timestamp_file.reader(context.io, &timestamp_file_buf);
        const reader = &file_reader.interface;

        const timestamp_file_content_size = try file_reader.getSize();
        const timestamp_file_content = try tmp.a.alloc(u8, timestamp_file_content_size);
        defer tmp.release();

        try reader.readSliceAll(timestamp_file_content);

        var line_it = std.mem.splitScalar(u8, timestamp_file_content, '\n');

        var current_input: ?[]const u8 = null;
        var current_outputs: std.ArrayList([]const u8) = .empty;

        while (line_it.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, "\r");
            if (line.len > 0) {
                if (!(line[0] == 'i' or line[0] == 'o') or line[1] != ':') {
                    log.err("Invalid line in timestamp file: '{s}'", .{line});
                    return error.ReadTimestampFile;
                }

                const path = try context.arena.dupe(u8, line[2..]);
                if (path.len == 0) {
                    log.err("Invalid line in timestamp file: '{s}'", .{line});
                    return error.ReadTimestampFile;
                }

                if (line[0] == 'i') {
                    if (current_input) |ci| {
                        const outputs = try context.arena.dupe([]const u8, current_outputs.items);
                        try outputs_per_input.put(context.gpa, ci, outputs);

                        log.debug("input: '{s}'", .{ci});
                        for (outputs) |o| log.debug("\toutput: '{s}'", .{o});
                    }

                    current_outputs = .empty;
                    current_input = path;
                } else if (line[0] == 'o') {
                    if (current_input == null) {
                        log.err("Invalid line in timestamp file: '{s}'", .{line});
                        log.err("No associated input", .{});
                        return error.ReadTimestampFile;
                    }

                    try current_outputs.append(tmp.a, path);
                }
            }
        }

        if (current_input) |ci| {
            const outputs = try context.arena.dupe([]const u8, current_outputs.items);
            try outputs_per_input.put(context.gpa, ci, outputs);

            log.debug("input: '{s}'", .{ci});
            for (outputs) |o| log.debug("\toutput: '{s}'", .{o});
        }
    } else |e| {
        const full_path = try std.fs.path.resolve(tmp.a, &.{ context.output_dir_path, rel_path });
        std.log.err("unable to open timestamp file for reading '{s}'", .{full_path});
        std.log.err("{s}", .{@errorName(e)});
        return error.WriteTimestampFile;
    }

    return .{ .timestamp = timestamp, .outputs_per_input = outputs_per_input };
}

pub fn writeTimestampFile(context: *const Context, output_dir: *const std.Io.Dir, rel_path: []const u8, input_files: []const InputFile) !void {
    if (output_dir.createFile(context.io, rel_path, .{ .truncate = true })) |timestamp_file| {
        defer timestamp_file.close(context.io);

        var file_writer = timestamp_file.writer(context.io, &timestamp_file_buf);
        const writer = &file_writer.interface;

        for (input_files) |*input_file| {
            try writer.print("i:{s}\n", .{input_file.path});

            for (input_file.outputs) |out_file_path| {
                try writer.print("o:{s}\n", .{out_file_path});
            }
        }

        try writer.flush();
    } else |e| {
        var tmp = mem.getScratch(context.arena);
        defer tmp.release();

        const full_path = try std.fs.path.resolve(tmp.a, &.{ context.output_dir_path, rel_path });
        std.log.err("unable to open timestamp file for writing '{s}'", .{full_path});
        std.log.err("{s}", .{@errorName(e)});
        return error.WriteTimestampFile;
    }
}

pub const InputFile = struct {
    /// Relative to scan_path
    path: []const u8,
    abs_path: []const u8,

    skip: bool = false,

    timestamp: std.Io.Timestamp,

    outputs: []const []const u8 = &.{},
};

fn collectInputFiles(context: *const Context, allocator: Allocator, scan_dir: *const std.Io.Dir, scan_path: []const u8) ![]InputFile {
    var tmp = mem.getScratch(allocator);
    defer tmp.release();

    var input_files: std.ArrayList(InputFile) = .empty;

    var walker = try scan_dir.walk(tmp.a);
    while (try walker.next(context.io)) |entry| {
        if (entry.kind == .file) {
            if (std.mem.eql(u8, ".aseprite", extension(entry.basename))) {
                const tmp_input_path = try tmp.a.dupe(u8, entry.path);
                const abs_path = try pathJoin(allocator, &.{ scan_path, tmp_input_path });
                const path = abs_path[abs_path.len - tmp_input_path.len ..];
                const stat = try scan_dir.statFile(context.io, entry.path, .{});

                try input_files.append(tmp.a, .{
                    .path = path,
                    .abs_path = abs_path,
                    .timestamp = stat.mtime,
                });
            }
        }
    }

    return try allocator.dupe(InputFile, input_files.items);
}

const OutputFileStatus = enum(u2) {
    missing,
    outOfDate,
    upToDate,
};

fn outputFileStatus(context: *const Context, output_dir: *const std.Io.Dir, dir_rel_path: []const u8, input_timestamp: std.Io.Timestamp) !OutputFileStatus {
    const f = std.fs.path.fmtJoin(&.{ context.output_dir_path, dir_rel_path });
    log.debug("checking output file: {f}", .{f});

    const result: OutputFileStatus = if (output_dir.statFile(context.io, dir_rel_path, .{})) |stat|
        if (stat.mtime.nanoseconds <= input_timestamp.nanoseconds)
            .outOfDate
        else
            .upToDate
    else |_|
        .missing;

    log.debug("status: {s}", .{@tagName(result)});
    return result;
}

const RunResult = struct {
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
};

pub const RunError = std.process.RunError || error{};

fn aseprite(context: *const Context, allocator: Allocator, args: []const []const u8) !RunResult {
    var tmp = mem.getScratch(allocator);
    defer tmp.release();

    const argv = try tmp.a.alloc([]const u8, args.len + 1);

    argv[0] = compile_options.aseprite_exe_path;
    @memcpy(argv[1..], args);

    if (context.verbose) {
        for (argv, 0..) |a, i| {
            if (i > 0) try context.stdout.writeByte(' ');
            try context.stdout.writeAll(a);
        }
    }

    const start_time = std.Io.Timestamp.now(context.io, .real);
    const result_or_err = std.process.run(tmp.a, context.io, .{ .argv = argv });
    const duration = start_time.untilNow(context.io, .real);
    total_aseprite_time.nanoseconds += duration.nanoseconds;

    if (context.verbose) {
        try context.stdout.print(" ({f})\n", .{duration});
        try context.stdout.flush();
    }

    const result = try result_or_err;

    switch (result.term) {
        .exited => |ec| {
            var exit_code = ec;
            if (std.mem.startsWith(u8, result.stdout, "File not found:")) {
                exit_code = 1;
            }

            if (result.stderr.len != 0) {
                exit_code = 1;
            }

            if (exit_code != 0) {
                std.log.err("asprite stdout:\n{s}", .{result.stdout});
                std.log.err("asprite stderr:\n{s}", .{result.stderr});
            }
            return .{
                .exit_code = exit_code,
                .stdout = try allocator.dupe(u8, result.stdout),
                .stderr = try allocator.dupe(u8, result.stderr),
            };
        },
        .signal => return error.UnexpectedRunSignal,
        .stopped => return error.RunStopped,
        .unknown => return error.UnknownRunError,
    }
}

fn asepriteTags(context: *const Context, allocator: Allocator, abs_input_path: []const u8) ![]const []const u8 {
    assert(pathIsAbsolute(abs_input_path));

    var tmp = mem.getScratch(allocator);
    defer tmp.release();

    const tags_rr = try aseprite(context, tmp.a, &.{ "-b", "--list-tags", abs_input_path });

    if (tags_rr.exit_code != 0) {
        std.log.err("Asprite invocation failed", .{});
        return error.AsepriteNonZeroExitCode;
    }

    var tags: std.ArrayList([]const u8) = .empty;

    var line_it = std.mem.splitScalar(u8, tags_rr.stdout, '\n');
    while (line_it.next()) |line| {
        const tag = std.mem.trimEnd(u8, line, "\r");
        if (tag.len > 0) {
            const t = try allocator.dupe(u8, tag);
            try tags.append(tmp.a, t);
        }
    }

    return try allocator.dupe([]const u8, tags.items);
}

// Flattens the hierarchy, replacing / with -
fn asepriteLayers(context: *const Context, allocator: Allocator, abs_input_path: []const u8) ![]const []const u8 {
    assert(pathIsAbsolute(abs_input_path));

    var tmp = mem.getScratch(allocator);
    defer tmp.release();

    const layers_rr = try aseprite(context, tmp.a, &.{ "-b", "--all-layers", "--list-layer-hierarchy", abs_input_path });

    if (layers_rr.exit_code != 0) {
        std.log.err("Asprite invocation failed", .{});
        return error.AsepriteNonZeroExitCode;
    }

    var layers: std.ArrayList([]const u8) = .empty;
    var stack: std.ArrayList([]const u8) = .empty;

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
                try stack.append(tmp.a, layer_name[indent * 2 ..]);
            } else {
                const folder = try std.mem.concat(tmp.a, u8, stack.items);
                std.mem.replaceScalar(u8, folder, '/', '_');

                const full_layer_name = try std.mem.concat(allocator, u8, &.{ folder, layer_name[indent * 2 ..] });
                try layers.append(tmp.a, full_layer_name);
            }
        }
    }

    return try allocator.dupe([]const u8, layers.items);
}

fn asepriteExportBMP(context: *const Context, abs_input_path: []const u8, abs_output_path: []const u8) !void {
    assert(pathIsAbsolute(abs_input_path));
    assert(pathIsAbsolute(abs_output_path));

    var tmp = mem.getScratch(context.arena);
    defer tmp.release();

    const export_rr = try aseprite(context, tmp.a, &.{ "-b", abs_input_path, "--save-as", abs_output_path });

    if (export_rr.exit_code != 0) {
        std.log.err("Asprite invocation failed", .{});
        return error.AsepriteNonZeroExitCode;
    }
}

fn asepriteExportSplitLayerBMP(context: *const Context, abs_input_path: []const u8, abs_output_dir_path: []const u8) !void {
    assert(pathIsAbsolute(abs_input_path));
    assert(pathIsAbsolute(abs_output_dir_path));

    var tmp = mem.getScratch(context.arena);
    defer tmp.release();

    const out_dir_param = try std.fmt.allocPrint(tmp.a, "out_dir={s}", .{abs_output_dir_path});
    const script_path = try pathJoin(tmp.a, &.{ compile_options.aseprite_script_path, "extract_layers_recursive.lua" });

    const export_rr = try aseprite(context, tmp.a, &.{
        "-b",
        abs_input_path,
        "--script-param",
        out_dir_param,
        "--script",
        script_path,
    });

    if (export_rr.exit_code != 0) {
        std.log.err("Asprite invocation failed", .{});
        return error.AsepriteNonZeroExitCode;
    }
}

/// Wrapper around std.fs.path.resolve to make this safe to use with arenas.
///  (std.fs.path.resolve does temporary allocations with allocator.)
inline fn pathResolve(allocator: Allocator, paths: []const []const u8) ![]const u8 {
    var tmp = mem.getScratch(allocator);
    defer tmp.release();

    const tmp_res = try std.fs.path.resolve(tmp.a, paths);
    const result = try allocator.dupe(u8, tmp_res);

    return result;
}

inline fn verbose(context: *const Context, comptime fmt: []const u8, args: anytype) void {
    if (context.verbose) log.info(fmt, args);
}
