const std = @import("std");
const log = std.log.scoped(.alsa);

pub const Pcm = opaque {};
pub const PcmHwParams = opaque {};
pub const PcmUFrames = c_ulong;
pub const PcmSFrames = c_long;

pub const PcmStreamType = enum(c_int) {
    PLAYBACK = 0,
    CAPTURE,
    pub const LAST: @This() = .CAPTURE;
};

pub const PcmAccess = enum(c_int) {
    MMAP_INTERLEAVED = 0,
    MMAP_NONINTERLEAVED,
    MMAP_COMPLEX,
    RW_INTERLEAVED,
    RW_NONINTERLEAVED,
    pub const LAST: PcmAccess = .RW_NONINTERLEAVED;
};

pub const PcmFormat = enum(c_int) {
    UNKNOWN = -1,
    S8 = 0,
    U8,
    S16_LE,
    S16_BE,
    U16_LE,
    U16_BE,
    S24_LE,
    S24_BE,
    U24_LE,
    U24_BE,
    S32_LE,
    S32_BE,
    U32_LE,
    U32_BE,
    FLOAT_LE,
    FLOAT_BE,
    FLOAT64_LE,
    FLOAT64_BE,
    IEC958_SUBFRAME_LE,
    IEC958_SUBFRAME_BE,
    MU_LAW,
    A_LAW,
    IMA_ADPCM,
    MPEG,
    GSM,
    S20_LE,
    S20_BE,
    U20_LE,
    U20_BE,
    SPECIAL = 31,
    S24_3LE = 32,
    S24_3BE,
    U24_3LE,
    U24_3BE,
    S20_3LE,
    S20_3BE,
    U20_3LE,
    U20_3BE,
    S18_3LE,
    S18_3BE,
    U18_3LE,
    U18_3BE,
    G723_24,
    G723_24_1B,
    G723_40,
    G723_40_1B,
    DSD_U8,
    DSD_U16_LE,
    DSD_U32_LE,
    DSD_U16_BE,
    DSD_U32_BE,

    const le = @import("builtin").target.cpu.arch.endian() == .little;

    pub const S16: PcmFormat = if (le) .S16_LE else .S16_BE;
    pub const U16: PcmFormat = if (le) .U16_LE else .U16_BE;
    pub const S24: PcmFormat = if (le) .S24_LE else .S24_BE;
    pub const U24: PcmFormat = if (le) .U24_LE else .U24_BE;
    pub const S32: PcmFormat = if (le) .S32_LE else .S32_BE;
    pub const U32: PcmFormat = if (le) .U32_LE else .U32_BE;
    pub const FLOAT: PcmFormat = if (le) .FLOAT_LE else .FLOAT_BE;
    pub const FLOAT64: PcmFormat = if (le) .FLOAT64_LE else .FLOAT64_BE;
    pub const IEC958_SUBFRAME: PcmFormat = if (le) .IEC958_SUBFRAME_LE else .IEC958_SUBFRAME_BE;
    pub const S20: PcmFormat = if (le) .S20_LE else .S20_BE;
    pub const U20: PcmFormat = if (le) .U20_LE else .U20_BE;

    pub const LAST: PcmFormat = .DSD_U32_BE;
};

pub const PcmState = enum(c_int) {
    OPEN = 0,
    SETUP,
    PREPARED,
    RUNNING,
    XRUN,
    DRAINING,
    PAUSED,
    SUSPENDED,
    DISCONNECTED,
    PRIVATE1 = 1024,
    pub const LAST: PcmState = .DISCONNECTED;
};

pub const PcmChannelArea = extern struct {
    /// Base address of channel samples
    addr: [*]u8,
    /// Offset to first sample in bits
    offset: c_uint,
    /// Samples distance in bits
    step: c_uint,
};

fn pcm_open_stub(pcm: **Pcm, name: [*:0]const u8, stream: PcmStreamType, mode: c_int) callconv(.c) c_int {
    _ = .{ pcm, name, stream, mode };
    return -1;
}
const FN_pcm_open = @TypeOf(pcm_open_stub);
pub var pcm_open: *const FN_pcm_open = undefined;

fn pcm_hw_params_malloc_stub(ptr: *?*PcmHwParams) callconv(.c) c_int {
    ptr.* = null;
    return -1;
}
const FN_pcm_hw_params_malloc = @TypeOf(pcm_hw_params_malloc_stub);
pub var pcm_hw_params_malloc: *const FN_pcm_hw_params_malloc = undefined;

fn pcm_hw_params_free_stub(obj: *PcmHwParams) callconv(.c) void {
    _ = .{obj};
}
const FN_pcm_hw_params_free = @TypeOf(pcm_hw_params_free_stub);
pub var pcm_hw_params_free: *const FN_pcm_hw_params_free = undefined;

fn pcm_hw_params_any_stub(pcm: *Pcm, params: *PcmHwParams) callconv(.c) c_int {
    _ = .{ pcm, params };
    return -1;
}
const FN_pcm_hw_params_any = @TypeOf(pcm_hw_params_any_stub);
pub var pcm_hw_params_any: *const FN_pcm_hw_params_any = undefined;

fn pcm_hw_params_set_buffer_size_near_stub(pcm: *Pcm, params: *PcmHwParams, val: *PcmUFrames) callconv(.c) c_int {
    _ = .{ pcm, params, val };
    return -1;
}
const FN_pcm_hw_params_set_buffer_size_near = @TypeOf(pcm_hw_params_set_buffer_size_near_stub);
pub var pcm_hw_params_set_buffer_size_near: *const FN_pcm_hw_params_set_buffer_size_near = undefined;

fn pcm_hw_params_set_period_size_near_stub(pcm: *Pcm, params: *PcmHwParams, val: *PcmUFrames, dir: ?*c_int) callconv(.c) c_int {
    _ = .{ pcm, params, val, dir };
    return -1;
}
const FN_pcm_hw_params_set_period_size_near = @TypeOf(pcm_hw_params_set_period_size_near_stub);
pub var pcm_hw_params_set_period_size_near: *const FN_pcm_hw_params_set_period_size_near = undefined;

fn pcm_hw_params_set_access_stub(pcm: *Pcm, params: *PcmHwParams, access: PcmAccess) callconv(.c) c_int {
    _ = .{ pcm, params, access };
    return -1;
}
const FN_pcm_hw_params_set_access = @TypeOf(pcm_hw_params_set_access_stub);
pub var pcm_hw_params_set_access: *const FN_pcm_hw_params_set_access = undefined;

fn pcm_hw_params_set_format_stub(pcm: *Pcm, params: *PcmHwParams, format: PcmFormat) callconv(.c) c_int {
    _ = .{ pcm, params, format };
    return -1;
}
const FN_pcm_hw_params_set_format = @TypeOf(pcm_hw_params_set_format_stub);
pub var pcm_hw_params_set_format: *const FN_pcm_hw_params_set_format = undefined;

fn pcm_hw_params_set_channels_stub(pcm: *Pcm, params: *PcmHwParams, val: c_uint) callconv(.c) c_int {
    _ = .{ pcm, params, val };
    return -1;
}
const FN_pcm_hw_params_set_channels = @TypeOf(pcm_hw_params_set_channels_stub);
pub var pcm_hw_params_set_channels: *const FN_pcm_hw_params_set_channels = undefined;

fn pcm_hw_params_set_rate_stub(pcm: *Pcm, params: *PcmHwParams, val: c_uint, dir: c_int) callconv(.c) c_int {
    _ = .{ pcm, params, val, dir };
    return -1;
}
const FN_pcm_hw_params_set_rate = @TypeOf(pcm_hw_params_set_rate_stub);
pub var pcm_hw_params_set_rate: *const FN_pcm_hw_params_set_rate = undefined;

fn pcm_hw_params_stub(pcm: *Pcm, params: *PcmHwParams) callconv(.c) c_int {
    _ = .{ pcm, params };
    return -1;
}
const FN_pcm_hw_params = @TypeOf(pcm_hw_params_stub);
pub var pcm_hw_params: *const FN_pcm_hw_params = undefined;

fn pcm_prepare_stub(pcm: *Pcm) callconv(.c) c_int {
    _ = .{pcm};
    return -1;
}
const FN_pcm_prepare = @TypeOf(pcm_prepare_stub);
pub var pcm_prepare: *const FN_pcm_prepare = undefined;

fn pcm_writei_stub(pcm: *Pcm, buffer: *anyopaque, size: PcmUFrames) callconv(.c) c_int {
    _ = .{ pcm, buffer, size };
    return -1;
}
const FN_pcm_writei = @TypeOf(pcm_writei_stub);
pub var pcm_writei: *const FN_pcm_writei = undefined;

fn pcm_poll_descriptors_count_stub(pcm: *Pcm) callconv(.c) c_int {
    _ = .{pcm};
    return -1;
}
const FN_pcm_poll_descriptors_count = @TypeOf(pcm_poll_descriptors_count_stub);
pub var pcm_poll_descriptors_count: *const FN_pcm_poll_descriptors_count = undefined;

fn pcm_poll_descriptors_stub(pcm: *Pcm, pfds: [*]std.posix.pollfd, space: c_uint) callconv(.c) c_int {
    _ = .{ pcm, pfds, space };
    return -1;
}
const FN_pcm_poll_descriptors = @TypeOf(pcm_poll_descriptors_stub);
pub var pcm_poll_descriptors: *const FN_pcm_poll_descriptors = undefined;

fn pcm_poll_descriptors_revents_stub(pcm: *Pcm, pfds: [*]std.posix.pollfd, nfds: c_uint, revents: *c_ushort) callconv(.c) c_int {
    _ = .{ pcm, pfds, nfds, revents };
    return -1;
}
const FN_pcm_poll_descriptors_revents = @TypeOf(pcm_poll_descriptors_revents_stub);
pub var pcm_poll_descriptors_revents: *const FN_pcm_poll_descriptors_revents = undefined;

fn pcm_start_stub(pcm: *Pcm) callconv(.c) c_int {
    _ = .{pcm};
    return -1;
}
const FN_pcm_start = @TypeOf(pcm_start_stub);
pub var pcm_start: *const FN_pcm_start = undefined;

fn pcm_state_stub(pcm: *Pcm) callconv(.c) PcmState {
    _ = .{pcm};
    return .DISCONNECTED;
}
const FN_pcm_state = @TypeOf(pcm_state_stub);
pub var pcm_state: *const FN_pcm_state = undefined;

fn pcm_mmap_begin_stub(pcm: *Pcm, areas: **PcmChannelArea, offset: *PcmUFrames, frames: *PcmUFrames) callconv(.c) c_int {
    _ = .{ pcm, areas, offset, frames };
    return -1;
}
const FN_pcm_mmap_begin = @TypeOf(pcm_mmap_begin_stub);
pub var pcm_mmap_begin: *const FN_pcm_mmap_begin = undefined;

fn pcm_mmap_commit_stub(pcm: *Pcm, offset: PcmUFrames, frames: PcmUFrames) callconv(.c) PcmSFrames {
    _ = .{ pcm, offset, frames };
    return -1;
}
const FN_pcm_mmap_commit = @TypeOf(pcm_mmap_commit_stub);
pub var pcm_mmap_commit: *const FN_pcm_mmap_commit = undefined;

fn pcm_avail_update_stub(pcm: *Pcm) callconv(.c) PcmSFrames {
    _ = pcm;
    return -1;
}
const FN_pcm_avail_update = @TypeOf(pcm_avail_update_stub);
pub var pcm_avail_update: *const FN_pcm_avail_update = undefined;

pub fn load() void {
    var lib = std.DynLib.open("libasound.so") catch {
        log.warn("Alsa not found, loading stubs", .{});
        loadStubs();
        return;
    };

    log.debug("Loaded libasound.so", .{});

    const struct_info = @typeInfo(@This()).@"struct";
    inline for (struct_info.decls) |decl| {
        const decl_type = @TypeOf(@field(@This(), decl.name));
        const decl_info = @typeInfo(decl_type);
        if (decl_info == .pointer and @typeInfo(decl_info.pointer.child) == .@"fn") {
            @field(@This(), decl.name) = lib.lookup(decl_type, "snd_" ++ decl.name) orelse {
                log.warn("Error loading alsa, loading stubs", .{});
                if (@import("builtin").mode == .Debug) @panic("Error loading alsa!");
                loadStubs();
                break;
            };
        }
    }
}

fn loadStubs() void {
    const struct_info = @typeInfo(@This()).@"struct";
    inline for (struct_info.decls) |decl| {
        const decl_type = @TypeOf(@field(@This(), decl.name));
        const decl_info = @typeInfo(decl_type);

        if (decl_info == .pointer and @typeInfo(decl_info.pointer.child) == .@"fn") {
            @field(@This(), decl.name) = @field(@This(), decl.name ++ "_stub");
        }
    }
}
