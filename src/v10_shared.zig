const std = @import("std");
const log = std.log.scoped(.v10_shared);
const options = @import("options");
const v10 = @import("v10.zig");

const assert = std.debug.assert;

// Note: In the original handmade hero this is in the platform layer, but in zig we can do this (for our current target platforms) in platform agnostic code.
pub const GameCode = struct {
    valid: bool = false,
    dll: ?std.DynLib = null,
    last_write_time: i128 = 0,

    init: v10.FN_init = v10.initStub,
    updateAndRender: v10.FN_updateAndRender = v10.updateAndRenderStub,
    getAudioFrames: v10.FN_getAudioFrames = v10.getAudioFramesStub,
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

pub fn loadGameCode(io: std.Io, libname: []const u8) GameCode {
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

pub fn unloadGameCode(game_code: *GameCode) void {
    if (game_code.dll) |*lib| {
        lib.close();
    }
}
