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
const fmtAlt = std.fmt.alt;

pub const std_options: std.Options = core.default_std_options;
const logFn = std_options.logFn;

const OptionParser = clip.OptionParser("asset_compiler", &.{
    clip.option(@as([]const u8, ""), "input_scan_dir", 'i', "Directory to scan for input files"),
    clip.option(@as([]const u8, ""), "output_dir", 'o', "Output directory"),
    clip.option(@as(usize, 0), "max_threads", 'n', "Max concurrent compilation threads (default to 'std.Thread.getCpuCount() catch 1')"),
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

    scan_dir: std.Io.Dir = undefined,
    output_dir: std.Io.Dir = undefined,

    scan_dir_path: []const u8 = undefined,
    output_dir_path: []const u8 = undefined,

    options: OptionParser.Options,

    inline fn err(_: *const Context, comptime fmt: []const u8, args: anytype) void {
        logFn(.err, log_scope, fmt, args);
    }

    inline fn verbose(this: *const Context, comptime fmt: []const u8, args: anytype) void {
        if (this.options.verbose) logFn(.info, log_scope, fmt, args);
    }

    inline fn info(_: *const Context, comptime fmt: []const u8, args: anytype) void {
        logFn(.info, log_scope, fmt, args);
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

    var rc: u8 = 0;

    run(&ctx, &main_arena) catch |e| {
        ctx.err("Error: '{s}'", .{@errorName(e)});
        rc = 1;
    };

    return rc;
}

pub fn run(ctx: *Context, arena: *mem.Arena) !void {
    const start_time = PerfTs.now(ctx.io);

    const allocator = arena.allocator();

    if (ctx.options.debug) ctx.options.verbose = true;

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

    ctx.scan_dir = dir: {
        if (pathIsAbsolute(ctx.options.input_scan_dir)) {
            ctx.scan_dir_path = try allocator.dupe(u8, ctx.options.input_scan_dir);
        } else {
            ctx.scan_dir_path = try pathResolve(allocator, &.{ cwd, ctx.options.input_scan_dir });
        }

        break :dir std.Io.Dir.cwd().openDir(ctx.io, ctx.scan_dir_path, .{ .iterate = true }) catch |e| {
            ctx.err("Unable to open input dir '{s}', error: '{s}'", .{ ctx.scan_dir_path, @errorName(e) });
            return error.InvalidInputScanDir;
        };
    };
    defer ctx.scan_dir.close(ctx.io);

    ctx.output_dir = dir: {
        if (pathIsAbsolute(ctx.options.output_dir)) {
            ctx.output_dir_path = try allocator.dupe(u8, ctx.options.output_dir);
        } else {
            ctx.output_dir_path = try pathResolve(allocator, &.{ cwd, ctx.options.output_dir });
        }

        break :dir std.Io.Dir.cwd().openDir(ctx.io, ctx.output_dir_path, .{ .iterate = true }) catch |e| switch (e) {
            error.FileNotFound => blk: {
                ctx.verbose("Creating output dir: '{s}'", .{ctx.output_dir_path});

                break :blk std.Io.Dir.cwd().createDirPathOpen(ctx.io, ctx.output_dir_path, .{}) catch |de| {
                    ctx.err("Unable to creat output dir '{s}', error: '{s}'", .{ ctx.output_dir_path, @errorName(de) });
                    return de;
                };
            },

            else => {
                ctx.err("Unable to open output dir '{s}', error: '{s}'", .{ ctx.output_dir_path, @errorName(e) });
                return error.InvalidOutputDir;
            },
        };
    };
    defer ctx.output_dir.close(ctx.io);

    ctx.debug("input_scan_dir: '{s}'", .{ctx.scan_dir_path});
    ctx.debug("output_dir: '{s}'", .{ctx.output_dir_path});

    var ts_file_opt = try readTimestampFile(ctx, arena);
    defer if (ts_file_opt) |*ts_file| ts_file.deinit(ctx);

    const input_files = try collectInputFiles(ctx, arena);

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
                        const status = try outputFileStatus(ctx, output_file_path, input_file.timestamp);
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

    const cpu_count = std.Thread.getCpuCount() catch 1;
    const max_threads = if (ctx.options.max_threads == 0)
        cpu_count
    else
        @min(ctx.options.max_threads, cpu_count);

    const mem_per_task = 1 * mem.MiB;
    const pool_size = @min(files_to_compile.items.len, max_threads);
    const mem_pool = try allocator.alloc([mem_per_task]u8, pool_size);
    const pool_free_index_buf = try allocator.alloc(usize, pool_size);
    var pool_free_index_stack = std.ArrayList(usize).initBuffer(pool_free_index_buf);
    for (0..pool_size) |i| pool_free_index_stack.appendAssumeCapacity((pool_size - 1) - i);

    ctx.verbose("start compile tasks, pool_size: {}, task_count: {}", .{ pool_size, files_to_compile.items.len });

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
                const output_or_err = compile(a.ctx, a.input_file, &mp[pool_index], &perf_timers);

                a.input_file.result_opt = CompileResult{
                    .perf_timers = perf_timers,
                    .output_or_err = if (output_or_err) |output| blk: {
                        a.main_arena_mutex.lockUncancelable(a.ctx.io);
                        {
                            defer a.main_arena_mutex.unlock(a.ctx.io);
                            break :blk output.dupe(a.main_arena);
                        }
                    } else |err| err,
                };
            }
        }.run, .{ args, mem_pool });
    }

    try g.await(ctx.io);

    var total_durations = PerfTimers{};

    var errors = false;

    for (input_files) |*input_file| {
        const outputs = if (input_file.result_opt) |result| blk: {
            total_durations.add(&result.perf_timers);

            if (result.output_or_err) |output| {
                input_file.skip = output.skip;
                break :blk output.files;
            } else |err| {
                errors = true;

                ctx.err("Error compiling input: '{s}', error: '{s}'", .{ input_file.path, @errorName(err) });

                break :blk switch (err) {
                    error.OutputMissing => &.{},
                    else => input_file.old_outputs,
                };
            }
        } else input_file.old_outputs;

        for (outputs) |output_file_path| {
            try all_output_files.putNoClobber(ctx.gpa, output_file_path, undefined);
        }
    }

    try writeTimestampFile(ctx, timestamp_file_sub_path, input_files);

    // TODO: Attempt to remove any file in the output dir that's missing from all_output_files

    const total_time = start_time.untilNow(ctx.io);
    ctx.info("compile             | {f}", .{fmtAlt(total_durations.total_run, .formatColumns)});
    ctx.info("aseprite            | {f}", .{fmtAlt(total_durations.aseprite_run, .formatColumns)});
    ctx.info("output verification | {f}", .{fmtAlt(total_durations.output_verification, .formatColumns)});
    ctx.info("total wall          | {f}", .{fmtAlt(total_time, .formatColumns)});

    if (errors) return error.SomeInputsFailed;
}

const CompileError = AsepriteError || mem.Arena.Error || error{ OutputNameTooLong, OutputMissing };

fn compile(ctx: *Context, input_file: *const InputFile, task_mem: []u8, perf_timers: *PerfTimers) CompileError!CompileOutput {
    const start = PerfTs.now(ctx.io);
    defer perf_timers.total_run.add(start.untilNow(ctx.io));

    const arena_size = task_mem.len / 2;
    assert(arena_size >= 512 * mem.KiB);

    var result_arena = try mem.Arena.init(.{ .slice = .{ .data = task_mem[0..arena_size] } });
    var tmp_arena = try mem.Arena.init(.{ .slice = .{ .data = task_mem[arena_size..] } });

    const arena = result_arena.allocator();
    const tmp = mem.TempArena.init(&tmp_arena);

    ctx.verbose("compiling: '{s}'", .{input_file.abs_path});

    const tags = try asepriteTags(ctx, tmp.arena, &result_arena, input_file.abs_path, perf_timers);

    var output_file_paths: [][]const u8 = &.{};

    if (!tags.skip) {
        const rel_dir_path = dirname(input_file.path) orelse "";

        var name_buf: [std.Io.Dir.max_name_bytes]u8 = undefined;

        output_file_paths = if (tags.split_layers) blk: {
            const layers = try asepriteLayers(ctx, tmp.arena, &result_arena, input_file, perf_timers);

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

            _ = try asepriteExportSplitLayerBMP(ctx, tmp.arena, &result_arena, input_file, rel_dir_path, perf_timers);

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

            _ = try asepriteExportBMP(ctx, tmp.arena, &result_arena, input_file, rel_out_path, perf_timers);

            break :blk try arena.dupe([]const u8, &.{rel_out_path});
        };
    } else {
        ctx.verbose("Skipping: '{s}' (skip tag found)", .{input_file.abs_path});
    }

    const verify_start = PerfTs.now(ctx.io);
    {
        defer perf_timers.output_verification.add(verify_start.untilNow(ctx.io));
        for (output_file_paths) |output_file_path| {
            _ = ctx.output_dir.statFile(ctx.io, output_file_path, .{}) catch |e| switch (e) {
                error.FileNotFound => {
                    ctx.err("Output file missing after compilation, input: '{s}', output: '{s}'", .{ input_file.path, output_file_path });
                    return error.OutputMissing;
                },

                else => {
                    ctx.err("Ouput file verification (stat) failed, output: '{s}', error: '{s}'", .{ output_file_path, @errorName(e) });
                },
            };
        }
    }

    return .{ .skip = tags.skip, .files = output_file_paths };
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

fn readTimestampFile(ctx: *Context, arena: *mem.Arena) !?TimestampFile {
    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    const allocator = _arena.a;
    var tmp = mem.getScratch(allocator);
    defer tmp.release();

    const rel_path = timestamp_file_sub_path;

    const timestamp: std.Io.Timestamp = if (ctx.output_dir.statFile(ctx.io, rel_path, .{})) |stat|
        stat.mtime
    else |_| {
        return null;
    };

    ctx.debug("Reading timestamp file", .{});

    var inputs: std.StringHashMapUnmanaged(TimestampFile.Input) = .empty;
    errdefer inputs.deinit(ctx.gpa);

    const ts_file = ctx.output_dir.openFile(ctx.io, rel_path, .{ .mode = .read_only }) catch |e| {
        const full_path = try std.fs.path.resolve(tmp.a, &.{ ctx.output_dir_path, rel_path });
        ctx.err("Unable to open timestamp file for reading: '{s}', error: '{s}'", .{ full_path, @errorName(e) });
        return error.ReadTimestampFile;
    };
    defer ts_file.close(ctx.io);

    // Should be big enough to fit an entire line
    var read_buf: [std.Io.Dir.max_path_bytes + 16]u8 = undefined;
    var reader = ts_file.reader(ctx.io, &read_buf);

    var current_input: ?[]const u8 = null;
    var current_outputs: std.ArrayList([]const u8) = .empty;

    var line_n: usize = 1;

    while (reader.interface.takeDelimiter('\n') catch |e| {
        const full_path = try std.fs.path.resolve(tmp.a, &.{ ctx.output_dir_path, rel_path });
        switch (e) {
            error.ReadFailed => ctx.err("Unable to read timestamp file: '{s}', error: '{s}'", .{ full_path, @errorName(e) }),
            error.StreamTooLong => ctx.err("Timestamp line {} longer than expected max, timestamp file: '{s}'", .{ line_n, full_path }),
        }
        return error.ReadTimestampFile;
    }) |raw_line| : (line_n += 1) {
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

pub fn writeTimestampFile(ctx: *Context, rel_path: []const u8, input_files: []const InputFile) !void {
    if (ctx.output_dir.createFile(ctx.io, rel_path, .{ .truncate = true })) |timestamp_file| {
        defer timestamp_file.close(ctx.io);

        var write_buf: [4096]u8 = undefined;
        var file_writer = timestamp_file.writer(ctx.io, &write_buf);
        const writer = &file_writer.interface;

        for (input_files) |*input_file| {
            if (input_file.skip) {
                try writer.print("s:{s}\n", .{input_file.path});
            } else {
                const outputs_opt = if (input_file.result_opt) |result_or_err|
                    // Failed inputs are omitted to force retry on next run
                    // Old outputs for failed inputs are still recorded in all_output_files, so --clean does not remove them
                    if (result_or_err.output_or_err) |output| output.files else |_| null
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
        ctx.err("unable to open timestamp file for writing '{s}/{s}', error: '{s}'", .{ ctx.output_dir_path, rel_path, @errorName(e) });
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
    output_or_err: CompileError!CompileOutput,

    perf_timers: PerfTimers,
};

pub const CompileOutput = struct {
    skip: bool,
    files: []const []const u8,

    pub inline fn dupe(this: *const CompileOutput, allocator: Allocator) !CompileOutput {
        var result = this.*;

        const files = try allocator.alloc([]const u8, this.files.len);
        for (this.files, files) |source, *dest| {
            dest.* = try allocator.dupe(u8, source);
        }
        result.files = files;

        return result;
    }
};

pub const PerfTimers = struct {
    total_run: PerfDuration = .zero,
    aseprite_run: PerfDuration = .zero,
    output_verification: PerfDuration = .zero,

    pub inline fn add(this: *PerfTimers, other: *const PerfTimers) void {
        this.total_run.add(other.total_run);
        this.aseprite_run.add(other.aseprite_run);
        this.output_verification.add(other.output_verification);
    }
};

fn collectInputFiles(ctx: *const Context, arena: *mem.Arena) ![]InputFile {
    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    const allocator = _arena.a;
    var tmp = mem.getScratch(allocator);
    defer tmp.release();

    ctx.debug("Collecting input files...", .{});

    var input_files: std.ArrayList(InputFile) = .empty;

    var walker = try ctx.scan_dir.walk(tmp.a);
    while (try walker.next(ctx.io)) |entry| {
        if (entry.kind == .file) {
            if (std.mem.eql(u8, ".aseprite", extension(entry.basename))) {
                const tmp_input_path = try tmp.a.dupe(u8, entry.path);
                const abs_path = try pathJoin(allocator, &.{ ctx.scan_dir_path, tmp_input_path });
                const path = abs_path[abs_path.len - tmp_input_path.len ..];
                const stat = try ctx.scan_dir.statFile(ctx.io, entry.path, .{});

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

fn outputFileStatus(ctx: *const Context, dir_rel_path: []const u8, input_timestamp: std.Io.Timestamp) !OutputFileStatus {
    const result: OutputFileStatus = if (ctx.output_dir.statFile(ctx.io, dir_rel_path, .{})) |stat|
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

pub const AsepriteError = error{ AsepriteRunFailed, CreateOutputDirFailed } ||
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
    perf_timers.aseprite_run.add(run_duration);

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
fn asepriteLayers(ctx: *Context, arena: *mem.Arena, tmp_arena: *mem.Arena, input_file: *const InputFile, perf_timers: *PerfTimers) AsepriteError![]const []const u8 {
    assert(pathIsAbsolute(input_file.abs_path));

    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    const allocator = _arena.a;
    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const layers_rr = try aseprite(ctx, tmp.arena, arena, &.{ "-b", "--all-layers", "--list-layer-hierarchy", input_file.abs_path }, perf_timers);

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

fn asepriteExportBMP(ctx: *Context, arena: *mem.Arena, tmp_arena: *mem.Arena, input_file: *const InputFile, rel_output_path: []const u8, perf_timers: *PerfTimers) AsepriteError!void {
    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const abs_output_path = try pathJoin(tmp.a, &.{ ctx.output_dir_path, rel_output_path });

    assert(pathIsAbsolute(input_file.abs_path));
    assert(pathIsAbsolute(abs_output_path));

    if (dirname(rel_output_path)) |output_sub_dir_path| {
        ctx.output_dir.createDirPath(ctx.io, output_sub_dir_path) catch return error.CreateOutputDirFailed;
    }

    _ = try aseprite(ctx, tmp.arena, arena, &.{ "-b", input_file.abs_path, "--save-as", abs_output_path }, perf_timers);
}

fn asepriteExportSplitLayerBMP(ctx: *Context, arena: *mem.Arena, tmp_arena: *mem.Arena, input_file: *const InputFile, rel_output_dir_path: []const u8, perf_timers: *PerfTimers) AsepriteError!void {
    assert(pathIsAbsolute(input_file.abs_path));

    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const abs_output_dir_path = try pathJoin(tmp.a, &.{ ctx.output_dir_path, rel_output_dir_path });
    assert(pathIsAbsolute(abs_output_dir_path));

    const out_dir_param = try std.fmt.allocPrint(tmp.a, "out_dir={s}", .{abs_output_dir_path});
    const script_path = try pathJoin(tmp.a, &.{ compile_options.aseprite_script_path, "extract_layers_recursive.lua" });

    if (dirname(rel_output_dir_path)) |output_sub_dir_path| {
        ctx.output_dir.createDirPath(ctx.io, output_sub_dir_path) catch return error.CreateOutputDirFailed;
    }

    _ = try aseprite(ctx, tmp.arena, arena, &.{
        "-b",
        input_file.abs_path,
        "--script-param",
        out_dir_param,
        "--script",
        script_path,
    }, perf_timers);
}
