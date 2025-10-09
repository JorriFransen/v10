const std = @import("std");
const log = std.log.scoped(.v10_shared);
const options = @import("options");

const assert = std.debug.assert;

pub const GameCode = struct {
    valid: bool = false,
    dll: ?std.DynLib = null,
    last_write_time: i128 = 0,

    init: FN_init = initStub,
    updateAndRender: FN_updateAndRender = updateAndRenderStub,
    getAudioFrames: FN_getAudioFrames = getAudioFramesStub,
};

pub fn getLastWriteTime(file_name: []const u8) i128 {
    var result: i128 = 0;

    if (std.fs.cwd().openFile(file_name, .{ .mode = .read_only })) |dll_file| {
        if (dll_file.stat()) |stat| {
            result = stat.mtime;
        } else |_| {}
        dll_file.close();
    } else |_| {}

    return result;
}

pub fn loadGameCode(libname: []const u8) GameCode {
    const last_write_time = getLastWriteTime(libname);
    var lib = std.DynLib.open(libname) catch |e| {
        log.err("Failed to load game code: {}", .{e});
        return .{};
    };

    const init = lib.lookup(FN_init, "init");
    const update_and_render = lib.lookup(FN_updateAndRender, "updateAndRender");
    const get_audio_frames = lib.lookup(FN_getAudioFrames, "getAudioFrames");

    const valid =
        init != null and
        update_and_render != null and
        get_audio_frames != null;

    if (valid) {
        return .{
            .valid = true,
            .dll = lib,
            .last_write_time = last_write_time,
            .init = init.?,
            .updateAndRender = update_and_render.?,
            .getAudioFrames = get_audio_frames.?,
        };
    } else {
        if (options.internal_build) @panic("Missing function in game dll");
        return .{}; // TODO: Probably show a message and exit here
    }
}

pub fn unloadGameCode(game_code: *GameCode) void {
    if (game_code.dll) |*lib| {
        lib.close();
    }
}

pub const FN_init = *const @TypeOf(initStub);
pub fn initStub(memory: *Memory) callconv(.c) void {
    _ = .{memory};
}

pub const FN_updateAndRender = *const @TypeOf(updateAndRenderStub);
pub fn updateAndRenderStub(memory: *Memory, input: *const Input, offscreen_buffer: *OffscreenBuffer) callconv(.c) bool {
    _ = .{ memory, input, offscreen_buffer };
    return true;
}

pub const FN_getAudioFrames = *const @TypeOf(getAudioFramesStub);
pub fn getAudioFramesStub(memory: *Memory, sound_buffer: *AudioBuffer) callconv(.c) void {
    _ = .{ memory, sound_buffer };
}

pub const OffscreenBuffer = struct {
    memory: []u8,
    width: i32,
    height: i32,
    pitch: i32,
};

pub const AudioBuffer = extern struct {
    pub const Sample = i16;
    pub const Frame = extern struct {
        left: Sample = 0,
        right: Sample = 0,
    };

    frames: [*]Frame,
    frame_count: i32,
    frames_per_second: i32,
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

pub const Input = extern struct {
    controllers: [5]ControllerInput = .{std.mem.zeroes(ControllerInput)} ** 5,
};

pub const GameState = extern struct {
    blue_offset: i32 = 0,
    green_offset: i32 = 0,
    tone_hz: i32 = 0,
    t_sine: f32 = 0,
};

pub const Memory = struct {
    initialized: bool = false,
    permanent: []u8 = &.{},
    transient: []u8 = &.{},

    debug: DEBUG,
};

pub const DEBUG = if (options.internal_build) struct {
    pub const ReadFileResult = extern struct {
        size: usize = 0,
        content: *anyopaque = undefined,
    };

    readEntireFile: *const fn (path: [*:0]const u8) callconv(.c) ReadFileResult,
    freeFileMemory: *const fn (memory: ?*anyopaque, size: usize) callconv(.c) void,
    writeEntireFile: *const fn (path: [*:0]const u8, memory: *anyopaque, size: usize) callconv(.c) bool,
} else struct {};
