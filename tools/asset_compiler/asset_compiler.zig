const std = @import("std");
const log_scope = .asset_compiler;
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");

const core = @import("core");
const assert = core.assert;
const clip = core.clip;
const mem = core.mem;
const PerfTs = core.perf.Timestamp;
const PerfDuration = core.perf.Duration;

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

    inline fn err(_: *const Context, comptime fmt: []const u8, args: anytype) void {
        logFn(.err, log_scope, fmt, args);
    }

    inline fn info(this: *const Context, comptime fmt: []const u8, args: anytype) void {
        if (this.options.verbose) logFn(.info, log_scope, fmt, args);
    }

    inline fn debug(this: *const Context, comptime fmt: []const u8, args: anytype) void {
        if (this.options.debug) logFn(.debug, log_scope, fmt, args);
    }
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

    var ctx = Context{
        .io = init.io,
        .gpa = init.gpa,
        .stdout = &stdout_writer.interface,
        .stderr = &stderr_writer.interface,
        .options = args,
    };

    try run(&ctx, &main_arena);
    return 0;
}

pub fn run(ctx: *Context, arena: *mem.Arena) !void {
    const start_time = PerfTs.now(ctx.io);

    const allocator = arena.allocator();

    if (ctx.options.input_scan_dir.len == 0) {
        try ctx.stderr.print("error: missing argument 'input_scan_dir'\n", .{});
        try OptionParser.usage(ctx.stderr);
        return error.MissingInputScanDir;
    }

    if (ctx.options.output_dir.len == 0) {
        try ctx.stderr.print("error: missing argument 'output_dir'\n", .{});
        try OptionParser.usage(ctx.stderr);
        return error.MissingOutputDir;
    }

    const cwd = try std.process.currentPathAlloc(ctx.io, allocator);

    const scan_dir = dir: {
        if (pathIsAbsolute(ctx.options.input_scan_dir)) {
            ctx.scan_dir_path = try allocator.dupe(u8, ctx.options.input_scan_dir);
        } else {
            ctx.scan_dir_path = try pathResolve(allocator, &.{ cwd, ctx.options.input_scan_dir });
        }

        break :dir std.Io.Dir.cwd().openDir(ctx.io, ctx.scan_dir_path, .{ .iterate = true }) catch |e| {
            ctx.err("Unable to open input dir '{s}', error: '{}'", .{ ctx.scan_dir_path, e });
            return error.InvalidInputScanDir;
        };
    };
    defer scan_dir.close(ctx.io);

    const output_dir = dir: {
        if (pathIsAbsolute(ctx.options.output_dir)) {
            ctx.output_dir_path = try allocator.dupe(u8, ctx.options.output_dir);
        } else {
            ctx.output_dir_path = try pathResolve(allocator, &.{ cwd, ctx.options.output_dir });
        }

        break :dir std.Io.Dir.cwd().openDir(ctx.io, ctx.output_dir_path, .{ .iterate = true }) catch |e| switch (e) {
            error.FileNotFound => blk: {
                ctx.info("Creating output dir: '{s}'", .{ctx.output_dir_path});

                break :blk std.Io.Dir.cwd().createDirPathOpen(ctx.io, ctx.output_dir_path, .{}) catch |de| {
                    ctx.err("Unable to creat output dir '{s}', error: '{}", .{ ctx.output_dir_path, de });
                    return de;
                };
            },

            else => {
                ctx.err("Unable to open output dir '{s}', error: '{}'", .{ ctx.output_dir_path, e });
                return error.InvalidOutputDir;
            },
        };
    };
    defer output_dir.close(ctx.io);

    ctx.debug("input_scan_dir: '{s}'", .{ctx.scan_dir_path});
    ctx.debug("output_dir: '{s}'", .{ctx.output_dir_path});

    var ts_file_opt = try readTimestampFile(ctx, arena, &output_dir, timestamp_file_sub_path);
    defer if (ts_file_opt) |*ts_file| ts_file.deinit(ctx);

    const input_files = try collectInputFiles(ctx, arena, &scan_dir, ctx.scan_dir_path);

    var files_to_compile: std.ArrayList(*InputFile) = .empty;
    defer files_to_compile.deinit(ctx.gpa);

    var all_output_files: std.StringHashMapUnmanaged(void) = .empty;
    defer all_output_files.deinit(ctx.gpa);

    if (ts_file_opt) |ts_file| {
        ctx.debug("Check found input files against timestamp file...", .{});
        for (input_files) |*input_file| {
            ctx.debug("  Check new input against timestamp file: '{s}'", .{input_file.abs_path});
            if (ts_file.timestamp.nanoseconds <= input_file.timestamp.nanoseconds) {
                // Input newer than timestamp
                ctx.debug("    Input newer than timestamp, recompile: '{s}'", .{input_file.abs_path});
                try files_to_compile.append(ctx.gpa, input_file);
            } else if (ts_file.inputs.get(input_file.path)) |old_input| {
                const up_to_date = blk: {
                    for (old_input.outputs) |output_file_path| {
                        const status = try outputFileStatus(ctx, &output_dir, output_file_path, input_file.timestamp);
                        ctx.debug("    Output {s}: '{f}'", .{ @tagName(status), std.fs.path.fmtJoin(&.{ ctx.output_dir_path, output_file_path }) });
                        switch (status) {
                            .missing, .outOfDate => break :blk false,
                            .upToDate => {},
                        }
                    }
                    break :blk true;
                };

                if (up_to_date) {
                    if (old_input.skip) {
                        input_file.skip = true;
                        ctx.debug("    Input has skip tag: '{s}'", .{input_file.abs_path});
                    }
                    input_file.old_outputs = old_input.outputs;
                } else {
                    // Input newer than output or missing output(s)
                    try files_to_compile.append(ctx.gpa, input_file);
                }
            } else {
                // New/unseen input
                ctx.debug("    Input file unknown, compile: '{s}'", .{input_file.abs_path});
                try files_to_compile.append(ctx.gpa, input_file);
            }
        }
    } else {
        ctx.debug("Missing timestamp file, compile everything", .{});
        for (input_files) |*input_file| {
            try files_to_compile.append(ctx.gpa, input_file);
        }
    }

    const mem_per_task = 1 * mem.MiB;
    const pool_size = @min(files_to_compile.items.len, std.Thread.getCpuCount() catch 4);
    const mem_pool = try allocator.alloc([mem_per_task]u8, pool_size);
    const pool_free_index_buf = try allocator.alloc(usize, pool_size);
    var pool_free_index_stack = std.ArrayList(usize).initBuffer(pool_free_index_buf);
    for (0..pool_size) |i| pool_free_index_stack.appendAssumeCapacity((pool_size - 1) - i);

    ctx.info("start compile tasks, pool_size: {}, task_count: {}", .{ pool_size, files_to_compile.items.len });

    var main_arena_mutex = std.Io.Mutex.init;
    var pool_mutex = std.Io.Mutex.init;
    var pool_sem = std.Io.Semaphore{ .permits = pool_size };
    var g = std.Io.Group.init;

    for (files_to_compile.items) |input_file| {
        const Args = struct {
            ctx: *Context,
            input_file: *InputFile,
            main_arena: Allocator,
            main_arena_mutex: *std.Io.Mutex,

            pool_free_index_stack: *std.ArrayList(usize),
            pool_mutex: *std.Io.Mutex,
            pool_sem: *std.Io.Semaphore,
        };

        const args = Args{
            .ctx = ctx,
            .input_file = input_file,
            .main_arena = allocator,
            .main_arena_mutex = &main_arena_mutex,
            .pool_free_index_stack = &pool_free_index_stack,
            .pool_mutex = &pool_mutex,
            .pool_sem = &pool_sem,
        };

        g.async(ctx.io, struct {
            fn run(a: Args, mp: [][mem_per_task]u8) !void {
                a.pool_sem.waitUncancelable(a.ctx.io);

                a.pool_mutex.lockUncancelable(a.ctx.io);
                assert(a.pool_free_index_stack.items.len > 0);
                const pool_index = a.pool_free_index_stack.pop().?;
                a.pool_mutex.unlock(a.ctx.io);

                defer {
                    a.pool_mutex.lockUncancelable(a.ctx.io);
                    a.pool_free_index_stack.appendAssumeCapacity(pool_index);
                    a.pool_mutex.unlock(a.ctx.io);

                    a.pool_sem.post(a.ctx.io);
                }

                var perf_timers = PerfTimers{};
                const result_or_err = compile(a.ctx, a.input_file, &mp[pool_index], &perf_timers);

                a.input_file.result_opt = CompileResult{
                    .perf_timers = perf_timers,
                    .output_files_or_error = if (result_or_err) |result| blk: {
                        a.main_arena_mutex.lockUncancelable(a.ctx.io);
                        {
                            defer a.main_arena_mutex.unlock(a.ctx.io);

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

    try g.await(ctx.io);

    var total_aseprite_run_duration: PerfDuration = .zero;

    for (input_files) |*input_file| {
        const outputs = if (input_file.result_opt) |result| blk: {
            total_aseprite_run_duration.add(result.perf_timers.aseprite_run_time);

            break :blk if (result.output_files_or_error) |output_files| output_files else |err| {
                ctx.err("Error compiling input: '{s}', error: '{}'", .{ input_file.path, err });
                break :blk input_file.old_outputs;
            };
        } else input_file.old_outputs;

        for (outputs) |output_file_path| {
            try all_output_files.putNoClobber(ctx.gpa, output_file_path, undefined);
        }
    }

    try writeTimestampFile(ctx, &output_dir, timestamp_file_sub_path, input_files);

    // TODO: Attempt to remove any file in the output dir that's missing from all_output_files

    const total_time = start_time.untilNow(ctx.io);
    ctx.info("aseprite time: {f}", .{total_aseprite_run_duration});
    ctx.info("total time   : {f}", .{total_time});
}

const CompileError = AsepriteError || mem.Arena.Error || error{OutputNameTooLong};

fn compile(ctx: *Context, input_file: *InputFile, task_mem: []u8, perf_timers: *PerfTimers) CompileError![]const []const u8 {
    const arena_size = task_mem.len / 2;
    assert(arena_size >= 512 * mem.KiB);

    var result_arena = try mem.Arena.init(.{ .slice = .{ .data = task_mem[0..arena_size] } });
    var tmp_arena = try mem.Arena.init(.{ .slice = .{ .data = task_mem[arena_size..] } });

    const arena = result_arena.allocator();
    const tmp = mem.TempArena.init(&tmp_arena);

    ctx.info("compiling: '{s}'", .{input_file.abs_path});

    const tags = try asepriteTags(ctx, tmp.arena, &result_arena, input_file.abs_path, perf_timers);
    if (!input_file.skip and tags.skip) input_file.skip = true;

    var output_file_paths: [][]const u8 = &.{};

    if (!tags.skip) {
        const rel_dir_path = dirname(input_file.path) orelse "";

        var name_buf: [std.Io.Dir.max_name_bytes]u8 = undefined;

        output_file_paths = if (tags.split_layers) blk: {
            const layers = try asepriteLayers(ctx, tmp.arena, &result_arena, input_file.abs_path, perf_timers);

            const output_filename_prefix = stem(input_file.path);

            const result = try arena.alloc([]const u8, layers.len);

            for (layers, result) |l, *output_file_name| {
                const name = std.fmt.bufPrint(&name_buf, "{s}_{s}.bmp", .{ output_filename_prefix, l }) catch |e| switch (e) {
                    error.NoSpaceLeft => {
                        ctx.err("Output file name too long: '{s}_{s}.bmp', input file: '{s}'", .{ output_filename_prefix, l, input_file.abs_path });
                        return error.OutputNameTooLong;
                    },
                };
                output_file_name.* = try pathJoin(arena, &.{ rel_dir_path, name });
            }

            const abs_out_dir = try pathJoin(tmp.a, &.{ ctx.output_dir_path, rel_dir_path });
            _ = try asepriteExportSplitLayerBMP(ctx, tmp.arena, &result_arena, input_file.abs_path, abs_out_dir, perf_timers);

            break :blk result;
        } else blk: {
            const input_stem = stem(input_file.path);
            const out_file_name = std.fmt.bufPrint(&name_buf, "{s}.bmp", .{input_stem}) catch |e| switch (e) {
                error.NoSpaceLeft => {
                    ctx.err("Output file name too long: '{s}.bmp', input file: '{s}'", .{ input_stem, input_file.abs_path });
                    return error.OutputNameTooLong;
                },
            };
            const rel_out_path = try pathJoin(arena, &.{ rel_dir_path, out_file_name });
            const abs_file_path = try pathJoin(tmp.a, &.{ ctx.output_dir_path, rel_out_path });

            _ = try asepriteExportBMP(ctx, tmp.arena, &result_arena, input_file.abs_path, abs_file_path, perf_timers);
            break :blk try arena.dupe([]const u8, &.{rel_out_path});
        };
    } else {
        ctx.info("Skipping: '{s}' (skip tag found)", .{input_file.abs_path});
    }

    return output_file_paths;
}

pub const TimestampFile = struct {
    timestamp: std.Io.Timestamp,
    inputs: std.StringHashMapUnmanaged(Input),

    pub const Input = struct {
        skip: bool = false,
        outputs: []const []const u8 = &.{},
    };

    pub fn deinit(this: *TimestampFile, ctx: *const Context) void {
        this.inputs.deinit(ctx.gpa);
    }
};

fn readTimestampFile(ctx: *Context, arena: *mem.Arena, output_dir: *const std.Io.Dir, rel_path: []const u8) !?TimestampFile {
    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    const allocator = _arena.a;
    var tmp = mem.getScratch(allocator);
    defer tmp.release();

    const timestamp: std.Io.Timestamp = if (output_dir.statFile(ctx.io, rel_path, .{})) |stat|
        stat.mtime
    else |_| {
        return null;
    };

    ctx.debug("Reading timestamp file", .{});

    var inputs: std.StringHashMapUnmanaged(TimestampFile.Input) = .empty;
    errdefer inputs.deinit(ctx.gpa);

    const ts_file = output_dir.openFile(ctx.io, rel_path, .{ .mode = .read_only }) catch |e| {
        const full_path = try std.fs.path.resolve(tmp.a, &.{ ctx.output_dir_path, rel_path });
        ctx.err("Unable to open timestamp file for reading: '{s}', error: '{}'", .{ full_path, e });
        return error.WriteTimestampFile;
    };
    defer ts_file.close(ctx.io);

    var read_buf: [4096]u8 = undefined;
    var reader = ts_file.reader(ctx.io, &read_buf);

    const ts_len = try reader.getSize();
    const timestamp_file_content = reader.interface.readAlloc(tmp.a, ts_len) catch |e| {
        const full_path = try std.fs.path.resolve(tmp.a, &.{ ctx.output_dir_path, rel_path });
        ctx.err("Unable to read timestamp file: '{s}', error: '{}'", .{ full_path, e });
        return error.WriteTimestampFile;
    };

    var line_it = std.mem.splitScalar(u8, timestamp_file_content, '\n');

    var current_input: ?[]const u8 = null;
    var current_outputs: std.ArrayList([]const u8) = .empty;

    while (line_it.next()) |raw_line| {
        var flush_input: ?struct { ?[]const u8 } = null;
        const line = std.mem.trim(u8, raw_line, "\r");

        if (line.len > 0) {
            if (!(line[0] == 'i' or line[0] == 'o' or line[0] == 's') or line[1] != ':') {
                ctx.err("Invalid line in timestamp file: '{s}'", .{line});
                return error.ReadTimestampFile;
            }

            const path = try allocator.dupe(u8, line[2..]);
            if (path.len == 0) {
                ctx.err("Invalid line in timestamp file: '{s}'", .{line});
                return error.ReadTimestampFile;
            }

            if (line[0] == 'i') {
                flush_input = .{path};
            } else if (line[0] == 'o') {
                if (current_input == null) {
                    ctx.err("Invalid line in timestamp file: '{s}'", .{line});
                    ctx.err("No associated input", .{});
                    return error.ReadTimestampFile;
                }

                try current_outputs.append(tmp.a, path);
            } else if (line[0] == 's') {
                flush_input = .{null};

                try inputs.put(ctx.gpa, path, .{ .skip = true });
            }

            if (flush_input) |next_input| {
                if (current_input) |ci| {
                    const outputs = try allocator.dupe([]const u8, current_outputs.items);
                    try inputs.put(ctx.gpa, ci, .{ .outputs = outputs });

                    ctx.debug("  Input: '{s}'", .{ci});
                    for (outputs) |o| ctx.debug("    Output: '{s}'", .{o});
                }

                current_outputs = .empty;
                current_input = next_input[0];
            }
        }
    }

    if (current_input) |ci| {
        const outputs = try allocator.dupe([]const u8, current_outputs.items);
        try inputs.put(ctx.gpa, ci, .{ .outputs = outputs });

        ctx.debug("  Input: '{s}'", .{ci});
        for (outputs) |o| ctx.debug("    Output: '{s}'", .{o});
    }

    return .{ .timestamp = timestamp, .inputs = inputs };
}

pub fn writeTimestampFile(ctx: *Context, output_dir: *const std.Io.Dir, rel_path: []const u8, input_files: []const InputFile) !void {
    if (output_dir.createFile(ctx.io, rel_path, .{ .truncate = true })) |timestamp_file| {
        defer timestamp_file.close(ctx.io);

        var write_buf: [4096]u8 = undefined;
        var file_writer = timestamp_file.writer(ctx.io, &write_buf);
        const writer = &file_writer.interface;

        for (input_files) |input_file| {
            if (input_file.skip) {
                try writer.print("s:{s}\n", .{input_file.path});
            } else {
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
        }

        try writer.flush();
    } else |e| {
        ctx.err("unable to open timestamp file for writing '{s}/{s}', error: '{}'", .{ ctx.output_dir_path, rel_path, e });
        return error.WriteTimestampFile;
    }
}

const AsepriteTags = packed struct(u2) {
    skip: bool = false,
    split_layers: bool = false,
};

pub const InputFile = struct {
    /// Relative to scan_path
    path: []const u8,
    abs_path: []const u8,

    timestamp: std.Io.Timestamp,

    old_outputs: []const []const u8 = &.{},

    skip: bool = false,
    result_opt: ?CompileResult = null,
};

pub const CompileResult = struct {
    output_files_or_error: CompileError![]const []const u8,

    perf_timers: PerfTimers = .{},
};

pub const PerfTimers = struct {
    aseprite_run_time: PerfDuration = .zero,
};

fn collectInputFiles(ctx: *const Context, arena: *mem.Arena, scan_dir: *const std.Io.Dir, scan_path: []const u8) ![]InputFile {
    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    const allocator = _arena.a;
    var tmp = mem.getScratch(allocator);
    defer tmp.release();

    ctx.debug("Collecting input files...", .{});

    var input_files: std.ArrayList(InputFile) = .empty;

    var walker = try scan_dir.walk(tmp.a);
    while (try walker.next(ctx.io)) |entry| {
        if (entry.kind == .file) {
            if (std.mem.eql(u8, ".aseprite", extension(entry.basename))) {
                const tmp_input_path = try tmp.a.dupe(u8, entry.path);
                const abs_path = try pathJoin(allocator, &.{ scan_path, tmp_input_path });
                const path = abs_path[abs_path.len - tmp_input_path.len ..];
                const stat = try scan_dir.statFile(ctx.io, entry.path, .{});

                try input_files.append(tmp.a, .{
                    .path = path,
                    .abs_path = abs_path,
                    .timestamp = stat.mtime,
                    .skip = false,
                });
                ctx.debug("  Found input file: '{s}'", .{abs_path});
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

fn outputFileStatus(ctx: *const Context, output_dir: *const std.Io.Dir, dir_rel_path: []const u8, input_timestamp: std.Io.Timestamp) !OutputFileStatus {
    const result: OutputFileStatus = if (output_dir.statFile(ctx.io, dir_rel_path, .{})) |stat|
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

fn aseprite(ctx: *Context, arena: *mem.Arena, tmp_arena: *mem.Arena, args: []const []const u8, perf_timers: *PerfTimers) AsepriteError!RunResult {
    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    const allocator = _arena.a;
    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const argv = try tmp.a.alloc([]const u8, args.len + 1);

    argv[0] = compile_options.aseprite_exe_path;
    @memcpy(argv[1..], args);

    const start_ts = PerfTs.now(ctx.io);
    const result_or_err = std.process.run(tmp.a, ctx.io, .{ .argv = argv });
    const run_duration = start_ts.untilNow(ctx.io);
    perf_timers.aseprite_run_time.add(run_duration);

    if (ctx.options.verbose) {
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
                ctx.err("asprite stdout:\n{s}", .{result.stdout});
                ctx.err("asprite stderr:\n{s}", .{result.stderr});
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

fn asepriteTags(ctx: *Context, arena: *mem.Arena, tmp_arena: *mem.Arena, abs_input_path: []const u8, perf_timers: *PerfTimers) AsepriteError!AsepriteTags {
    assert(pathIsAbsolute(abs_input_path));

    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    const allocator = _arena.a;
    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const tags_rr = try aseprite(ctx, tmp.arena, arena, &.{ "-b", "--list-tags", abs_input_path }, perf_timers);

    var tags: std.ArrayList([]const u8) = .empty;

    var line_it = std.mem.splitScalar(u8, tags_rr.stdout, '\n');
    while (line_it.next()) |line| {
        const tag = std.mem.trimEnd(u8, line, "\r");
        if (tag.len > 0) {
            const t = try allocator.dupe(u8, tag);
            try tags.append(tmp.a, t);
        }
    }

    var result: AsepriteTags = .{};

    for (tags.items) |t| {
        if (std.mem.eql(u8, "skip", t))
            result.skip = true
        else if (std.mem.eql(u8, "split_layers", t))
            result.split_layers = true;
    }

    return result;
}

// Flattens the hierarchy, replacing / with -
fn asepriteLayers(ctx: *Context, arena: *mem.Arena, tmp_arena: *mem.Arena, abs_input_path: []const u8, perf_timers: *PerfTimers) AsepriteError![]const []const u8 {
    assert(pathIsAbsolute(abs_input_path));

    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    const allocator = _arena.a;
    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const layers_rr = try aseprite(ctx, tmp.arena, arena, &.{ "-b", "--all-layers", "--list-layer-hierarchy", abs_input_path }, perf_timers);

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

fn asepriteExportBMP(ctx: *Context, arena: *mem.Arena, tmp_arena: *mem.Arena, abs_input_path: []const u8, abs_output_path: []const u8, perf_timers: *PerfTimers) AsepriteError!void {
    assert(pathIsAbsolute(abs_input_path));
    assert(pathIsAbsolute(abs_output_path));

    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    _ = try aseprite(ctx, tmp.arena, arena, &.{ "-b", abs_input_path, "--save-as", abs_output_path }, perf_timers);
}

fn asepriteExportSplitLayerBMP(ctx: *Context, arena: *mem.Arena, tmp_arena: *mem.Arena, abs_input_path: []const u8, abs_output_dir_path: []const u8, perf_timers: *PerfTimers) AsepriteError!void {
    assert(pathIsAbsolute(abs_input_path));
    assert(pathIsAbsolute(abs_output_dir_path));

    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const out_dir_param = try std.fmt.allocPrint(tmp.a, "out_dir={s}", .{abs_output_dir_path});
    const script_path = try pathJoin(tmp.a, &.{ compile_options.aseprite_script_path, "extract_layers_recursive.lua" });

    _ = try aseprite(ctx, tmp.arena, arena, &.{
        "-b",
        abs_input_path,
        "--script-param",
        out_dir_param,
        "--script",
        script_path,
    }, perf_timers);
}
