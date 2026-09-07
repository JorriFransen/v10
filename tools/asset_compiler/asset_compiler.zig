const std = @import("std");
const log_scope = .asset_compiler;
const log = std.log.scoped(log_scope);
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");

const core = @import("core");
const assert = core.assert;
const clip = core.clip;
const mem = core.mem;

const compile_options = @import("options");

const pathResolve = std.fs.path.resolve;
const pathJoin = std.fs.path.join;
const extension = std.fs.path.extension;
const dirname = std.fs.path.dirname;
const stem = std.fs.path.stem;
const pathIsAbsolute = std.fs.path.isAbsolute;

pub const std_options: std.Options = core.default_std_options;
const logFn = std_options.logFn;

const OptionParser = clip.OptionParser("asset_compiler", &.{
    clip.option(@as([]const u8, ""), "input_scan_dir", 'i', "Directory to scan for input files"),
    clip.option(@as([]const u8, ""), "output_dir", 'o', "Output directory"),
    clip.option(false, "verbose", 'v', "Verbose output"),
    clip.option(false, "debug", 'd', "Debug output"),
});

/// Relative to output_dir
const timestamp_file_sub_path = ".timestamps";

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,

    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,

    scan_dir_path: []const u8 = undefined,
    output_dir_path: []const u8 = undefined,

    options: OptionParser.Options,
};

pub fn main(init: std.process.Init) !u8 {
    mem.init();
    defer mem.deinit();

    var stderr_buf: [256]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buf);

    var stdout_buf: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    defer {
        stderr_writer.flush() catch {};
        stdout_writer.flush() catch {};
    }

    var main_arena = try mem.Arena.init(.{ .virtual = .{} });

    const args: OptionParser.Options = blk: {
        var arg_tmp = mem.getScratch(main_arena.allocator());
        defer arg_tmp.release();

        const raw_args = try init.minimal.args.toSlice(arg_tmp.a);
        break :blk OptionParser.parse(
            raw_args[1..],
            main_arena.allocator(),
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
        .gpa = init.gpa,
        .stdout = &stdout_writer.interface,
        .stderr = &stderr_writer.interface,
        .options = args,
    };

    try run(&context, &main_arena);
    return 0;
}

pub fn run(context: *Context, arena: *mem.Arena) !void {
    const start_time = PerfTs.now(context.io);

    const allocator = arena.allocator();

    if (context.options.input_scan_dir.len == 0) {
        try context.stderr.print("error: missing argument 'input_scan_dir'\n", .{});
        try OptionParser.usage(context.stderr);
        return error.MissingInputScanDir;
    }

    if (context.options.output_dir.len == 0) {
        try context.stderr.print("error: missing argument 'output_dir'\n", .{});
        try OptionParser.usage(context.stderr);
        return error.MissingOutputDir;
    }

    const cwd = try std.process.currentPathAlloc(context.io, allocator);

    const scan_dir = dir: {
        if (pathIsAbsolute(context.options.input_scan_dir)) {
            context.scan_dir_path = try allocator.dupe(u8, context.options.input_scan_dir);
        } else {
            context.scan_dir_path = try pathResolve(allocator, &.{ cwd, context.options.input_scan_dir });
        }

        break :dir std.Io.Dir.cwd().openDir(context.io, context.scan_dir_path, .{ .iterate = true }) catch |e| {
            std.log.err("Unable to open input dir '{s}', error: '{}'", .{ context.scan_dir_path, e });
            return error.InvalidInputScanDir;
        };
    };
    defer scan_dir.close(context.io);

    const output_dir = dir: {
        if (pathIsAbsolute(context.options.output_dir)) {
            context.output_dir_path = try allocator.dupe(u8, context.options.output_dir);
        } else {
            context.output_dir_path = try pathResolve(allocator, &.{ cwd, context.options.output_dir });
        }

        break :dir std.Io.Dir.cwd().openDir(context.io, context.output_dir_path, .{ .iterate = true }) catch |e| switch (e) {
            error.FileNotFound => blk: {
                verbose(context, "Creating output dir: '{s}'", .{context.output_dir_path});

                break :blk std.Io.Dir.cwd().createDirPathOpen(context.io, context.output_dir_path, .{}) catch |de| {
                    std.log.err("Unable to creat output dir '{s}', error: '{}", .{ context.output_dir_path, de });
                    return de;
                };
            },

            else => {
                std.log.err("Unable to open output dir '{s}', error: '{}'", .{ context.output_dir_path, e });
                return error.InvalidOutputDir;
            },
        };
    };
    defer output_dir.close(context.io);

    debug(context, "input_scan_dir: '{s}'", .{context.scan_dir_path});
    debug(context, "output_dir: '{s}'", .{context.output_dir_path});

    var ts_file_opt = try readTimestampFile(context, allocator, &output_dir, timestamp_file_sub_path);
    defer if (ts_file_opt) |*ts_file| ts_file.deinit(context);

    const input_files = try collectInputFiles(context, allocator, &scan_dir, context.scan_dir_path);

    var files_to_compile: std.ArrayList(*InputFile) = .empty;
    defer files_to_compile.deinit(context.gpa);

    var all_output_files: std.StringHashMapUnmanaged(void) = .empty;
    defer all_output_files.deinit(context.gpa);

    if (ts_file_opt) |ts_file| {
        debug(context, "Check found input files against timestamp file...", .{});
        for (input_files) |*input_file| {
            debug(context, "  Check new input against timestamp file: '{s}'", .{input_file.abs_path});
            if (ts_file.timestamp.nanoseconds <= input_file.timestamp.nanoseconds) {
                // Input newer than timestamp
                debug(context, "    Input newer than timestamp, recompile: '{s}'", .{input_file.abs_path});
                try files_to_compile.append(context.gpa, input_file);
            } else if (ts_file.outputs_per_input.get(input_file.path)) |old_output_files| {
                const up_to_date = blk: {
                    for (old_output_files) |output_file_path| {
                        const status = try outputFileStatus(context, &output_dir, output_file_path, input_file.timestamp);
                        debug(context, "    Output {s}: '{f}'", .{ @tagName(status), std.fs.path.fmtJoin(&.{ context.output_dir_path, output_file_path }) });
                        switch (status) {
                            .missing, .outOfDate => break :blk false,
                            .upToDate => {},
                        }
                    }
                    break :blk true;
                };

                if (up_to_date) {
                    if (old_output_files.len == 0) {
                        debug(context, "    Input has skip tag: '{s}'", .{input_file.abs_path});
                    }
                    input_file.old_outputs = old_output_files;
                } else {
                    // Input newer than output or missing output(s)
                    try files_to_compile.append(context.gpa, input_file);
                }
            } else {
                // New/unseen input
                debug(context, "    Input file unknown, compile: '{s}'", .{input_file.abs_path});
                try files_to_compile.append(context.gpa, input_file);
            }
        }
    } else {
        debug(context, "Missing timestamp file, compile everything", .{});
        for (input_files) |*input_file| {
            try files_to_compile.append(context.gpa, input_file);
        }
    }

    const mem_per_task = 1 * mem.MiB;
    const pool_size = @min(files_to_compile.items.len, std.Thread.getCpuCount() catch 4);
    const mem_pool = try allocator.alloc([mem_per_task]u8, pool_size);
    const pool_free_index_buf = try allocator.alloc(usize, pool_size);
    var pool_free_index_stack = std.ArrayList(usize).initBuffer(pool_free_index_buf);
    for (0..pool_size) |i| pool_free_index_stack.appendAssumeCapacity((pool_size - 1) - i);

    verbose(context, "start compile tasks, pool_size: {}, task_count: {}", .{ pool_size, files_to_compile.items.len });

    var main_arena_mutex = std.Io.Mutex.init;
    var pool_mutex = std.Io.Mutex.init;
    var pool_sem = std.Io.Semaphore{ .permits = pool_size };
    var g = std.Io.Group.init;

    for (files_to_compile.items) |input_file| {
        const Args = struct {
            context: *Context,
            input_file: *InputFile,
            main_arena: Allocator,
            main_arena_mutex: *std.Io.Mutex,

            pool_free_index_stack: *std.ArrayList(usize),
            pool_mutex: *std.Io.Mutex,
            pool_sem: *std.Io.Semaphore,
        };

        const args = Args{
            .context = context,
            .input_file = input_file,
            .main_arena = allocator,
            .main_arena_mutex = &main_arena_mutex,
            .pool_free_index_stack = &pool_free_index_stack,
            .pool_mutex = &pool_mutex,
            .pool_sem = &pool_sem,
        };

        g.async(context.io, struct {
            fn run(a: Args, mp: [][mem_per_task]u8) !void {
                a.pool_sem.waitUncancelable(a.context.io);

                a.pool_mutex.lockUncancelable(a.context.io);
                assert(a.pool_free_index_stack.items.len > 0);
                const pool_index = a.pool_free_index_stack.pop().?;
                a.pool_mutex.unlock(a.context.io);

                defer {
                    a.pool_mutex.lockUncancelable(a.context.io);
                    a.pool_free_index_stack.appendAssumeCapacity(pool_index);
                    a.pool_mutex.unlock(a.context.io);

                    a.pool_sem.post(a.context.io);
                }

                var perf_timers = PerfTimers{};
                const result_or_err = compile(a.context, a.input_file, &mp[pool_index], &perf_timers);

                a.input_file.result_opt = CompileResult{
                    .perf_timers = perf_timers,
                    .output_files_or_error = if (result_or_err) |result| blk: {
                        a.main_arena_mutex.lockUncancelable(a.context.io);
                        {
                            defer a.main_arena_mutex.unlock(a.context.io);

                            if (a.main_arena.alloc([]const u8, result.len)) |array_copy| {
                                for (result, array_copy) |source, *dest|
                                    if (a.main_arena.dupe(u8, source)) |string_copy| {
                                        dest.* = string_copy;
                                    } else |e| break :blk e;
                                break :blk array_copy;
                            } else |e| break :blk e;
                        }
                    } else |err| err,
                };
            }
        }.run, .{ args, mem_pool });
    }

    try g.await(context.io);

    var total_aseprite_run_duration: PerfDuration = .zero;

    for (input_files) |*input_file| {
        const outputs = if (input_file.result_opt) |result| blk: {
            total_aseprite_run_duration.add(result.perf_timers.aseprite_run_time);

            break :blk if (result.output_files_or_error) |output_files| output_files else |err| {
                log.err("Error compiling input: '{s}', error: '{}'", .{ input_file.path, err });
                break :blk input_file.old_outputs;
            };
        } else input_file.old_outputs;

        for (outputs) |output_file_path| {
            try all_output_files.putNoClobber(context.gpa, output_file_path, undefined);
        }
    }

    try writeTimestampFile(context, &output_dir, timestamp_file_sub_path, input_files);

    // TODO: Attempt to remove any file in the output dir that's missing from all_output_files

    const total_time = start_time.untilNow(context.io);
    verbose(context, "aseprite time: {f}", .{total_aseprite_run_duration});
    verbose(context, "total time   : {f}", .{total_time});
}

const CompileError = AsepriteError || mem.Arena.Error || error{OutputNameTooLong};

fn compile(context: *Context, input_file: *InputFile, task_mem: []u8, perf_timers: *PerfTimers) CompileError![]const []const u8 {
    const arena_size = task_mem.len / 2;
    assert(arena_size >= 512 * mem.KiB);

    var result_arena = try mem.Arena.init(.{ .slice = .{ .data = task_mem[0..arena_size] } });
    var tmp_arena = try mem.Arena.init(.{ .slice = .{ .data = task_mem[arena_size..] } });

    const arena = result_arena.allocator();
    const tmp = mem.TempArena.init(&tmp_arena);

    verbose(context, "compiling: '{s}'", .{input_file.abs_path});

    const tags = try asepriteTags(context, tmp.arena, &result_arena, input_file.abs_path, perf_timers);

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

    var output_file_paths: [][]const u8 = &.{};

    if (!tag_skip) {
        const rel_dir_path = dirname(input_file.path) orelse "";

        var name_buf: [std.Io.Dir.max_name_bytes]u8 = undefined;

        output_file_paths = if (tag_split_layers) blk: {
            const layers = try asepriteLayers(context, tmp.arena, &result_arena, input_file.abs_path, perf_timers);

            const output_filename_prefix = stem(input_file.path);

            const result = try arena.alloc([]const u8, layers.len);

            for (layers, result) |l, *output_file_name| {
                const name = std.fmt.bufPrint(&name_buf, "{s}_{s}.bmp", .{ output_filename_prefix, l }) catch |e| switch (e) {
                    error.NoSpaceLeft => {
                        log.err("Output file name too long: '{s}_{s}.bmp', input file: '{s}'", .{ output_filename_prefix, l, input_file.abs_path });
                        return error.OutputNameTooLong;
                    },
                };
                output_file_name.* = try pathJoin(arena, &.{ rel_dir_path, name });
            }

            const abs_out_dir = try pathJoin(tmp.a, &.{ context.output_dir_path, rel_dir_path });
            _ = try asepriteExportSplitLayerBMP(context, tmp.arena, &result_arena, input_file.abs_path, abs_out_dir, perf_timers);

            break :blk result;
        } else blk: {
            const input_stem = stem(input_file.path);
            const out_file_name = std.fmt.bufPrint(&name_buf, "{s}.bmp", .{input_stem}) catch |e| switch (e) {
                error.NoSpaceLeft => {
                    log.err("Output file name too long: '{s}.bmp', input file: '{s}'", .{ input_stem, input_file.abs_path });
                    return error.OutputNameTooLong;
                },
            };
            const rel_out_path = try pathJoin(arena, &.{ rel_dir_path, out_file_name });
            const abs_file_path = try pathJoin(tmp.a, &.{ context.output_dir_path, rel_out_path });

            _ = try asepriteExportBMP(context, tmp.arena, &result_arena, input_file.abs_path, abs_file_path, perf_timers);
            break :blk try arena.dupe([]const u8, &.{rel_out_path});
        };
    } else {
        verbose(context, "Skipping: '{s}' (skip tag found)", .{input_file.abs_path});
    }

    return output_file_paths;
}

pub const TimestampFile = struct {
    timestamp: std.Io.Timestamp,
    outputs_per_input: std.StringHashMapUnmanaged([]const []const u8),

    pub fn deinit(this: *TimestampFile, context: *const Context) void {
        this.outputs_per_input.deinit(context.gpa);
    }
};

fn readTimestampFile(context: *Context, allocator: Allocator, output_dir: *const std.Io.Dir, rel_path: []const u8) !?TimestampFile {
    var tmp = mem.getScratch(allocator);
    defer tmp.release();

    const timestamp: std.Io.Timestamp = if (output_dir.statFile(context.io, rel_path, .{})) |stat|
        stat.mtime
    else |_| {
        return null;
    };

    debug(context, "Reading timestamp file", .{});

    var outputs_per_input: std.StringHashMapUnmanaged([]const []const u8) = .empty;
    errdefer outputs_per_input.deinit(context.gpa);

    if (output_dir.readFileAlloc(context.io, rel_path, tmp.a, .limited(tmp.arena.unused()))) |timestamp_file_content| {
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

                const path = try allocator.dupe(u8, line[2..]);
                if (path.len == 0) {
                    log.err("Invalid line in timestamp file: '{s}'", .{line});
                    return error.ReadTimestampFile;
                }

                if (line[0] == 'i') {
                    if (current_input) |ci| {
                        const outputs = try allocator.dupe([]const u8, current_outputs.items);
                        try outputs_per_input.put(context.gpa, ci, outputs);

                        debug(context, "  Input: '{s}'", .{ci});
                        for (outputs) |o| debug(context, "    Output: '{s}'", .{o});
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
            const outputs = try allocator.dupe([]const u8, current_outputs.items);
            try outputs_per_input.put(context.gpa, ci, outputs);

            debug(context, "  Input: '{s}'", .{ci});
            for (outputs) |o| debug(context, "    Output: '{s}'", .{o});
        }
    } else |e| {
        const full_path = try std.fs.path.resolve(tmp.a, &.{ context.output_dir_path, rel_path });
        std.log.err("unable to open timestamp file for reading '{s}', error: '{}'", .{ full_path, e });
        return error.WriteTimestampFile;
    }

    return .{ .timestamp = timestamp, .outputs_per_input = outputs_per_input };
}

pub fn writeTimestampFile(context: *Context, output_dir: *const std.Io.Dir, rel_path: []const u8, input_files: []const InputFile) !void {
    if (output_dir.createFile(context.io, rel_path, .{ .truncate = true })) |timestamp_file| {
        defer timestamp_file.close(context.io);

        var write_buf: [4096]u8 = undefined;
        var file_writer = timestamp_file.writer(context.io, &write_buf);
        const writer = &file_writer.interface;

        for (input_files) |input_file| {
            const outputs_opt = if (input_file.result_opt) |result_or_err|
                // Failed inputs are omitted to force retry on next run
                // Old outputs for failed inputs are still recorded in all_output_files, so --clean does not remove them
                if (result_or_err.output_files_or_error) |output_files| output_files else |_| null
            else
                input_file.old_outputs;

            if (outputs_opt) |outputs| {
                try writer.print("i:{s}\n", .{input_file.path});
                for (outputs) |out_file_path| {
                    try writer.print("o:{s}\n", .{out_file_path});
                }
            }
        }

        try writer.flush();
    } else |e| {
        std.log.err("unable to open timestamp file for writing '{s}/{s}', error: '{}'", .{ context.output_dir_path, rel_path, e });
        return error.WriteTimestampFile;
    }
}

pub const InputFile = struct {
    /// Relative to scan_path
    path: []const u8,
    abs_path: []const u8,

    skip: bool = false,

    timestamp: std.Io.Timestamp,

    old_outputs: []const []const u8 = &.{},

    result_opt: ?CompileResult = null,
};

pub const CompileResult = struct {
    output_files_or_error: CompileError![]const []const u8,

    perf_timers: PerfTimers = .{},
};

pub const PerfTimers = struct {
    aseprite_run_time: PerfDuration = .zero,
};

fn collectInputFiles(context: *const Context, allocator: Allocator, scan_dir: *const std.Io.Dir, scan_path: []const u8) ![]InputFile {
    var tmp = mem.getScratch(allocator);
    defer tmp.release();

    debug(context, "Collecting input files...", .{});

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
                debug(context, "  Found input file: '{s}'", .{abs_path});
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
    const result: OutputFileStatus = if (output_dir.statFile(context.io, dir_rel_path, .{})) |stat|
        if (stat.mtime.nanoseconds <= input_timestamp.nanoseconds)
            .outOfDate
        else
            .upToDate
    else |_|
        .missing;

    return result;
}

const RunResult = struct {
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
};

pub const AsepriteError = error{AsepriteRunFailed} ||
    Allocator.Error ||
    std.process.RunError;

fn aseprite(context: *Context, result_arena: *mem.Arena, tmp_arena: *mem.Arena, args: []const []const u8, perf_timers: *PerfTimers) AsepriteError!RunResult {
    const allocator = result_arena.allocator();
    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const argv = try tmp.a.alloc([]const u8, args.len + 1);

    argv[0] = compile_options.aseprite_exe_path;
    @memcpy(argv[1..], args);

    const start_ts = PerfTs.now(context.io);
    const result_or_err = std.process.run(tmp.a, context.io, .{ .argv = argv });
    const run_duration = start_ts.untilNow(context.io);
    perf_timers.aseprite_run_time.add(run_duration);

    if (context.options.verbose) {
        var buf: [512]u8 = undefined;
        const w = &std.debug.lockStderr(&buf).file_writer.interface;
        defer std.debug.unlockStderr();

        for (argv, 0..) |a, i| {
            if (i > 0) w.writeByte(' ') catch {};
            w.writeAll(a) catch {};
        }
        w.print(" ({f})\n", .{run_duration}) catch {};
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
                return error.AsepriteRunFailed;
            }
            return .{
                .exit_code = exit_code,
                .stdout = try allocator.dupe(u8, result.stdout),
                .stderr = try allocator.dupe(u8, result.stderr),
            };
        },
        .signal, .stopped, .unknown => return error.AsepriteRunFailed,
    }
}

fn asepriteTags(context: *Context, result_arena: *mem.Arena, tmp_arena: *mem.Arena, abs_input_path: []const u8, perf_timers: *PerfTimers) AsepriteError![]const []const u8 {
    assert(pathIsAbsolute(abs_input_path));

    const allocator = result_arena.allocator();
    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const tags_rr = try aseprite(context, tmp.arena, result_arena, &.{ "-b", "--list-tags", abs_input_path }, perf_timers);

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
fn asepriteLayers(context: *Context, result_arena: *mem.Arena, tmp_arena: *mem.Arena, abs_input_path: []const u8, perf_timers: *PerfTimers) AsepriteError![]const []const u8 {
    assert(pathIsAbsolute(abs_input_path));

    const allocator = result_arena.allocator();
    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const layers_rr = try aseprite(context, tmp.arena, result_arena, &.{ "-b", "--all-layers", "--list-layer-hierarchy", abs_input_path }, perf_timers);

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

fn asepriteExportBMP(context: *Context, result_arena: *mem.Arena, tmp_arena: *mem.Arena, abs_input_path: []const u8, abs_output_path: []const u8, perf_timers: *PerfTimers) AsepriteError!void {
    assert(pathIsAbsolute(abs_input_path));
    assert(pathIsAbsolute(abs_output_path));

    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    _ = try aseprite(context, tmp.arena, result_arena, &.{ "-b", abs_input_path, "--save-as", abs_output_path }, perf_timers);
}

fn asepriteExportSplitLayerBMP(context: *Context, result_arena: *mem.Arena, tmp_arena: *mem.Arena, abs_input_path: []const u8, abs_output_dir_path: []const u8, perf_timers: *PerfTimers) AsepriteError!void {
    assert(pathIsAbsolute(abs_input_path));
    assert(pathIsAbsolute(abs_output_dir_path));

    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const out_dir_param = try std.fmt.allocPrint(tmp.a, "out_dir={s}", .{abs_output_dir_path});
    const script_path = try pathJoin(tmp.a, &.{ compile_options.aseprite_script_path, "extract_layers_recursive.lua" });

    _ = try aseprite(context, tmp.arena, result_arena, &.{
        "-b",
        abs_input_path,
        "--script-param",
        out_dir_param,
        "--script",
        script_path,
    }, perf_timers);
}

inline fn verbose(context: *const Context, comptime fmt: []const u8, args: anytype) void {
    if (context.options.verbose) logFn(.info, log_scope, fmt, args);
}

inline fn debug(context: *const Context, comptime fmt: []const u8, args: anytype) void {
    if (context.options.debug) logFn(.debug, log_scope, fmt, args);
}

const PerfTs = struct {
    wall: std.Io.Timestamp,
    cpu: std.Io.Timestamp,

    pub fn now(io: std.Io) PerfTs {
        return .{
            .wall = std.Io.Timestamp.now(io, .awake),
            .cpu = std.Io.Timestamp.now(io, .cpu_thread),
        };
    }

    pub fn untilNow(start: *const PerfTs, io: std.Io) PerfDuration {
        const n = now(io);
        return .{
            .wall = start.wall.durationTo(n.wall),
            .cpu = start.cpu.durationTo(n.cpu),
        };
    }
};

const PerfDuration = struct {
    wall: std.Io.Duration,
    cpu: std.Io.Duration,

    pub const zero = PerfDuration{ .wall = .zero, .cpu = .zero };

    pub fn add(this: *PerfDuration, other: PerfDuration) void {
        this.wall.nanoseconds += other.wall.nanoseconds;
        this.cpu.nanoseconds += other.cpu.nanoseconds;
    }

    pub fn format(this: *const PerfDuration, writer: *std.Io.Writer) !void {
        try writer.print("wall: {:0<7.2}ms, cpu: {:0<7.2}ms", .{
            @as(f64, @floatFromInt(this.wall.nanoseconds)) / std.time.ns_per_ms,
            @as(f64, @floatFromInt(this.cpu.nanoseconds)) / std.time.ns_per_ms,
        });
    }
};
