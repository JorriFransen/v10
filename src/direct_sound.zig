const std = @import("std");
const log = std.log.scoped(.dsound);
const win32 = @import("win32.zig");

const LPUNKNOWN = ?*anyopaque;

pub const OK: u32 = 0x00000000;
pub const ERR_OUTOFMEMORY: u32 = 0x00000007;
pub const ERR_NOINTERFACE: u32 = 0x000001AE;
pub const NO_VIRTUALIZATION: u32 = 0x0878000A;
pub const INCOMPLETE: u32 = 0x08780014;
pub const ERR_UNSUPPORTED: u32 = 0x80004001;
pub const ERR_GENERIC: u32 = 0x80004005;
pub const ERR_ACCESSDENIED: u32 = 0x80070005;
pub const ERR_INVALIDPARAM: u32 = 0x80070057;
pub const ERR_ALLOCATED: u32 = 0x8878000A;
pub const ERR_CONTROLUNAVAIL: u32 = 0x8878001E;
pub const ERR_INVALIDCALL: u32 = 0x88780032;
pub const ERR_PRIOLEVELNEEDED: u32 = 0x88780046;
pub const ERR_BADFORMAT: u32 = 0x88780064;
pub const ERR_NODRIVER: u32 = 0x88780078;
pub const ERR_ALREADYINITIALIZED: u32 = 0x88780082;
pub const ERR_BUFFERLOST: u32 = 0x88780096;
pub const ERR_OTHERAPPHASPRIO: u32 = 0x887800A0;
pub const ERR_UNINITIALIZED: u32 = 0x887800AA;
pub const ERR_BUFFERTOOSMALL: u32 = 0x887810B4;
pub const ERR_DS8_REQUIRED: u32 = 0x887810BE;
pub const ERR_SENDLOOP: u32 = 0x887810C8;
pub const ERR_BADSENDBUFFERGUID: u32 = 0x887810D2;
pub const ERR_FXUNAVAILABLE: u32 = 0x887810DC;
pub const ERR_OBJECTNOTFOUND: u32 = 0x88781161;

pub const SCL_NORMAL = 0x00000001;
pub const SCL_PRIORITY = 0x00000002;
pub const SCL_EXCLUSIVE = 0x00000003;
pub const SCL_WRITEPRIMARY = 0x00000004;

pub const BCAPS_PRIMARYBUFFER = 0x00000001;
pub const BCAPS_STATIC = 0x00000002;
pub const BCAPS_LOCHARDWARE = 0x00000004;
pub const BCAPS_LOCSOFTWARE = 0x00000008;
pub const BCAPS_CTRL3D = 0x00000010;
pub const BCAPS_CTRLFREQUENCY = 0x00000020;
pub const BCAPS_CTRLPAN = 0x00000040;
pub const BCAPS_CTRLVOLUME = 0x00000080;
pub const BCAPS_CTRLPOSITIONNOTIFY = 0x00000100;
pub const BCAPS_CTRLDEFAULT = 0x000000E0;
pub const BCAPS_CTRLALL = 0x000001F0;
pub const BCAPS_STICKYFOCUS = 0x00004000;
pub const BCAPS_GLOBALFOCUS = 0x00008000;
pub const BCAPS_GETCURRENTPOSITION2 = 0x00010000;
pub const BCAPS_MUTE3DATMAXDISTANCE = 0x00020000;

pub const IDirectSound = extern struct {
    vtable: *const VTable,

    pub inline fn QueryInterface(this: *IDirectSound, riid: *const win32.GUID, object: **anyopaque) win32.HRESULT {
        return this.vtable.QueryInterface(this, riid, object);
    }
    pub inline fn AddRef(this: *IDirectSound) u32 {
        return this.vtable.AddRef(this);
    }
    pub inline fn Release(this: *IDirectSound) u32 {
        return this.vtable.Release(this);
    }

    // IDirectSound methods
    pub inline fn CreateSoundBuffer(this: *IDirectSound, buffer_desc: *const BufferDesc, buffer: **IDirectSoundBuffer, unk_outer: ?*anyopaque) win32.HRESULT {
        return this.vtable.CreateSoundBuffer(this, buffer_desc, buffer, unk_outer);
    }
    pub inline fn GetCaps(this: *IDirectSound, caps: *Caps) win32.HRESULT {
        return this.vtable.GetCaps(this, caps);
    }
    pub inline fn DuplicateSoundBuffer(this: *IDirectSound, original: *const IDirectSoundBuffer, duplicate: **const IDirectSoundBuffer) win32.HRESULT {
        return this.vtable.DuplicateSoundBuffer(this, original, duplicate);
    }
    pub inline fn SetCooperativeLevel(this: *IDirectSound, hwnd: win32.HWND, level: win32.DWORD) win32.HRESULT {
        return this.vtable.SetCooperativeLevel(this, hwnd, level);
    }
    pub inline fn Compact(this: *IDirectSound) win32.HRESULT {
        return this.vtable.Compact(this);
    }
    pub inline fn GetSpeakerConfig(this: *IDirectSound, speaker_config: *win32.DWORD) win32.HRESULT {
        return this.vtable.GetSpeakerConfig(this, speaker_config);
    }
    pub inline fn SetSpeakerConfig(this: *IDirectSound, speaker_config: win32.DWORD) win32.HRESULT {
        return this.vtable.SetSpeakerConfig(this, speaker_config);
    }
    pub inline fn Initialize(this: *IDirectSound, guid_device: *const win32.GUID) win32.HRESULT {
        return this.vtable.Initialize(this, guid_device);
    }

    const VTable = extern struct {

        // IUnknown methods
        QueryInterface: *const fn (this: *IDirectSound, riid: *const win32.GUID, object: **anyopaque) callconv(.c) win32.HRESULT,
        AddRef: *const fn (this: *IDirectSound) callconv(.c) u32,
        Release: *const fn (this: *IDirectSound) callconv(.c) u32,

        // IDirectSound methods
        CreateSoundBuffer: *const fn (this: *IDirectSound, buffer_desc: *const BufferDesc, buffer: **IDirectSoundBuffer, unk_outer: ?*anyopaque) callconv(.c) win32.HRESULT,
        GetCaps: *const fn (this: *IDirectSound, caps: *Caps) callconv(.c) win32.HRESULT,
        DuplicateSoundBuffer: *const fn (this: *IDirectSound, original: *const IDirectSoundBuffer, duplicate: **const IDirectSoundBuffer) callconv(.c) win32.HRESULT,
        SetCooperativeLevel: *const fn (this: *IDirectSound, hwnd: win32.HWND, level: win32.DWORD) callconv(.c) win32.HRESULT,
        Compact: *const fn (this: *IDirectSound) callconv(.c) win32.HRESULT,
        GetSpeakerConfig: *const fn (this: *IDirectSound, speaker_config: *win32.DWORD) callconv(.c) win32.HRESULT,
        SetSpeakerConfig: *const fn (this: *IDirectSound, speaker_config: win32.DWORD) callconv(.c) win32.HRESULT,
        Initialize: *const fn (this: *IDirectSound, guid_device: *const win32.GUID) callconv(.c) win32.HRESULT,
    };
};

pub const IDirectSoundBuffer = extern struct {
    vtable: *const VTable,

    pub inline fn QueryInterface(this: *IDirectSound, riid: *const win32.GUID, object: **anyopaque) win32.HRESULT {
        return this.vtable.QueryInterface(this, riid, object);
    }
    pub inline fn AddRef(this: *IDirectSound) u32 {
        return this.vtable.AddRef(this);
    }
    pub inline fn Release(this: *IDirectSound) u32 {
        return this.vtable.Release(this);
    }

    pub inline fn GetCaps(this: *IDirectSoundBuffer, caps: *BCaps) win32.HRESULT {
        return this.vtable.GetCaps(this, caps);
    }
    pub inline fn GetCurrentPosition(this: *IDirectSoundBuffer, current_play_cursor: *win32.DWORD, current_write_cursor: *win32.DWORD) win32.HRESULT {
        return this.vtable.GetCurrentPosition(this, current_play_cursor, current_write_cursor);
    }
    pub inline fn GetFormat(this: *IDirectSoundBuffer, format: *WAVEFORMATEX, size_allocated: win32.DWORD, size_written: *win32.DWORD) win32.HRESULT {
        return this.vtable.GetFormat(this, format, size_allocated, size_written);
    }
    pub inline fn GetVolume(this: *IDirectSoundBuffer, volume: *win32.LONG) win32.HRESULT {
        return this.vtable.GetVolume(this, volume);
    }
    pub inline fn GetPan(this: *IDirectSoundBuffer, pan: *win32.LONG) win32.HRESULT {
        return this.vtable.GetPan(this, pan);
    }
    pub inline fn GetFrequency(this: *IDirectSoundBuffer, frequency: *win32.DWORD) win32.HRESULT {
        return this.vtable.GetFrequency(this, frequency);
    }
    pub inline fn GetStatus(this: *IDirectSoundBuffer, status: *win32.DWORD) win32.HRESULT {
        return this.vtable.GetStatus(this, status);
    }
    pub inline fn Initialize(this: *IDirectSoundBuffer, direct_sound: *IDirectSound, buffer_desc: *const BufferDesc) win32.HRESULT {
        return this.vtable.Initialize(this, direct_sound, buffer_desc);
    }
    pub inline fn Lock(this: *IDirectSoundBuffer, write_cursor: win32.DWORD, write_bytes: win32.DWORD, audio_ptr_1: **anyopaque, audio_bytes_1: *win32.DWORD, audio_ptr_2: **anyopaque, audio_bytes_2: *win32.DWORD, flags: win32.DWORD) win32.HRESULT {
        return this.vtable.Lock(this, write_cursor, write_bytes, audio_ptr_1, audio_bytes_1, audio_ptr_2, audio_bytes_2, flags);
    }
    pub inline fn Play(this: *IDirectSoundBuffer, reserved1: win32.DWORD, reserved2: win32.DWORD, flags: win32.DWORD) win32.HRESULT {
        return this.vtable.Play(this, reserved1, reserved2, flags);
    }
    pub inline fn SetCurrentPosition(this: *IDirectSoundBuffer, new_position: win32.DWORD) win32.HRESULT {
        return this.vtable.SetCurrentPosition(this, new_position);
    }
    pub inline fn SetFormat(this: *IDirectSoundBuffer, format: *const WAVEFORMATEX) win32.HRESULT {
        return this.vtable.SetFormat(this, format);
    }
    pub inline fn SetVolume(this: *IDirectSoundBuffer, volume: win32.LONG) win32.HRESULT {
        return this.vtable.SetVolume(this, volume);
    }
    pub inline fn SetPan(this: *IDirectSoundBuffer, pan: win32.LONG) win32.HRESULT {
        return this.vtable.SetPan(this, pan);
    }
    pub inline fn SetFrequency(this: *IDirectSoundBuffer, frequency: win32.DWORD) win32.HRESULT {
        return this.vtable.SetFrequency(this, frequency);
    }
    pub inline fn Stop(this: *IDirectSoundBuffer) win32.HRESULT {
        return this.vtable.Stop(this);
    }
    pub inline fn Unlock(this: *IDirectSoundBuffer, audio_ptr_1: *anyopaque, audio_bytes_1: win32.DWORD, audio_ptr_2: *anyopaque, audio_bytes_2: win32.DWORD) win32.HRESULT {
        return this.vtable.Unlock(this, audio_ptr_1, audio_bytes_1, audio_ptr_2, audio_bytes_2);
    }
    pub inline fn Restore(this: *IDirectSoundBuffer) win32.HRESULT {
        return this.vtable.Restore(this);
    }

    const VTable = extern struct {
        // IUnknown methods
        QueryInterface: *const fn (this: *IDirectSound, riid: *const win32.GUID, object: **anyopaque) callconv(.c) win32.HRESULT,
        AddRef: *const fn (this: *IDirectSound) callconv(.c) u32,
        Release: *const fn (this: *IDirectSound) callconv(.c) u32,

        // IDirectSoundBuffer methods
        GetCaps: *const fn (this: *IDirectSoundBuffer, caps: *BCaps) callconv(.c) win32.HRESULT,
        GetCurrentPosition: *const fn (this: *IDirectSoundBuffer, current_play_cursor: *win32.DWORD, current_write_cursor: *win32.DWORD) callconv(.c) win32.HRESULT,
        GetFormat: *const fn (this: *IDirectSoundBuffer, format: *WAVEFORMATEX, size_allocated: win32.DWORD, size_written: *win32.DWORD) callconv(.c) win32.HRESULT,
        GetVolume: *const fn (this: *IDirectSoundBuffer, volume: *win32.LONG) callconv(.c) win32.HRESULT,
        GetPan: *const fn (this: *IDirectSoundBuffer, pan: *win32.LONG) callconv(.c) win32.HRESULT,
        GetFrequency: *const fn (this: *IDirectSoundBuffer, frequency: *win32.DWORD) callconv(.c) win32.HRESULT,
        GetStatus: *const fn (this: *IDirectSoundBuffer, status: *win32.DWORD) callconv(.c) win32.HRESULT,
        Initialize: *const fn (this: *IDirectSoundBuffer, direct_sound: *IDirectSound, buffer_desc: *const BufferDesc) callconv(.c) win32.HRESULT,
        Lock: *const fn (this: *IDirectSoundBuffer, write_cursor: win32.DWORD, write_bytes: win32.DWORD, audio_ptr_1: **anyopaque, audio_bytes_1: *win32.DWORD, audio_ptr_2: **anyopaque, audio_bytes_2: *win32.DWORD, flags: win32.DWORD) callconv(.c) win32.HRESULT,
        Play: *const fn (this: *IDirectSoundBuffer, reserved1: win32.DWORD, reserved2: win32.DWORD, flags: win32.DWORD) callconv(.c) win32.HRESULT,
        SetCurrentPosition: *const fn (this: *IDirectSoundBuffer, new_position: win32.DWORD) callconv(.c) win32.HRESULT,
        SetFormat: *const fn (this: *IDirectSoundBuffer, format: *const WAVEFORMATEX) callconv(.c) win32.HRESULT,
        SetVolume: *const fn (this: *IDirectSoundBuffer, volume: win32.LONG) callconv(.c) win32.HRESULT,
        SetPan: *const fn (this: *IDirectSoundBuffer, pan: win32.LONG) callconv(.c) win32.HRESULT,
        SetFrequency: *const fn (this: *IDirectSoundBuffer, frequency: win32.DWORD) callconv(.c) win32.HRESULT,
        Stop: *const fn (this: *IDirectSoundBuffer) callconv(.c) win32.HRESULT,
        Unlock: *const fn (this: *IDirectSoundBuffer, audio_ptr_1: *anyopaque, audio_bytes_1: win32.DWORD, audio_ptr_2: *anyopaque, audio_bytes_2: win32.DWORD) callconv(.c) win32.HRESULT,
        Restore: *const fn (this: *IDirectSoundBuffer) callconv(.c) win32.HRESULT,
    };
};

pub const Caps = opaque {};
pub const BCaps = extern struct {
    dwSize: win32.DWORD = 0,
    dwFlags: win32.DWORD = 0,
    dwBufferBytes: win32.DWORD = 0,
    dwUnlockTransferRate: win32.DWORD = 0,
    dwPlayCpuOverhead: win32.DWORD = 0,
};

pub const BufferDesc = extern struct {
    size: win32.DWORD = @sizeOf(@This()),
    flags: win32.DWORD = 0,
    buffer_bytes: win32.DWORD = 0,
    reserved: win32.DWORD = 0,
    wave_format: ?*WAVEFORMATEX = null,
    guid_3d_algorighm: win32.GUID = .{},
};

pub const WAVEFORMATEX = extern struct {
    wFormatTag: win32.WORD = 0,
    nChannels: win32.WORD = 0,
    nSamplesPerSec: win32.DWORD = 0,
    nAvgBytesPerSec: win32.DWORD = 0,
    nBlockAlign: win32.WORD = 0,
    wBitsPerSample: win32.WORD = 0,
    cbSize: win32.WORD = 0,
};

// typedef struct WAVEFORMATEXTENSIBLE {
//     WAVEFORMATEX Format;
//     WORD wValidBitsPerSample;
//     WORD wSamplesPerBlock;
//     WORD wReserved;
//     DWORD dwChannelMask;
//     DWORD SubFormat;
// } WAVEFORMATEXTENSIBLE;

fn DirectSoundCreateStub(guid: ?*win32.GUID, ds: **IDirectSound, unk_outer: LPUNKNOWN) callconv(.winapi) win32.HRESULT {
    _ = guid;
    _ = ds;
    _ = unk_outer;
    return @bitCast(ERR_NODRIVER);
}
const FN_DirectSoundCreate = @TypeOf(DirectSoundCreateStub);
pub var DirectSoundCreate: *const FN_DirectSoundCreate = undefined;

pub fn load() void {
    var lib = std.DynLib.open("dsound.dll") catch {
        log.warn("DSound not found, loading stubs", .{});
        loadStubs();
        return;
    };

    log.debug("Loaded dsound.dll", .{});

    const struct_info = @typeInfo(@This()).@"struct";
    inline for (struct_info.decls) |decl| {
        const decl_type = @TypeOf(@field(@This(), decl.name));
        const decl_info = @typeInfo(decl_type);
        if (decl_info == .pointer and @typeInfo(decl_info.pointer.child) == .@"fn") {
            @field(@This(), decl.name) = lib.lookup(decl_type, decl.name) orelse {
                log.warn("Error loading dsound, loading stubs", .{});
                if (@import("builtin").mode == .Debug) @panic("Error loading dsound!");
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
            @field(@This(), decl.name) = @field(@This(), decl.name ++ "Stub");
        }
    }
}
