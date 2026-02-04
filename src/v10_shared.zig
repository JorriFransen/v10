const std = @import("std");
const log = std.log.scoped(.v10_shared);
const options = @import("options");
const v10 = @import("v10.zig");

const assert = std.debug.assert;

pub fn joinPathsZ(buffer: []u8, base: []const u8, sub: []const u8) ![:0]const u8 {
    return std.fmt.bufPrintSentinel(buffer, "{s}" ++ .{std.fs.path.sep} ++ "{s}", .{ base, sub }, 0) catch |e| switch (e) {
        error.NoSpaceLeft => {
            log.err("File path too big! base path: \"{s}\" sub_path: \"{s}\"", .{ base, sub });
            return e;
        },
    };
}

// Note: In the original handmade hero this is in the platform layer, but in zig we can do this (for our current target platforms) in platform agnostic code.
pub const SharedState = struct {
    game_memory_block: []u8 = &.{},

    recording_handle: std.Io.File = undefined,
    recording_reader: std.Io.Reader = undefined,
    input_recording_index: usize = 0,

    playback_handle: std.Io.File = undefined,
    input_playing_index: usize = 0,

    exe_dir_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined,
    exe_dir_path: []const u8 = &.{},

    pub fn buildExePathFilename(shared_state: *const SharedState, buffer: []u8, sub_path: []const u8) ![:0]const u8 {
        return joinPathsZ(buffer, shared_state.exe_dir_path, sub_path) catch |e| switch (e) {
            error.NoSpaceLeft => return e,
        };
    }

    pub fn getInputRecordingPath(shared_state: *const SharedState, buffer: []u8, recording_index: usize) [:0]const u8 {
        _ = recording_index;
        return shared_state.buildExePathFilename(buffer, "input_recording.hmi") catch @panic("File path too big!");
    }

    pub fn beginRecordingInput(shared_state: *SharedState, io: std.Io, input_recording_index: usize) void {
        shared_state.input_recording_index = input_recording_index;

        var filename_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const filename = shared_state.getInputRecordingPath(&filename_buf, input_recording_index);

        shared_state.recording_handle = std.Io.Dir.createFileAbsolute(io, filename, .{ .truncate = true }) catch @panic("Input recording createFile failed");

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

        var filename_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const filename = shared_state.getInputRecordingPath(&filename_buf, input_playing_index);

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

        const bytes_read = shared_state.playback_handle.readStreaming(io, &.{@as([]u8, @ptrCast(input))}) catch |e| switch (e) {
            error.EndOfStream => 0,
            else => @panic("Input playback read failed"),
        };

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

    init: ?v10.FN_init = null,
    updateAndRender: ?v10.FN_updateAndRender = null,
    getAudioFrames: ?v10.FN_getAudioFrames = null,

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

pub fn getLastWriteTime(io: std.Io, absolute_file_name: []const u8) i128 {
    var result: i128 = 0;

    switch (@import("builtin").os.tag) {
        .windows => {
            const win32 = @import("win32/win32.zig");
            var data: win32.FILE_ATTRIBUTE_DATA = undefined;
            if (win32.GetFileAttributesExA(@ptrCast(absolute_file_name), .standard, &data) == win32.TRUE) {
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
