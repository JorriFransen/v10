const std = @import("std");
const log_scope = .asset_compiler;
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");

const core = @import("core");
const Timestamp = core.time.TimeStamp;
const assert = core.assert;
const fs = core.fs;
const mem = core.mem;

const compile_options = @import("options");

const pathResolve = std.fs.path.resolve;
const extension = std.fs.path.extension;
const dirname = std.fs.path.dirname;
const stem = std.fs.path.stem;
const pathIsAbsolute = std.fs.path.isAbsolute;
const fmtAlt = std.fmt.alt;

const PerfTs = if (compile_options.perf_timers) core.perf.Timestamp else core.perf.VoidTimestamp;
const PerfDuration = if (compile_options.perf_timers) core.perf.Duration else core.perf.VoidDuration;

const OptionParser = core.cli_arg_parser.Parser(&.{
    .string("", "input_scan_dir", 'i', "Directory to scan for input files"),
    .string("", "output_dir", 'o', "Output directory"),
    .bool(false, "clean", 'c', "Remove stale files and directories from output directory (stale outputs from failed inputs are not removed)"),
    .int(usize, 0, "max_threads", 'n', "Max concurrent compilation threads (default to 'std.Thread.getCpuCount() catch 1')"),
    .bool(false, "verbose", 'v', "Verbose output"),
    .bool(false, "debug", 'd', "Debug output"),
    .bool(false, "help", 'h', "Print this help"),
}, .{});

/// Relative to output_dir
const timestamp_file_sub_path = ".timestamps";

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,

    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,

    scan_dir: fs.Dir = undefined,
    output_dir: fs.Dir = undefined,

    scan_dir_path: [:0]const u8 = undefined,
    output_dir_path: [:0]const u8 = undefined,

    options: OptionParser.Options,

    const logFn = if (@hasDecl(@import("root"), "std_options"))
        @import("root").std_options.logFn
    else
        (std.Options{}).logFn;

    inline fn err(_: *const Context, comptime fmt: []const u8, args: anytype) void {
        logFn(.err, log_scope, fmt, args);
    }

    inline fn warn(_: *const Context, comptime fmt: []const u8, args: anytype) void {
        logFn(.warn, log_scope, fmt, args);
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

    const raw_args = try init.minimal.args.toSlice(main_arena.allocator());

    const parser = OptionParser.init(raw_args[0], .{ .err_writer = &stderr_writer.interface });
    const args = parser.parse(main_arena.allocator(), raw_args[1..]) catch |e| switch (e) {
        error.OutOfMemory => return e,
        else => {
            try parser.usage(&stderr_writer.interface);
            return 1;
        },
    };

    if (args.help) {
        try parser.help(&stdout_writer.interface);
        return 0;
    }

    var ctx = Context{
        .io = init.io,
        .gpa = init.gpa,
        .stdout = &stdout_writer.interface,
        .stderr = &stderr_writer.interface,
        .options = args,
    };

    run(&ctx, &main_arena) catch {
        try parser.usage(&stderr_writer.interface);
        return 1;
    };

    return 0;
}

pub fn run(ctx: *Context, arena: *mem.Arena) !void {
    const start_time = PerfTs.now();

    const allocator = arena.allocator();

    if (ctx.options.debug) ctx.options.verbose = true;

    if (ctx.options.input_scan_dir.len == 0) {
        ctx.err("missing argument 'input_scan_dir'", .{});
        return error.MissingInputScanDir;
    }

    if (ctx.options.output_dir.len == 0) {
        ctx.err("missing argument 'output_dir'", .{});
        return error.MissingOutputDir;
    }

    ctx.debug("input_scan_dir: '{s}'", .{ctx.options.input_scan_dir});
    ctx.debug("output_dir: '{s}'", .{ctx.options.output_dir});

    const cwd: [:0]const u8 = try std.process.currentPathAlloc(ctx.io, allocator);

    var tmp = mem.getScratch(allocator);
    defer tmp.release();

    ctx.scan_dir = dir: {
        if (pathIsAbsolute(ctx.options.input_scan_dir)) {
            ctx.scan_dir_path = try allocator.dupeSentinel(u8, ctx.options.input_scan_dir, 0);
        } else {
            const sdp = try pathResolve(tmp.a, &.{ cwd, ctx.options.input_scan_dir });
            ctx.scan_dir_path = try allocator.dupeSentinel(u8, sdp, 0);
        }

        ctx.debug("resolved scan_dir: '{s}'", .{ctx.scan_dir_path});

        break :dir fs.cwd().openDir(ctx.scan_dir_path, .{ .iterate = true, .follow_symlinks = false }) catch |e| {
            ctx.err("Unable to open input dir '{s}', error: '{s}'", .{ ctx.scan_dir_path, @errorName(e) });
            return error.InvalidInputScanDir;
        };
    };
    defer ctx.scan_dir.close();

    ctx.output_dir = dir: {
        if (pathIsAbsolute(ctx.options.output_dir)) {
            ctx.output_dir_path = try allocator.dupeSentinel(u8, ctx.options.output_dir, 0);
        } else {
            const odp = try pathResolve(tmp.a, &.{ cwd, ctx.options.output_dir });
            ctx.output_dir_path = try allocator.dupeSentinel(u8, odp, 0);
        }

        break :dir fs.cwd().openDir(ctx.output_dir_path, .{ .iterate = true, .follow_symlinks = false }) catch |e| switch (e) {
            error.FileNotFound => {
                ctx.verbose("Creating output dir: '{s}'", .{ctx.output_dir_path});

                fs.cwd().createDirParents(ctx.output_dir_path, .{}) catch |de| {
                    ctx.err("Unable to create output dir '{s}', error: '{s}'", .{ ctx.output_dir_path, @errorName(de) });
                    return de;
                };

                break :dir fs.cwd().openDir(ctx.output_dir_path, .{ .iterate = true, .follow_symlinks = false }) catch |de| {
                    ctx.err("Unable to open output dir '{s}', error: '{s}'", .{ ctx.output_dir_path, @errorName(de) });
                    return de;
                };
            },

            else => {
                ctx.err("Unable to open output dir '{s}', error: '{s}'", .{ ctx.output_dir_path, @errorName(e) });
                return error.InvalidOutputDir;
            },
        };
    };
    defer ctx.output_dir.close();

    tmp.release(); // null terminated dir paths.

    ctx.debug("absolute input_scan_dir: '{s}'", .{ctx.scan_dir_path});
    ctx.debug("absolute output_dir: '{s}'", .{ctx.output_dir_path});

    const ts_start = PerfTs.now();
    var ts_file: TimestampFile, const ts_file_exists = if (try readTimestampFile(ctx, arena)) |tsf| .{ tsf, true } else blk: {
        break :blk .{ .{ .timestamp = .zero, .inputs = .empty }, false };
    };
    defer ts_file.deinit(ctx);
    const ts_read_duration = ts_start.untilNow();

    const input_collect_start = PerfTs.now();
    const input_files = try collectInputFiles(ctx, arena);
    const input_collect_duration = input_collect_start.untilNow();

    const input_compare_start = PerfTs.now();
    var force_timestamp_write = false;
    const file_indices_to_compile: []usize = if (ts_file_exists)
        try compareInputFilesAgainstTimestampFile(ctx, arena, ts_file, input_files, &force_timestamp_write)
    else blk: {
        const indices = try allocator.alloc(usize, input_files.len);
        for (indices, 0..) |*dst, i| {
            dst.* = i;
        }
        break :blk indices;
    };
    const input_compare_duration = input_compare_start.untilNow();

    ctx.info("Compiling {} inputs", .{file_indices_to_compile.len});
    var compile_duration: PerfDuration = .{};
    const results = if (file_indices_to_compile.len > 0) blk: {
        const compile_start = PerfTs.now();
        defer compile_duration = compile_start.untilNow();
        break :blk try compile(ctx, allocator, input_files, file_indices_to_compile);
    } else &.{};

    const aggregate_start = PerfTs.now();
    var errors = false;
    var total_durations: PerfTimers = .{};
    var all_output_files: std.StringHashMapUnmanaged(void) = .empty;
    defer all_output_files.deinit(ctx.gpa);

    try all_output_files.putNoClobber(ctx.gpa, timestamp_file_sub_path, undefined);

    if (file_indices_to_compile.len > 0) {
        const err_opt = try aggregate(ctx, input_files, ts_file, results, &total_durations, &all_output_files);
        errors = err_opt != null;
    } else {
        for (input_files) |*input_file| {
            if (ts_file.inputs.get(input_file.path)) |old_input| {
                for (old_input.outputs) |output_file_path| {
                    try all_output_files.putNoClobber(ctx.gpa, output_file_path, undefined);
                }
            }
        }
    }

    const aggregate_duration = aggregate_start.untilNow();

    var timestamp_write_duration: PerfDuration = .{};
    if (force_timestamp_write or file_indices_to_compile.len > 0) {
        const timestamp_write_start = PerfTs.now();
        try writeTimestampFile(ctx, ts_file, input_files, results);
        timestamp_write_duration = timestamp_write_start.untilNow();
    }

    var clean_duration_opt: ?PerfDuration = null;
    if (ctx.options.clean) {
        const clean_start = PerfTs.now();
        try clean(ctx, &all_output_files);
        clean_duration_opt = clean_start.untilNow();
    }

    if (compile_options.perf_timers) {
        const total_time = start_time.untilNow(ctx.io);
        ctx.info("ts file read/parse  | {f}", .{fmtAlt(ts_read_duration, .formatColumns)});
        ctx.info("input collect       | {f}", .{fmtAlt(input_collect_duration, .formatColumns)});
        ctx.info("input compare       | {f}", .{fmtAlt(input_compare_duration, .formatColumns)});
        ctx.info("compile             | {f}", .{fmtAlt(compile_duration, .formatColumns)});
        ctx.info("compile aggregate   | {f}", .{fmtAlt(aggregate_duration, .formatColumns)});
        ctx.info("compile aseprite    | {f}", .{fmtAlt(total_durations.total_run, .formatColumns)});
        ctx.info("aseprite (external) | {f}", .{fmtAlt(total_durations.aseprite_run, .formatColumns)});
        ctx.info("output verification | {f}", .{fmtAlt(total_durations.output_verification, .formatColumns)});
        ctx.info("ts write            | {f}", .{fmtAlt(timestamp_write_duration, .formatColumns)});
        if (clean_duration_opt) |cdo|
            ctx.info("clean               | {f}", .{fmtAlt(cdo, .formatColumns)});
        ctx.info("total wall          | {f}", .{fmtAlt(total_time, .formatColumns)});
    }

    if (errors) return error.SomeInputsFailed;
}

const CompileError = AsepriteError || mem.Arena.Error || fs.Error || error{ OutputNameTooLong, OutputMissing };

fn compile(ctx: *Context, allocator: Allocator, input_files: []const InputFile, indices: []const usize) CompileError![]?CompileResult {
    const cpu_count = std.Thread.getCpuCount() catch 1;
    const max_threads = if (ctx.options.max_threads == 0)
        cpu_count
    else
        @min(ctx.options.max_threads, cpu_count);

    const mem_per_task = 256 * mem.KiB;
    const pool_size = @min(indices.len, max_threads);
    const mem_pool = try allocator.alloc([mem_per_task]u8, pool_size);
    const pool_free_index_buf = try allocator.alloc(usize, pool_size);
    var pool_free_index_stack = std.ArrayList(usize).initBuffer(pool_free_index_buf);
    for (0..pool_size) |i| pool_free_index_stack.appendAssumeCapacity((pool_size - 1) - i);

    ctx.verbose("Start compile tasks, pool_size: {}", .{pool_size});

    var main_arena_mutex = std.Io.Mutex.init;
    var pool_mutex = std.Io.Mutex.init;
    var pool_sem = std.Io.Semaphore{ .permits = pool_size };
    var g = std.Io.Group.init;

    const results_per_input = try allocator.alloc(?CompileResult, input_files.len);
    @memset(results_per_input, null);

    for (indices) |input_index| {
        assert(input_index < input_files.len);

        const Args = struct {
            ctx: *Context,
            input_file: *const InputFile,
            result: *?CompileResult,
            main_arena: Allocator,
            main_arena_mutex: *std.Io.Mutex,

            pool_free_index_stack: *std.ArrayList(usize),
            pool_mutex: *std.Io.Mutex,
            pool_sem: *std.Io.Semaphore,
        };

        const args = Args{
            .ctx = ctx,
            .input_file = &input_files[input_index],
            .result = &results_per_input[input_index],
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
                const output_or_err = asepriteCompile(a.ctx, a.input_file, &mp[pool_index], &perf_timers);

                a.result.* = CompileResult{
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

    return results_per_input;
}

fn aggregate(ctx: *Context, input_files: []const InputFile, ts_file: TimestampFile, results: []const ?CompileResult, total_durations: *PerfTimers, all_output_files: *std.StringHashMapUnmanaged(void)) !?CompileError {
    var result: ?CompileError = null;

    for (input_files, 0..) |*input_file, i| {
        const old_outputs = if (ts_file.inputs.get(input_file.path)) |oi| oi.outputs else &.{};

        const outputs = if (results[i]) |input_result| blk: {
            total_durations.add(&input_result.perf_timers);

            if (input_result.output_or_err) |output| {
                break :blk output.files;
            } else |err| {
                if (result == null) result = err;

                ctx.err("Error compiling input: '{s}', error: '{s}'", .{ input_file.path, @errorName(err) });

                break :blk switch (err) {
                    error.OutputMissing => &.{},
                    else => old_outputs,
                };
            }
        } else blk: {
            break :blk old_outputs;
        };

        for (outputs) |output_file_path| {
            try all_output_files.putNoClobber(ctx.gpa, output_file_path, undefined);
        }
    }

    return result;
}

fn clean(ctx: *Context, all_output_files: *std.StringHashMapUnmanaged(void)) !void {
    const Entry = struct {
        it: std.Io.Dir.Iterator,
        path: []const u8,
        entry_count: u32 = 0,
    };

    var stack: std.ArrayList(Entry) = try .initCapacity(ctx.gpa, 8);
    defer stack.deinit(ctx.gpa);

    try stack.append(ctx.gpa, .{
        .it = ctx.output_dir.stdDir().iterate(),
        .path = "", // To skip close at the end
    });

    while (stack.items.len > 0) {
        var top = &stack.items[stack.items.len - 1];

        if (try top.it.next(ctx.io)) |entry| {
            top.entry_count += 1;

            const full_name = try std.fs.path.join(ctx.gpa, &.{ top.path, entry.name });

            if (entry.kind == .directory) {
                ctx.debug("enter dir: {s}", .{entry.name});
                const dir = try top.it.reader.dir.openDir(ctx.io, entry.name, .{ .iterate = true });
                try stack.append(ctx.gpa, .{ .it = dir.iterateAssumeFirstIteration(), .path = full_name });
            } else {
                ctx.debug("Check output for stale: {s}", .{full_name});
                if (!all_output_files.contains(full_name)) {
                    ctx.debug("Removing stale output: '{s}'", .{entry.name});

                    try top.it.reader.dir.deleteFile(ctx.io, entry.name);
                    top.entry_count -= 1;
                }

                ctx.gpa.free(full_name);
            }
        } else {
            const old_top = stack.pop().?;

            if (old_top.path.len > 0) {
                const new_top = &stack.items[stack.items.len - 1];

                old_top.it.reader.dir.close(ctx.io);

                if (old_top.entry_count == 0) {
                    ctx.debug("Removing empty dir: '{s}'", .{old_top.path});
                    const sub_path = std.fs.path.basename(old_top.path);
                    try new_top.it.reader.dir.deleteDir(ctx.io, sub_path);
                    assert(new_top.entry_count > 0);
                    new_top.entry_count -= 1;
                }

                ctx.gpa.free(old_top.path);
            }
        }
    }
}

fn asepriteCompile(ctx: *Context, input_file: *const InputFile, task_mem: []u8, perf_timers: *PerfTimers) CompileError!CompileOutput {
    const start = PerfTs.now();
    defer perf_timers.total_run.add(start.untilNow());

    const arena_size = task_mem.len / 2;

    var result_arena = try mem.Arena.init(.{ .slice = .{ .data = task_mem[0..arena_size] } });
    var tmp_arena = try mem.Arena.init(.{ .slice = .{ .data = task_mem[arena_size..] } });

    const arena = result_arena.allocator();
    const tmp = mem.TempArena.init(&tmp_arena);

    ctx.debug("Compiling: '{s}'", .{input_file.abs_path});

    const tags = try asepriteTags(ctx, tmp.arena, &result_arena, input_file.abs_path, perf_timers);

    var output_file_paths: [][:0]const u8 = &.{};

    if (!tags.skip) {
        const rel_dir_path = dirname(input_file.path) orelse "";

        var name_buf: [fs.max_name_bytes]u8 = undefined;

        output_file_paths = if (tags.split_layers) blk: {
            const layers = try asepriteLayers(ctx, tmp.arena, &result_arena, input_file, perf_timers);

            const output_filename_prefix = stem(input_file.path);

            const result = try arena.alloc([:0]const u8, layers.len);

            for (layers, result) |l, *output_file_name| {
                const name = std.fmt.bufPrint(&name_buf, "{s}_{s}.bmp", .{ output_filename_prefix, l }) catch |e| switch (e) {
                    error.NoSpaceLeft => {
                        ctx.err("Output file name too long: '{s}_{s}.bmp', input file: '{s}'", .{ output_filename_prefix, l, input_file.abs_path });
                        return error.OutputNameTooLong;
                    },
                };
                output_file_name.* = try std.fs.path.joinZ(arena, &.{ rel_dir_path, name });
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
            const rel_out_path = try std.fs.path.joinZ(arena, &.{ rel_dir_path, out_file_name });

            _ = try asepriteExportBMP(ctx, tmp.arena, &result_arena, input_file, rel_out_path, perf_timers);

            break :blk try arena.dupe([:0]const u8, &.{rel_out_path});
        };
    } else {
        ctx.verbose("Skipping: '{s}' (skip tag found)", .{input_file.abs_path});
    }

    const verify_start = PerfTs.now();
    {
        defer perf_timers.output_verification.add(verify_start.untilNow());
        for (output_file_paths) |output_file_path| {
            if (!try ctx.output_dir.exists(output_file_path)) {
                ctx.err("Output file missing after compilation, input: '{s}', output: '{s}'", .{ input_file.path, output_file_path });
                return error.OutputMissing;
            }
        }
    }

    return .{ .skip = tags.skip, .files = output_file_paths };
}

pub const TimestampFile = struct {
    timestamp: Timestamp,
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

    const timestamp: Timestamp = if (ctx.output_dir.stdDir().statFile(ctx.io, rel_path, .{})) |stat|
        .fromNs(stat.mtime.toNanoseconds())
    else |_| {
        return null;
    };

    ctx.debug("Reading timestamp file", .{});

    var inputs: std.StringHashMapUnmanaged(TimestampFile.Input) = .empty;
    errdefer inputs.deinit(ctx.gpa);

    const ts_file = ctx.output_dir.stdDir().openFile(ctx.io, rel_path, .{ .mode = .read_only }) catch |e| {
        const full_path = try std.fs.path.resolve(tmp.a, &.{ ctx.output_dir_path, rel_path });
        ctx.err("Unable to open timestamp file for reading: '{s}', error: '{s}'", .{ full_path, @errorName(e) });
        return error.ReadTimestampFile;
    };
    defer ts_file.close(ctx.io);

    // Should be big enough to fit an entire line
    var read_buf: [fs.max_path_bytes + 16]u8 = undefined;
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

pub fn writeTimestampFile(ctx: *Context, input_ts_file: TimestampFile, input_files: []const InputFile, results: []const ?CompileResult) !void {
    const rel_path = timestamp_file_sub_path;

    assert(results.len == input_files.len or results.len == 0);

    if (ctx.output_dir.stdDir().createFile(ctx.io, rel_path, .{ .truncate = true })) |timestamp_file| {
        defer timestamp_file.close(ctx.io);

        var write_buf: [4096]u8 = undefined;
        var file_writer = timestamp_file.writer(ctx.io, &write_buf);
        const writer = &file_writer.interface;

        if (results.len > 0) {
            for (input_files, 0..) |*input_file, i| {
                const old_input_opt = input_ts_file.inputs.get(input_file.path);
                const old_outputs = if (old_input_opt) |oi| oi.outputs else &.{};
                const old_skip = if (old_input_opt) |oi| oi.skip else false;

                const outputs_opt, const skip = if (results[i]) |result_or_err|
                    // Failed inputs are omitted to force retry on next run
                    // Old outputs for failed inputs are still recorded in all_output_files, so --clean does not remove them
                    if (result_or_err.output_or_err) |output| .{ output.files, output.skip } else |_| .{ null, false }
                else
                    .{ old_outputs, old_skip };

                if (skip) {
                    try writer.print("s:{s}\n", .{input_file.path});
                } else if (outputs_opt) |outputs| {
                    try writer.print("i:{s}\n", .{input_file.path});
                    for (outputs) |out_file_path| {
                        try writer.print("o:{s}\n", .{out_file_path});
                    }
                }
            }
        } else {
            // Didn't compile anything, rewrite with still existing inputs
            for (input_files) |*input_file| {
                if (input_ts_file.inputs.get(input_file.path)) |old_input| {
                    if (old_input.skip) {
                        try writer.print("s:{s}\n", .{input_file.path});
                    } else {
                        try writer.print("i:{s}\n", .{input_file.path});
                        for (old_input.outputs) |out_file_path| {
                            try writer.print("o:{s}\n", .{out_file_path});
                        }
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

    timestamp: Timestamp,
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
    total_run: PerfDuration = .{},
    aseprite_run: PerfDuration = .{},
    output_verification: PerfDuration = .{},

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

    var walker = try ctx.scan_dir.stdDir().walk(tmp.a);

    while (try walker.next(ctx.io)) |entry| {
        if (entry.kind == .file) {
            if (std.mem.eql(u8, ".aseprite", extension(entry.basename))) {
                const tmp_input_path = try tmp.a.dupe(u8, entry.path);
                const abs_path = try std.fs.path.join(allocator, &.{ ctx.scan_dir_path, tmp_input_path });
                const path = abs_path[abs_path.len - tmp_input_path.len ..];
                const stat = try ctx.scan_dir.stdDir().statFile(ctx.io, entry.path, .{});

                try input_files.append(tmp.a, .{
                    .path = path,
                    .abs_path = abs_path,
                    .timestamp = .fromNs(stat.mtime.toNanoseconds()),
                });
                ctx.debug("  Found input file: '{s}'", .{abs_path});
            }
        }
    }

    return try allocator.dupe(InputFile, input_files.items);
}

fn compareInputFilesAgainstTimestampFile(ctx: *Context, arena: *mem.Arena, ts_file: TimestampFile, input_files: []const InputFile, force_timestamp_write: *bool) ![]usize {
    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();
    const allocator = _arena.a;

    var file_indices_to_compile: std.ArrayList(usize) = .empty;

    ctx.debug("Check found input files against timestamp file...", .{});

    var all_inputs: std.StringHashMapUnmanaged(void) = .empty;
    defer all_inputs.deinit(ctx.gpa);

    for (input_files, 0..) |*input_file, i| {
        try all_inputs.putNoClobber(ctx.gpa, input_file.path, undefined);

        ctx.debug("  Check new input against timestamp file: '{s}'", .{input_file.abs_path});
        if (ts_file.timestamp.ns() <= input_file.timestamp.ns()) {
            // Input newer than timestamp
            ctx.debug("    Input newer than timestamp, recompile: '{s}'", .{input_file.abs_path});
            try file_indices_to_compile.append(allocator, i);
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
                    ctx.debug("    Input has skip tag: '{s}'", .{input_file.abs_path});
                }
            } else {
                // Input newer than output or missing output(s)
                try file_indices_to_compile.append(allocator, i);
            }
        } else {
            // New/unseen input
            ctx.debug("    Input file unknown, compile: '{s}'", .{input_file.abs_path});
            try file_indices_to_compile.append(allocator, i);
        }
    }

    var ts_input_it = ts_file.inputs.keyIterator();
    while (ts_input_it.next()) |ts_input_path| {
        if (!all_inputs.contains(ts_input_path.*)) {
            force_timestamp_write.* = true;
            break;
        }
    }

    return file_indices_to_compile.toOwnedSlice(allocator) catch unreachable;
}

const OutputFileStatus = enum(u2) {
    missing,
    outOfDate,
    upToDate,
};

fn outputFileStatus(ctx: *const Context, dir_rel_path: []const u8, input_timestamp: Timestamp) !OutputFileStatus {
    const result: OutputFileStatus = if (ctx.output_dir.stdDir().statFile(ctx.io, dir_rel_path, .{})) |stat|
        if (stat.mtime.toNanoseconds() <= input_timestamp.ns())
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

pub const AsepriteError = error{
    AsepriteMaxLayerDepthExceeded,
    AsepriteRunFailed,
    CreateOutputDirFailed,
    OutputPathTooLong,
    ScriptPathTooLong,
} ||
    Allocator.Error ||
    std.process.RunError;

const AsepriteArgv = struct {
    values: []const []const u8,

    inline fn args(a: anytype) AsepriteArgv {
        var result: [a.len + 1][]const u8 = undefined;
        const _a: []const []const u8 = a;
        result[0] = compile_options.aseprite_exe_path;
        @memcpy(result[1..], _a);

        return .{ .values = &result };
    }
};

fn aseprite(ctx: *Context, arena: *mem.Arena, tmp_arena: *mem.Arena, args: AsepriteArgv, perf_timers: *PerfTimers) AsepriteError!RunResult {
    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    const allocator = _arena.a;
    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const start_ts = PerfTs.now();
    const result_or_err = std.process.run(tmp.a, ctx.io, .{ .argv = args.values });
    const run_duration = start_ts.untilNow();
    perf_timers.aseprite_run.add(run_duration);

    if (ctx.options.verbose) {
        var buf: [512]u8 = undefined;
        const w = &std.debug.lockStderr(&buf).file_writer.interface;
        defer std.debug.unlockStderr();

        for (args.values, 0..) |a, i| {
            if (i > 0) w.writeByte(' ') catch {};
            w.writeAll(a) catch {};
        }

        if (compile_options.perf_timers) {
            w.print(" ({f})", .{run_duration}) catch {};
        }

        w.writeByte('\n') catch {};
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

    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const tags_rr = try aseprite(ctx, tmp.arena, arena, .args(&.{ "-b", "--list-tags", abs_input_path }), perf_timers);

    var result: AsepriteTags = .{};

    var line_it = std.mem.splitScalar(u8, tags_rr.stdout, '\n');
    while (line_it.next()) |line| {
        const tag = std.mem.trimEnd(u8, line, "\r");
        if (tag.len > 0) {
            if (std.mem.eql(u8, "skip", tag))
                result.skip = true
            else if (std.mem.eql(u8, "split_layers", tag))
                result.split_layers = true
            else
                ctx.warn("Unknown tag '{s}' in '{s}'", .{ tag, abs_input_path });
        }
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

    const layers_rr = try aseprite(ctx, tmp.arena, arena, .args(&.{ "-b", "--all-layers", "--list-layer-hierarchy", input_file.abs_path }), perf_timers);

    var layers: std.ArrayList([]const u8) = .empty;

    var stack_buf: [64][]const u8 = undefined;
    var stack: std.ArrayList([]const u8) = .initBuffer(&stack_buf);

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
                assert(stack.items.len > 0);
                _ = stack.pop();
            }

            if (layer_name[layer_name.len - 1] == '/') {
                stack.appendBounded(layer_name[indent * 2 ..]) catch |e| switch (e) {
                    error.OutOfMemory => {
                        ctx.err("Max layer depth exceeded ({}), input: '{s}'", .{ stack_buf.len, input_file.abs_path });
                        return error.AsepriteMaxLayerDepthExceeded;
                    },
                };
            } else {
                stack.appendBounded(layer_name[indent * 2 ..]) catch |e| switch (e) {
                    error.OutOfMemory => {
                        ctx.err("Max layer depth exceeded ({}), input: '{s}'", .{ stack_buf.len, input_file.abs_path });
                        return error.AsepriteMaxLayerDepthExceeded;
                    },
                };

                const full_layer_name = try std.mem.concat(allocator, u8, stack.items);
                _ = stack.pop();

                std.mem.replaceScalar(u8, full_layer_name, '/', '_');
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

    const abs_output_path = stackPathJoin(&.{ ctx.output_dir_path, rel_output_path }) catch {
        ctx.err("Output path too long: '{f}', input: '{s}'", .{
            std.fs.path.fmtJoin(&.{ ctx.output_dir_path, rel_output_path }),
            input_file.abs_path,
        });
        return error.OutputPathTooLong;
    };

    assert(pathIsAbsolute(input_file.abs_path));
    assert(pathIsAbsolute(abs_output_path));

    if (dirname(rel_output_path)) |output_sub_dir_path| {
        ctx.output_dir.stdDir().createDirPath(ctx.io, output_sub_dir_path) catch return error.CreateOutputDirFailed;
    }

    _ = try aseprite(ctx, tmp.arena, arena, .args(&.{ "-b", input_file.abs_path, "--save-as", abs_output_path }), perf_timers);
}

fn asepriteExportSplitLayerBMP(ctx: *Context, arena: *mem.Arena, tmp_arena: *mem.Arena, input_file: *const InputFile, rel_output_dir_path: []const u8, perf_timers: *PerfTimers) AsepriteError!void {
    assert(pathIsAbsolute(input_file.abs_path));

    var _arena = mem.TempArena.init(arena);
    errdefer _arena.release();

    var tmp = mem.TempArena.init(tmp_arena);
    defer tmp.release();

    const abs_output_dir_path = stackPathJoin(&.{ ctx.output_dir_path, rel_output_dir_path }) catch {
        ctx.err("Output path too long: '{f}', input: '{s}'", .{
            std.fs.path.fmtJoin(&.{ ctx.output_dir_path, rel_output_dir_path }),
            input_file.abs_path,
        });

        return error.OutputPathTooLong;
    };
    assert(pathIsAbsolute(abs_output_dir_path));

    const out_dir_param_fmt = "out_dir={s}";
    var out_dir_param_buf: [fs.max_path_bytes + out_dir_param_fmt.len]u8 = undefined;
    const out_dir_param = std.fmt.bufPrint(&out_dir_param_buf, "out_dir={s}", .{abs_output_dir_path}) catch unreachable;
    const script_path = stackPathJoin(&.{ compile_options.aseprite_script_path, "extract_layers_recursive.lua" }) catch {
        ctx.err("Script path too long: '{f}'", .{std.fs.path.fmtJoin(&.{ ctx.output_dir_path, rel_output_dir_path })});
        return error.ScriptPathTooLong;
    };

    if (dirname(rel_output_dir_path)) |output_sub_dir_path| {
        ctx.output_dir.stdDir().createDirPath(ctx.io, output_sub_dir_path) catch return error.CreateOutputDirFailed;
    }

    _ = try aseprite(ctx, tmp.arena, arena, .args(&.{
        "-b",
        input_file.abs_path,
        "--script-param",
        out_dir_param,
        "--script",
        script_path,
    }), perf_timers);
}

inline fn stackPathJoin(paths: []const []const u8) error{PathTooLong}![]const u8 {
    var path_buf: [fs.max_path_bytes]u8 = undefined;

    return std.fmt.bufPrint(&path_buf, "{f}", .{std.fs.path.fmtJoin(paths)}) catch |e| switch (e) {
        error.NoSpaceLeft => return error.PathTooLong,
    };
}
