const std = @import("std");
pub const log = std.log.scoped(.pulse);
const options = @import("options");

pub const Context = opaque {};
pub const MainLoop = opaque {};
pub const ThreadedMainLoop = opaque {};
pub const MainLoopApi = opaque {};
pub const Stream = opaque {};
pub const Operation = opaque {};

pub const ContextFlags = packed struct(c_int) {
    no_auto_spawn: bool = false,
    no_fail: bool = false,
    __reserved__: u30 = 0,

    pub const no_flags: ContextFlags = .{};
};

pub const SpawnApi = extern struct {
    pre_fork: ?*const fn () callconv(.c) void,
    post_fork: ?*const fn () callconv(.c) void,
    at_fork: ?*const fn () callconv(.c) void,
};

pub const ContextState = enum(c_int) {
    unconnected,
    connecting,
    authorizing,
    setting_name,
    ready,
    failed,
    terminated,

    pub fn int(this: @This()) c_int {
        return @intFromEnum(this);
    }
};

pub const SampleFormat = enum(c_int) {
    u8,
    alaw,
    ulaw,
    s16le,
    s16be,
    float32le,
    float32be,
    s32le,
    s32be,
    s24le,
    s24be,
    s24_32_le,
    s24_32_be,

    invalid = -1,
    pub const max = .s24_32_be;
};

pub const SampleSpec = extern struct {
    format: SampleFormat,
    rate: u32,
    channels: u8,
};

pub const CHANNELS_MAX = 32;

pub const ChannelPosition = enum(c_int) {
    invalid = -1,
    mono = 0,
    front_left,
    front_right,
    front_center,
    rear_center,
    rear_left,
    rear_right,
    lfe,
    front_left_of_center,
    front_right_of_center,
    side_left,
    side_right,
    aux0,
    aux1,
    aux2,
    aux3,
    aux4,
    aux5,
    aux6,
    aux7,
    aux8,
    aux9,
    aux10,
    aux11,
    aux12,
    aux13,
    aux14,
    aux15,
    aux16,
    aux17,
    aux18,
    aux19,
    aux20,
    aux21,
    aux22,
    aux23,
    aux24,
    aux25,
    aux26,
    aux27,
    aux28,
    aux29,
    aux30,
    aux31,
    top_center,
    top_front_left,
    top_front_right,
    top_front_center,
    top_rear_left,
    top_rear_right,
    top_rear_center,
    max,

    pub const left: ChannelPosition = .front_left;
    pub const right: ChannelPosition = .front_right;
    pub const center: ChannelPosition = .front_center;
    pub const subwoofer: ChannelPosition = .lfe;
};

pub const ChannelMap = extern struct {
    channels: u8,
    map: [CHANNELS_MAX]ChannelPosition,
};

pub const BufferAttr = extern struct {
    max_length: u32 = undefined,
    t_length: u32 = undefined,
    pre_buf: u32 = undefined,
    min_req: u32 = undefined,
    frag_size: u32 = undefined,
};

pub const StreamFlags = packed struct(c_int) {
    start_corked: bool = false,
    interpolate_timing: bool = false,
    not_monotonic: bool = false,
    auto_timing_update: bool = false,
    no_remap_channels: bool = false,
    no_remix_channels: bool = false,
    fix_format: bool = false,
    fix_rate: bool = false,
    fix_channels: bool = false,
    dont_move: bool = false,
    variable_rate: bool = false,
    peak_detect: bool = false,
    start_muted: bool = false,
    adjust_latency: bool = false,
    early_requests: bool = false,
    dont_inhibit_auto_suspend: bool = false,
    start_unmuted: bool = false,
    fail_on_suspend: bool = false,
    relative_volume: bool = false,
    stream_passthrough: bool = false,
    __reserved__: u12 = 0,

    pub const no_flags: StreamFlags = .{};
};

pub const Volume = u32;

pub const CVolume = extern struct {
    channels: u8,
    values: [CHANNELS_MAX]Volume,
};

pub const USec = u64;

pub const StreamState = enum(c_int) {
    unconnected,
    creating,
    ready,
    failed,
    terminated,

    pub fn int(this: @This()) c_int {
        return @intFromEnum(this);
    }
};

pub const OperationState = enum(c_int) {
    running,
    done,
    cancelled,
};

pub const SeekMode = enum(c_int) {
    relative = 0,
    absolute = 1,
    relative_on_read = 2,
    relative_end = 3,
};

pub const ErrorCode = enum(c_int) {
    ok = 0,
    access,
    command,
    invalid,
    exist,
    noentity,
    connectionrefused,
    protocol,
    timeout,
    authkey,
    internal,
    connectionterminated,
    killed,
    invalidserver,
    modinitfailed,
    badstate,
    nodata,
    version,
    toolarge,
    notsupported,
    unknown,
    noextension,
    obsolete,
    notimplemented,
    forked,
    io,
    busy,
    max,

    pub fn int(this: @This()) c_int {
        return @intFromEnum(this);
    }
};

pub const FreeCb = *const fn (p: ?*anyopaque) callconv(.c) void;
pub const StreamSuccessCb = *const fn (s: ?*Stream, success: c_int, userdata: ?*anyopaque) callconv(.c) void;
pub const StreamRequestCb = *const fn (p: ?*Stream, nbytes: usize, userdata: ?*anyopaque) callconv(.c) void;
pub const StreamNotifyCb = *const fn (p: ?*Stream, userdata: ?*anyopaque) callconv(.c) void;
pub const ContextNotifyCb = *const fn (c: ?*Context, userdata: ?*anyopaque) callconv(.c) void;

pub var threaded_mainloop_new: *const @TypeOf(threaded_mainloop_new_stub) = undefined;
fn threaded_mainloop_new_stub() callconv(.c) ?*ThreadedMainLoop {
    return null;
}

pub var threaded_mainloop_free: *const @TypeOf(threaded_mainloop_free_stub) = undefined;
fn threaded_mainloop_free_stub(m: ?*ThreadedMainLoop) callconv(.c) void {
    _ = .{m};
}

pub var threaded_mainloop_start: *const @TypeOf(threaded_mainloop_start_stub) = undefined;
fn threaded_mainloop_start_stub(m: ?*ThreadedMainLoop) callconv(.c) c_int {
    _ = .{m};
    return -1;
}

pub var threaded_mainloop_get_api: *const @TypeOf(threaded_mainloop_get_api_stub) = undefined;
fn threaded_mainloop_get_api_stub(m: ?*ThreadedMainLoop) callconv(.c) ?*MainLoopApi {
    _ = .{m};
    return null;
}

pub var threaded_mainloop_lock: *const @TypeOf(threaded_mainloop_lock_stub) = undefined;
fn threaded_mainloop_lock_stub(m: ?*ThreadedMainLoop) callconv(.c) void {
    _ = .{m};
}

pub var threaded_mainloop_unlock: *const @TypeOf(threaded_mainloop_unlock_stub) = undefined;
fn threaded_mainloop_unlock_stub(m: ?*ThreadedMainLoop) callconv(.c) void {
    _ = .{m};
}

pub var threaded_mainloop_wait: *const @TypeOf(threaded_mainloop_wait_stub) = undefined;
fn threaded_mainloop_wait_stub(m: ?*ThreadedMainLoop) callconv(.c) void {
    _ = .{m};
}

pub var threaded_mainloop_signal: *const @TypeOf(threaded_mainloop_signal_stub) = undefined;
fn threaded_mainloop_signal_stub(m: ?*ThreadedMainLoop, wait_for_accept: c_int) callconv(.c) void {
    _ = .{ m, wait_for_accept };
}

pub var mainloop_new: *const @TypeOf(mainloop_new_stub) = undefined;
fn mainloop_new_stub() callconv(.c) ?*MainLoop {
    return null;
}

pub var mainloop_free: *const @TypeOf(mainloop_free_stub) = undefined;
fn mainloop_free_stub(m: ?*MainLoop) callconv(.c) void {
    _ = .{m};
}

pub var mainloop_get_api: *const @TypeOf(mainloop_get_api_stub) = undefined;
fn mainloop_get_api_stub(mainloop: ?*MainLoop) callconv(.c) ?*MainLoopApi {
    _ = .{mainloop};
    return null;
}

pub var mainloop_prepare: *const @TypeOf(mainloop_prepare_stub) = undefined;
fn mainloop_prepare_stub(m: ?*MainLoop, timeout: c_int) callconv(.c) c_int {
    _ = .{ m, timeout };
    return -1;
}

pub var mainloop_poll: *const @TypeOf(mainloop_poll_stub) = undefined;
fn mainloop_poll_stub(m: ?*MainLoop) callconv(.c) c_int {
    _ = .{m};
    return -1;
}

pub var mainloop_dispatch: *const @TypeOf(mainloop_dispatch_stub) = undefined;
fn mainloop_dispatch_stub(m: ?*MainLoop) callconv(.c) c_int {
    _ = .{m};
    return -1;
}

pub var mainloop_iterate: *const @TypeOf(mainloop_iterate_stub) = undefined;
fn mainloop_iterate_stub(m: ?*MainLoop, block: c_int, retval: ?*c_int) callconv(.c) c_int {
    _ = .{ m, block, retval };
    return -1;
}

pub var context_new: *const @TypeOf(context_new_stub) = undefined;
fn context_new_stub(mainloop: ?*MainLoopApi, name: [*:0]const u8) callconv(.c) ?*Context {
    _ = .{ mainloop, name };
    return null;
}

pub var context_unref: *const @TypeOf(context_unref_stub) = undefined;
fn context_unref_stub(ctx: ?*Context) callconv(.c) void {
    _ = .{ctx};
}

pub var context_connect: *const @TypeOf(context_connect_stub) = undefined;
fn context_connect_stub(c: ?*Context, server: ?[*:0]const u8, flags: ContextFlags, api: ?*const SpawnApi) callconv(.c) c_int {
    _ = .{ c, server, flags, api };
    return -1;
}

pub var context_disconnect: *const @TypeOf(context_disconnect_stub) = undefined;
fn context_disconnect_stub(c: ?*Context) callconv(.c) void {
    _ = .{c};
}

pub var context_get_state: *const @TypeOf(context_get_state_stub) = undefined;
fn context_get_state_stub(context: ?*Context) callconv(.c) ContextState {
    _ = .{context};
    return .failed;
}

pub var context_set_state_callback: *const @TypeOf(context_set_state_callback_stub) = undefined;
fn context_set_state_callback_stub(c: ?*Context, cb: ?ContextNotifyCb, userdata: ?*anyopaque) callconv(.c) void {
    _ = .{ c, cb, userdata };
}

pub var stream_new: *const @TypeOf(stream_new_stub) = undefined;
fn stream_new_stub(c: ?*Context, name: ?[*:0]const u8, ss: *const SampleSpec, map: ?*ChannelMap) callconv(.c) ?*Stream {
    _ = .{ c, name, ss, map };
    return null;
}

pub var stream_unref: *const @TypeOf(stream_unref_stub) = undefined;
fn stream_unref_stub(s: ?*Stream) callconv(.c) void {
    _ = .{s};
}

pub var stream_connect_playback: *const @TypeOf(stream_connect_playback_stub) = undefined;
fn stream_connect_playback_stub(s: ?*Stream, dev: ?[*:0]const u8, attr: ?*const BufferAttr, flags: StreamFlags, volume: ?*const CVolume, sync_stream: ?*Stream) callconv(.c) c_int {
    _ = .{ s, dev, attr, flags, volume, sync_stream };
    return -1;
}

pub var stream_get_state: *const @TypeOf(stream_get_state_stub) = undefined;
fn stream_get_state_stub(p: ?*const Stream) callconv(.c) StreamState {
    _ = .{p};
    return .failed;
}

pub var stream_writable_size: *const @TypeOf(stream_writable_size_stub) = undefined;
fn stream_writable_size_stub(p: ?*const Stream) callconv(.c) usize {
    _ = .{p};
    return std.math.maxInt(usize);
}

pub var stream_get_latency: *const @TypeOf(stream_get_latency_stub) = undefined;
fn stream_get_latency_stub(p: ?*const Stream, usec: *USec, neg: ?*c_int) callconv(.c) c_int {
    _ = .{ p, usec, neg };
    return ErrorCode.nodata.int();
}

pub var stream_get_underflow_index: *const @TypeOf(stream_get_underflow_index_stub) = undefined;
fn stream_get_underflow_index_stub(p: ?*const Stream) callconv(.c) i64 {
    _ = .{p};
    return -1;
}

pub var stream_begin_write: *const @TypeOf(stream_begin_write_stub) = undefined;
fn stream_begin_write_stub(p: ?*const Stream, data: *?*anyopaque, nbytes: *usize) callconv(.c) c_int {
    _ = .{ p, data, nbytes };
    data.* = null;
    return -1;
}

pub var stream_write: *const @TypeOf(stream_write_stub) = undefined;
fn stream_write_stub(p: ?*const Stream, data: *const anyopaque, n_bytes: usize, free_cb: ?FreeCb, offset: i64, seek: SeekMode) callconv(.c) usize {
    _ = .{ p, data, n_bytes, free_cb, offset, seek };
    return std.math.maxInt(usize);
}

pub var stream_cork: *const @TypeOf(stream_cork_stub) = undefined;
fn stream_cork_stub(p: ?*const Stream, b: c_int, cb: ?StreamSuccessCb, userdata: ?*anyopaque) callconv(.c) ?*Operation {
    _ = .{ p, b, cb, userdata };
    return null;
}

pub var stream_update_timing_info: *const @TypeOf(stream_update_timing_info_stub) = undefined;
fn stream_update_timing_info_stub(p: ?*const Stream, cb: ?StreamSuccessCb, userdata: ?*anyopaque) callconv(.c) ?*Operation {
    _ = .{ p, cb, userdata };
    return null;
}

pub var stream_set_write_callback: *const @TypeOf(stream_set_write_callback_stub) = undefined;
fn stream_set_write_callback_stub(p: ?*const Stream, cb: StreamRequestCb, userdata: ?*anyopaque) callconv(.c) ?*Operation {
    _ = .{ p, cb, userdata };
    return null;
}

pub var stream_set_underflow_callback: *const @TypeOf(stream_set_underflow_callback_stub) = undefined;
fn stream_set_underflow_callback_stub(p: ?*const Stream, cb: StreamNotifyCb, userdata: ?*anyopaque) callconv(.c) ?*Operation {
    _ = .{ p, cb, userdata };
    return null;
}

pub var stream_set_state_callback: *const @TypeOf(stream_set_state_callback_stub) = undefined;
fn stream_set_state_callback_stub(p: ?*const Stream, cb: ?StreamNotifyCb, userdata: ?*anyopaque) callconv(.c) void {
    _ = .{ p, cb, userdata };
}

pub var stream_get_buffer_attr: *const @TypeOf(stream_get_buffer_attr_stub) = undefined;
fn stream_get_buffer_attr_stub(p: ?*const Stream) callconv(.c) ?*BufferAttr {
    _ = .{p};
    return null;
}

pub var stream_set_buffer_attr: *const @TypeOf(stream_set_buffer_attr_stub) = undefined;
fn stream_set_buffer_attr_stub(p: ?*Stream, attr: *const BufferAttr, cb: ?StreamSuccessCb, userdata: ?*anyopaque) callconv(.c) ?*Operation {
    _ = .{ p, attr, cb, userdata };
    return null;
}

pub var stream_trigger: *const @TypeOf(stream_trigger_stub) = undefined;
fn stream_trigger_stub(p: ?*const Stream, cb: ?StreamSuccessCb, userdata: ?*anyopaque) callconv(.c) ?*Operation {
    _ = .{ p, cb, userdata };
    return null;
}

pub var stream_flush: *const @TypeOf(stream_flush_stub) = undefined;
fn stream_flush_stub(p: ?*const Stream, cb: ?StreamSuccessCb, userdata: ?*anyopaque) callconv(.c) ?*Operation {
    _ = .{ p, cb, userdata };
    return null;
}

pub var operation_unref: *const @TypeOf(operation_unref_stub) = undefined;
fn operation_unref_stub(o: *Operation) callconv(.c) void {
    _ = o;
}

pub var operation_get_state: *const @TypeOf(operation_get_state_stub) = undefined;
fn operation_get_state_stub(o: *const Operation) callconv(.c) OperationState {
    _ = o;
    return .cancelled;
}
//
pub var usec_to_bytes: *const @TypeOf(usec_to_bytes_stub) = undefined;
fn usec_to_bytes_stub(t: USec, spec: *const SampleSpec) callconv(.c) usize {
    _ = .{ t, spec };
    return 0;
}

pub fn load() void {
    const lib_name = "libpulse.so";
    var load_stubs = false;

    var lib_or_err = std.DynLib.open(lib_name);
    if (lib_or_err) |*lib| {
        inline for (@typeInfo(@This()).@"struct".decls) |decl| {
            const decl_type = @TypeOf(@field(@This(), decl.name));
            const decl_info = @typeInfo(decl_type);

            if (decl_info == .pointer and @typeInfo(decl_info.pointer.child) == .@"fn") {
                if (lib.lookup(decl_type, "pa_" ++ decl.name)) |sym| {
                    @field(@This(), decl.name) = sym;
                } else {
                    load_stubs = true;
                    if (options.internal_build) {
                        @panic("Unable to load function: '" ++ decl.name ++ "'");
                    }
                    break;
                }
            }
        }
    } else |_| {
        log.warn("Failed to open: '{s}'", .{lib_name});
        load_stubs = true;
    }

    if (load_stubs) {
        inline for (@typeInfo(@This()).@"struct".decls) |decl| {
            const decl_type = @TypeOf(@field(@This(), decl.name));
            const decl_info = @typeInfo(decl_type);

            if (decl_info == .pointer and @typeInfo(decl_info.pointer.child) == .@"fn") {
                @field(@This(), decl.name) = @field(@This(), decl.name ++ "_stub");
            }
        }
        log.debug("Loaded stubs '{s}'", .{lib_name});
    } else {
        log.debug("Loaded '{s}'", .{lib_name});
    }
}
