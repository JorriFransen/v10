const std = @import("std");
const log = std.log.scoped(.v10_shared);
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");

const mem = @import("mem");
const asset_compiler = @import("asset_compiler");
const options = @import("options");
const v10 = @import("v10.zig");
const DynLib = @import("dynlib");

const assert = std.debug.assert;

pub const std_options: std.Options = .{
    .log_level = std.log.default_level,
    .log_scope_levels = &.{
        .{
            .scope = .asset_compiler,
            .level = if (options.tools_optimize == .Debug) .debug else .info,
        },
    },
};

pub const ThreadContext = extern struct {
    io: *const std.Io,
};

pub const FN_updateAndRender = *const fn (thread_context: *const ThreadContext, memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer) callconv(.c) void;
pub const FN_getAudioFrames = *const fn (thread_context: *const ThreadContext, memory: *Memory, sound_buffer: *const AudioBuffer) callconv(.c) void;

pub const OffscreenBuffer = extern struct {
    memory: [*]u8,
    memory_len: usize,
    width: u32,
    height: u32,
    pitch: i32,
    bytes_per_pixel: i32,
};

pub const AudioBuffer = extern struct {
    pub const Sample = i16;
    pub const Frame = struct {
        left: Sample = 0,
        right: Sample = 0,
    };

    frames: [*]Frame,
    frames_len: usize,
    frames_per_second: u32,
};

pub const ButtonState = extern struct {
    half_transition_count: i32 = 0,
    ended_down: bool = false,
};

pub const ControllerInput = extern struct {
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

pub const DebugMouseInput = extern struct {
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

pub const Input = extern struct {
    debug_mouse: DebugMouseInput = undefined,

    dt: f32 = 0,
    controllers: [5]ControllerInput = @splat(std.mem.zeroes(ControllerInput)),
};

pub const Memory = extern struct {
    initialized: bool = false,
    permanent: [*]u8 = &.{},
    permanent_len: usize,
    transient: [*]u8 = &.{},
    transient_len: usize,

    debug: DEBUG,
};

pub const DEBUG = extern struct {
    pub const ReadFileResult = extern struct {
        size: usize = 0,
        content: *anyopaque = undefined,

        pub inline fn slice(this: ReadFileResult) []u8 {
            return @as([*]u8, @ptrCast(this.content))[0..this.size];
        }
    };

    readEntireFile: *const fn (thread_context: *ThreadContext, path: [*:0]const u8, path_len: usize) callconv(.c) ReadFileResult = undefined,
    freeFileMemory: *const fn (thread_context: *ThreadContext, memory: ?[*]const u8, size: usize) callconv(.c) void = undefined,
    writeEntireFile: *const fn (thread_context: *ThreadContext, path: [*:0]const u8, path_len: usize, memory: [*]const u8, size: usize) callconv(.c) bool = undefined,
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
            log.debug("Loaded game code", .{});
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
                result = @as(u64, @bitCast(data.last_write_time));
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

pub inline fn runAssetCompiler(io: std.Io, stderr: *std.Io.Writer, stdout: *std.Io.Writer) !void {
    if (options.internal_build and !options.cross_compile) {
        const init_mem = !mem.temp_initialized;
        if (init_mem) mem.init();
        defer if (init_mem) mem.deinit();

        var arena = try mem.Arena.init(.{ .virtual = .{} });
        defer arena.deinit() catch {};

        const context = asset_compiler.Context{
            .io = io,
            .arena = arena.allocator(),
            .stderr = stderr,
            .stdout = stdout,
            .verbose = true,
        };
        try asset_compiler.run(&context, .{ .input_scan_dir = ".", .output_dir = "./test", .verbose = true });
    }
}
