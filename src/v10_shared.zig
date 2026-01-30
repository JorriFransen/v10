const std = @import("std");
const log = std.log.scoped(.v10_shared);
const options = @import("options");
const v10 = @import("v10.zig");

const assert = std.debug.assert;

// Note: In the original handmade hero this is in the platform layer, but in zig we can do this (for our current target platforms) in platform agnostic code.
pub const SharedState = struct {
    game_memory_block: []u8 = &.{},

    recording_handle: std.Io.File = undefined,
    recording_reader: std.Io.Reader = undefined,
    input_recording_index: usize = 0,

    playback_handle: std.Io.File = undefined,
    input_playing_index: usize = 0,

    pub fn beginRecordingInput(shared_state: *SharedState, io: std.Io, input_recording_index: usize) void {
        shared_state.input_recording_index = input_recording_index;

        const filename = "foo.hmi";
        shared_state.recording_handle = std.Io.Dir.cwd().createFile(io, filename, .{ .truncate = true }) catch @panic("Input recording createFile failed");

        shared_state.recording_handle.writeStreamingAll(io, shared_state.game_memory_block) catch @panic("Input recording memory write failed");
    }

    pub fn endRecordingInput(shared_state: *SharedState, io: std.Io) void {
        if (shared_state.input_recording_index > 0) {
            shared_state.recording_handle.close(io);
        }
        shared_state.input_recording_index = 0;
    }

    pub fn beginInputPlayback(shared_state: *SharedState, io: std.Io, input_playing_index: usize) void {
        shared_state.input_playing_index = input_playing_index;

        const filename = "foo.hmi";
        shared_state.playback_handle = std.Io.Dir.cwd().openFile(io, filename, .{}) catch @panic("Input playback openFile failed");

        var total_read: usize = 0;
        while (total_read < shared_state.game_memory_block.len) {
            const read = shared_state.playback_handle.readStreaming(io, &.{shared_state.game_memory_block[total_read..]}) catch @panic("Input playback memory read failed");
            total_read += read;
        }
    }

    pub fn endInputPlayback(shared_state: *SharedState, io: std.Io) void {
        if (shared_state.input_playing_index > 0) {
            shared_state.playback_handle.close(io);
        }
        shared_state.input_playing_index = 0;
    }

    pub fn recordInput(shared_state: *SharedState, io: std.Io, input: *v10.Input) void {
        shared_state.recording_handle.writeStreamingAll(io, &std.mem.toBytes(input.*)) catch @panic("Input recording write failed");
    }

    pub fn playbackInput(shared_state: *SharedState, io: std.Io, input: *v10.Input) void {
        _ = .{ shared_state, input };

        const bytes_read = shared_state.playback_handle.readStreaming(io, &.{@as([]u8, @ptrCast(input))}) catch @panic("Input playback read failed");
        if (bytes_read == 0) {
            const index = shared_state.input_playing_index;

            shared_state.endInputPlayback(io);
            shared_state.beginInputPlayback(io, index);

            _ = shared_state.playback_handle.readStreaming(io, &.{@as([]u8, @ptrCast(input))}) catch @panic("Input playback read failed");
        }
    }
};

pub const GameCode = struct {
    valid: bool = false,
    dll: ?std.DynLib = null,
    last_write_time: i128 = 0,

    init: v10.FN_init = v10.initStub,
    updateAndRender: v10.FN_updateAndRender = v10.updateAndRenderStub,
    getAudioFrames: v10.FN_getAudioFrames = v10.getAudioFramesStub,

    pub fn load(io: std.Io, libname: []const u8) GameCode {
        const last_write_time = getLastWriteTime(io, libname);

        var lib = std.DynLib.open(libname) catch |e| {
            log.err("Failed to load game code: {}", .{e});
            return .{};
        };

        const init = lib.lookup(v10.FN_init, "init");
        const update_and_render = lib.lookup(v10.FN_updateAndRender, "updateAndRender");
        const get_audio_frames = lib.lookup(v10.FN_getAudioFrames, "getAudioFrames");

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

    pub fn unload(game_code: *GameCode) void {
        if (game_code.dll) |*lib| {
            lib.close();
        }
    }
};

pub fn getLastWriteTime(io: std.Io, file_name: []const u8) i128 {
    var result: i128 = 0;

    if (std.Io.Dir.cwd().openFile(io, file_name, .{ .mode = .read_only })) |dll_file| {
        if (dll_file.stat(io)) |stat| {
            result = stat.mtime.toNanoseconds();
        } else |_| {}
        dll_file.close(io);
    } else |_| {}

    return result;
}
