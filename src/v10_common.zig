const std = @import("std");
const log = std.log.scoped(.v10_platform);
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");

const mem = @import("mem");
const options = @import("options");
const DynLib = @import("dynlib");

const TimeParts = @import("timeparts.zig").TimeParts;

const assert = std.debug.assert;

pub const std_log_scope_levels = [_]std.log.ScopeLevel{
    .{ .scope = .v10_platform, .level = .debug },
    .{
        .scope = .asset_compiler,
        .level = if (options.tools_optimize == .Debug) .debug else .info,
    },
};

pub const std_options: std.Options = .{
    .log_level = std.log.default_level,
    .log_scope_levels = &std_log_scope_levels,
    .logFn = defaultLog,
};

fn defaultLog(comptime level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);
    var buffer: [64]u8 = undefined;
    const stderr = std.debug.lockStderr(&buffer).terminal();
    defer std.debug.unlockStderr();
    return defaultLogFileTerminal(level, scope, format, args, stderr) catch {};
}
pub fn defaultLogFileTerminal(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
    t: std.Io.Terminal,
) !void {
    const color = switch (level) {
        .err => .red,
        .warn => .yellow,
        .info => .green,
        .debug => .magenta,
    };
    const ts = std.Io.Timestamp.now(std.Options.debug_io, .real);
    const tp = TimeParts.fromMsTimestamp(@bitCast(ts.toMilliseconds()));

    try t.writer.print("{f} ", .{std.fmt.alt(tp, .writeTime)});

    try t.setColor(color);
    try t.setColor(.bold);
    try t.writer.writeAll(level.asText());

    try t.setColor(.dim);
    try t.setColor(.bold);
    if (scope != .default) try t.writer.print("({t})", .{scope});
    try t.writer.writeAll(": ");

    try t.setColor(.reset);
    try t.writer.print(format ++ "\n", args);
}

pub const ThreadContext = struct {
    io: std.Io,
};

pub const FN_updateAndRender = *const fn (thread_context: *const ThreadContext, memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer) callconv(.c) void;
pub const FN_getAudioFrames = *const fn (thread_context: *const ThreadContext, memory: *Memory, sound_buffer: *const AudioBuffer) callconv(.c) void;

pub const OffscreenBuffer = struct {
    memory: [*]u8,
    width: i32,
    height: i32,
    pitch: i32,

    pub const bytes_per_pixel = 4;
};

pub const AudioBuffer = struct {
    pub const Sample = i16;
    pub const Frame = struct {
        left: Sample = 0,
        right: Sample = 0,
    };

    frames: []Frame,
    frames_per_second: u32,
};

pub const ButtonState = extern struct {
    half_transition_count: i32 = 0,
    ended_down: bool = false,
};

pub const ControllerInput = struct {
    is_connected: bool = false,
    is_analog: bool = false,

    stick_average_x: f32 = 0,
    stick_average_y: f32 = 0,

    buttons: extern union {
        array: [12]ButtonState,

        named: extern struct {
            move_up: ButtonState,
            move_down: ButtonState,
            move_left: ButtonState,
            move_right: ButtonState,

            action_up: ButtonState,
            action_down: ButtonState,
            action_left: ButtonState,
            action_right: ButtonState,

            left_shoulder: ButtonState,
            right_shoulder: ButtonState,

            back: ButtonState,
            start: ButtonState,
        },
        comptime {
            const dummy: @This() = std.mem.zeroes(@This());
            assert(dummy.array.len == @typeInfo(@TypeOf(@field(dummy, "named"))).@"struct".fields.len);
        }
    },
};

pub const DebugMouseInput = struct {
    buttons: extern union {
        array: [5]ButtonState,
        named: extern struct {
            left: ButtonState,
            right: ButtonState,
            middle: ButtonState,

            extra0: ButtonState,
            extra1: ButtonState,
        },

        comptime {
            const dummy: @This() = std.mem.zeroes(@This());
            assert(dummy.array.len == @typeInfo(@TypeOf(@field(dummy, "named"))).@"struct".fields.len);
        }
    } = std.mem.zeroes(@FieldType(@This(), "buttons")),

    x: i32 = 0,
    y: i32 = 0,
    z: i32 = 0,
};

pub const Input = struct {
    debug_mouse: DebugMouseInput = undefined,

    executable_reloaded: bool = false,
    dt: f32 = 0,
    controllers: [5]ControllerInput = @splat(std.mem.zeroes(ControllerInput)),
};

pub const Memory = struct {
    initialized: bool = false,
    permanent: []u8 = &.{},
    transient: []u8 = &.{},

    debug: DEBUG,
};

pub const DEBUG = struct {
    pub const ReadFileResult = []u8;

    readEntireFile: *const fn (thread_context: *ThreadContext, path: [:0]const u8) ReadFileResult = undefined,
    freeFileMemory: *const fn (thread_context: *ThreadContext, memory: []const u8) void = undefined,
    writeEntireFile: *const fn (thread_context: *ThreadContext, path: [:0]const u8, data: []const u8) bool = undefined,
};

pub fn joinPathsZ(buffer: []u8, base: []const u8, sub: []const u8) ![:0]const u8 {
    return std.fmt.bufPrintSentinel(buffer, "{s}" ++ .{std.fs.path.sep} ++ "{s}", .{ base, sub }, 0) catch |e| switch (e) {
        error.NoSpaceLeft => {
            log.err("File path too big! base path: \"{s}\" sub_path: \"{s}\"", .{ base, sub });
            return e;
        },
    };
}

pub const ReplayBuffer = struct {
    file_handle: std.Io.File,
    memory_map: std.Io.File,
    filname_buf: [std.Io.Dir.max_path_bytes]u8 = @splat(0),
    memory: []u8 = &.{},
};

pub const SharedState = struct {
    game_memory_block: []u8 = &.{},
    replay_buffers: [4]ReplayBuffer = undefined,

    recording_handle: std.Io.File = undefined,
    input_recording_index: usize = 0,

    playback_handle: std.Io.File = undefined,
    input_playing_index: usize = 0,

    cwd_buf: [std.Io.Dir.max_path_bytes]u8 = @splat(0),
    cwd: []const u8 = &.{},
    exe_dir_path_buf: [std.Io.Dir.max_path_bytes]u8 = @splat(0),
    exe_dir_path: []const u8 = &.{},

    pub fn buildExePathFilename(shared_state: *const SharedState, buffer: []u8, sub_path: []const u8) ![:0]const u8 {
        return joinPathsZ(buffer, shared_state.exe_dir_path, sub_path) catch |e| switch (e) {
            error.NoSpaceLeft => return e,
        };
    }

    pub fn getInputRecordingPath(shared_state: *const SharedState, buffer: []u8, input_stream: bool, recording_index: usize) [:0]const u8 {
        var name_buf: [128]u8 = undefined;

        var index = recording_index;

        // zero index is a special value
        if (input_stream) {
            assert(index > 0);
            index -= 1;
        }

        const name = std.fmt.bufPrintSentinel(
            &name_buf,
            "input_recording_{}_{s}.hmi",
            .{ index, if (input_stream) "input" else "state" },
            0,
        ) catch @panic("Input recording file name generation failed!");

        return shared_state.buildExePathFilename(buffer, name) catch @panic("File path too big!");
    }

    pub fn getReplayBuffer(shared_state: *SharedState, index: usize) *ReplayBuffer {
        assert(index < shared_state.replay_buffers.len);
        return &shared_state.replay_buffers[index - 1];
    }
};

pub const GameCode = struct {
    valid: bool = false,
    dll: ?DynLib = null,
    last_write_time: i128 = 0,

    updateAndRender: ?FN_updateAndRender = null,
    getAudioFrames: ?FN_getAudioFrames = null,

    pub fn load(io: std.Io, libname: []const u8) GameCode {
        const last_write_time = getLastWriteTime(io, libname);

        var lib = DynLib.open(libname) catch |e| {
            log.err("Failed to load game code: {}", .{e});
            return .{};
        };

        const update_and_render = lib.lookup(FN_updateAndRender, "updateAndRender");
        const get_audio_frames = lib.lookup(FN_getAudioFrames, "getAudioFrames");

        const valid =
            update_and_render != null and
            get_audio_frames != null;

        if (valid) {
            log.info("Loaded game code", .{});
            return .{
                .valid = true,
                .dll = lib,
                .last_write_time = last_write_time,
                .updateAndRender = update_and_render.?,
                .getAudioFrames = get_audio_frames.?,
            };
        } else {
            if (options.internal_build) @panic("Missing function in game dll");
            return .{}; // TODO: Probably show a message and exit here
        }
    }

    pub fn unload(game_code: *GameCode) void {
        if (game_code.dll) |*lib| {
            lib.close();
        }
    }
};

pub fn getLastWriteTime(io: std.Io, absolute_file_name: []const u8) i128 {
    var result: i128 = 0;

    switch (builtin.os.tag) {
        .windows => {
            const win32 = @import("win32");
            var data: win32.FILE_ATTRIBUTE_DATA = undefined;
            if (win32.GetFileAttributesExA(@ptrCast(absolute_file_name), .standard, &data).toBool()) {
                const lwt = win32.LARGE_INTEGER{ .u = .{ .low_part = data.last_write_time.low_date_time, .high_part = @bitCast(data.last_write_time.high_date_time) } };
                result = @intCast(lwt.quad_part);
            }
        },

        else => {
            if (std.Io.Dir.statFile(undefined, io, absolute_file_name, .{})) |stat| {
                result = stat.mtime.toNanoseconds();
            } else |_| {}
        },
    }
    return result;
}

pub inline fn runAssetCompiler(io: std.Io, gpa: Allocator, stderr: *std.Io.Writer, stdout: *std.Io.Writer) !void {
    if (options.internal_build) {
        if (options.run_asset_compiler) {
            const asset_compiler = @import("asset_compiler");

            const init_mem = !mem.temp_initialized;
            if (init_mem) mem.init();
            defer if (init_mem) mem.deinit();

            var arena = try mem.Arena.init(.{ .virtual = .{} });
            defer arena.deinit() catch {};

            var context = asset_compiler.Context{
                .io = io,
                .arena = arena.allocator(),
                .gpa = gpa,
                .stderr = stderr,
                .stdout = stdout,
                .verbose = true,
            };
            try asset_compiler.run(&context, .{
                .input_scan_dir = options.asset_compiler_scan_dir,
                .output_dir = options.asset_compiler_output_dir,
                .verbose = true,
            });
        }
    }
}
