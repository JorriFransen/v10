const std = @import("std");
const log = std.log.scoped(.linux);

const arch = @import("arch/arch.zig").arch;
const assert = @import("../../core.zig").assert;
const math = @import("../../math.zig");
const meta = @import("../../meta.zig");

pub const abi = @import("abi/abi.zig").abi;

pub const syscall0 = arch.syscall0;
pub const syscall1 = arch.syscall1;
pub const syscall2 = arch.syscall2;
pub const syscall3 = arch.syscall3;
pub const syscall4 = arch.syscall4;
pub const syscall5 = arch.syscall5;
pub const syscall6 = arch.syscall6;

pub const page_size = std.heap.page_size_min;

pub const Error = error{
    AddressNotAvailable,
    AlreadyConnecting,
    BufferTooSmall,
    ConnectingInProgress,
    ConnectionClosed,
    ConnectionRefused,
    ConnectionReset,
    DiskQuotaExceeded,
    EndOfFile,
    FileBusy,
    FileDoesNotExist,
    FileExists,
    HostUnreachable,
    IO,
    Interrupt,
    InvalidAddressFamily,
    InvalidArg,
    InvalidDevice,
    InvalidFD,
    InvalidFlags,
    InvalidPath,
    InvalidPointer,
    InvalidProtocol,
    IsDirectory,
    Lock,
    MessageTooBig,
    NameTooLong,
    NetworkUnreachable,
    NoData,
    NoMemory,
    NoSpaceLeft,
    NotConnected,
    NotSocket,
    NotSupported,
    Overflow,
    PackageNotCompiled,
    PermissionDenied,
    ReadOnly,
    Timeout,
    TooManyFiles,
    TooManyProcessFiles,
    TooManySymbolicLinks,
    UnexpectedDirFD,
    UnlinkDirectoryAttempt,
    ValueTooBig,

    UnexpectedErrno,
};

const sep = std.fs.path.sep_posix;
const sep_str = std.fs.path.sep_str_posix;
pub fn dirnameN(path: []const u8, n: usize) ?[]const u8 {
    if (n == 0) return path;

    const result = std.mem.trimEnd(u8, path, sep_str);

    var result_len: usize = result.len;
    var i: usize = result.len;
    var remaining_cuts = n;

    while (i > 0 and remaining_cuts > 0) {
        while (i > 0 and result[i - 1] != sep) {
            i -= 1;
        }

        if (i == 0) break;

        while (i > 0 and result[i - 1] == sep) {
            i -= 1;
        }

        result_len = if (i == 0) 1 else i;
        remaining_cuts -= 1;
    }

    return if (remaining_cuts == 0) result[0..result_len] else null;
}

// =============================================================================
// errno.h (+ errno-base.h)
// =============================================================================

pub const Errno = enum(u16) {
    /// No error occurred.
    /// Same code used for `NSROK`.
    SUCCESS = 0,
    /// Operation not permitted
    PERM = 1,
    /// No such file or directory
    NOENT = 2,
    /// No such process
    SRCH = 3,
    /// Interrupted system call
    INTR = 4,
    /// I/O error
    IO = 5,
    /// No such device or address
    NXIO = 6,
    /// Arg list too long
    @"2BIG" = 7,
    /// Exec format error
    NOEXEC = 8,
    /// Bad file number
    BADF = 9,
    /// No child processes
    CHILD = 10,
    /// Try again
    /// Also means: WOULDBLOCK: operation would block
    AGAIN = 11,
    /// Out of memory
    NOMEM = 12,
    /// Permission denied
    ACCES = 13,
    /// Bad address
    FAULT = 14,
    /// Block device required
    NOTBLK = 15,
    /// Device or resource busy
    BUSY = 16,
    /// File exists
    EXIST = 17,
    /// Cross-device link
    XDEV = 18,
    /// No such device
    NODEV = 19,
    /// Not a directory
    NOTDIR = 20,
    /// Is a directory
    ISDIR = 21,
    /// Invalid argument
    INVAL = 22,
    /// File table overflow
    NFILE = 23,
    /// Too many open files
    MFILE = 24,
    /// Not a typewriter
    NOTTY = 25,
    /// Text file busy
    TXTBSY = 26,
    /// File too large
    FBIG = 27,
    /// No space left on device
    NOSPC = 28,
    /// Illegal seek
    SPIPE = 29,
    /// Read-only file system
    ROFS = 30,
    /// Too many links
    MLINK = 31,
    /// Broken pipe
    PIPE = 32,
    /// Math argument out of domain of func
    DOM = 33,
    /// Math result not representable
    RANGE = 34,
    /// Resource deadlock would occur
    DEADLK = 35,
    /// File name too long
    NAMETOOLONG = 36,
    /// No record locks available
    NOLCK = 37,
    /// Function not implemented
    NOSYS = 38,
    /// Directory not empty
    NOTEMPTY = 39,
    /// Too many symbolic links encountered
    LOOP = 40,
    /// No message of desired type
    NOMSG = 42,
    /// Identifier removed
    IDRM = 43,
    /// Channel number out of range
    CHRNG = 44,
    /// Level 2 not synchronized
    L2NSYNC = 45,
    /// Level 3 halted
    L3HLT = 46,
    /// Level 3 reset
    L3RST = 47,
    /// Link number out of range
    LNRNG = 48,
    /// Protocol driver not attached
    UNATCH = 49,
    /// No CSI structure available
    NOCSI = 50,
    /// Level 2 halted
    L2HLT = 51,
    /// Invalid exchange
    BADE = 52,
    /// Invalid request descriptor
    BADR = 53,
    /// Exchange full
    XFULL = 54,
    /// No anode
    NOANO = 55,
    /// Invalid request code
    BADRQC = 56,
    /// Invalid slot
    BADSLT = 57,
    /// Bad font file format
    BFONT = 59,
    /// Device not a stream
    NOSTR = 60,
    /// No data available
    NODATA = 61,
    /// Timer expired
    TIME = 62,
    /// Out of streams resources
    NOSR = 63,
    /// Machine is not on the network
    NONET = 64,
    /// Package not installed
    NOPKG = 65,
    /// Object is remote
    REMOTE = 66,
    /// Link has been severed
    NOLINK = 67,
    /// Advertise error
    ADV = 68,
    /// Srmount error
    SRMNT = 69,
    /// Communication error on send
    COMM = 70,
    /// Protocol error
    PROTO = 71,
    /// Multihop attempted
    MULTIHOP = 72,
    /// RFS specific error
    DOTDOT = 73,
    /// Not a data message
    BADMSG = 74,
    /// Value too large for defined data type
    OVERFLOW = 75,
    /// Name not unique on network
    NOTUNIQ = 76,
    /// File descriptor in bad state
    BADFD = 77,
    /// Remote address changed
    REMCHG = 78,
    /// Can not access a needed shared library
    LIBACC = 79,
    /// Accessing a corrupted shared library
    LIBBAD = 80,
    /// .lib section in a.out corrupted
    LIBSCN = 81,
    /// Attempting to link in too many shared libraries
    LIBMAX = 82,
    /// Cannot exec a shared library directly
    LIBEXEC = 83,
    /// Illegal byte sequence
    ILSEQ = 84,
    /// Interrupted system call should be restarted
    RESTART = 85,
    /// Streams pipe error
    STRPIPE = 86,
    /// Too many users
    USERS = 87,
    /// Socket operation on non-socket
    NOTSOCK = 88,
    /// Destination address required
    DESTADDRREQ = 89,
    /// Message too long
    MSGSIZE = 90,
    /// Protocol wrong type for socket
    PROTOTYPE = 91,
    /// Protocol not available
    NOPROTOOPT = 92,
    /// Protocol not supported
    PROTONOSUPPORT = 93,
    /// Socket type not supported
    SOCKTNOSUPPORT = 94,
    /// Operation not supported on transport endpoint
    /// This code also means `NOTSUP`.
    OPNOTSUPP = 95,
    /// Protocol family not supported
    PFNOSUPPORT = 96,
    /// Address family not supported by protocol
    AFNOSUPPORT = 97,
    /// Address already in use
    ADDRINUSE = 98,
    /// Cannot assign requested address
    ADDRNOTAVAIL = 99,
    /// Network is down
    NETDOWN = 100,
    /// Network is unreachable
    NETUNREACH = 101,
    /// Network dropped connection because of reset
    NETRESET = 102,
    /// Software caused connection abort
    CONNABORTED = 103,
    /// Connection reset by peer
    CONNRESET = 104,
    /// No buffer space available
    NOBUFS = 105,
    /// Transport endpoint is already connected
    ISCONN = 106,
    /// Transport endpoint is not connected
    NOTCONN = 107,
    /// Cannot send after transport endpoint shutdown
    SHUTDOWN = 108,
    /// Too many references: cannot splice
    TOOMANYREFS = 109,
    /// Connection timed out
    TIMEDOUT = 110,
    /// Connection refused
    CONNREFUSED = 111,
    /// Host is down
    HOSTDOWN = 112,
    /// No route to host
    HOSTUNREACH = 113,
    /// Operation already in progress
    ALREADY = 114,
    /// Operation now in progress
    INPROGRESS = 115,
    /// Stale NFS file handle
    STALE = 116,
    /// Structure needs cleaning
    UCLEAN = 117,
    /// Not a XENIX named type file
    NOTNAM = 118,
    /// No XENIX semaphores available
    NAVAIL = 119,
    /// Is a named type file
    ISNAM = 120,
    /// Remote I/O error
    REMOTEIO = 121,
    /// Quota exceeded
    DQUOT = 122,
    /// No medium found
    NOMEDIUM = 123,
    /// Wrong medium type
    MEDIUMTYPE = 124,
    /// Operation canceled
    CANCELED = 125,
    /// Required key not available
    NOKEY = 126,
    /// Key has expired
    KEYEXPIRED = 127,
    /// Key has been revoked
    KEYREVOKED = 128,
    /// Key was rejected by service
    KEYREJECTED = 129,
    // for robust mutexes
    /// Owner died
    OWNERDEAD = 130,
    /// State not recoverable
    NOTRECOVERABLE = 131,
    /// Operation not possible due to RF-kill
    RFKILL = 132,
    /// Memory page has hardware error
    HWPOISON = 133,
    // nameserver query return codes
    /// DNS server returned answer with no data
    NSRNODATA = 160,
    /// DNS server claims query was misformatted
    NSRFORMERR = 161,
    /// DNS server returned general failure
    NSRSERVFAIL = 162,
    /// Domain name not found
    NSRNOTFOUND = 163,
    /// DNS server does not implement requested operation
    NSRNOTIMP = 164,
    /// DNS server refused query
    NSRREFUSED = 165,
    /// Misformatted DNS query
    NSRBADQUERY = 166,
    /// Misformatted domain name
    NSRBADNAME = 167,
    /// Unsupported address family
    NSRBADFAMILY = 168,
    /// Misformatted DNS reply
    NSRBADRESP = 169,
    /// Could not contact DNS servers
    NSRCONNREFUSED = 170,
    /// Timeout while contacting DNS servers
    NSRTIMEOUT = 171,
    /// End of file
    NSROF = 172,
    /// Error reading file
    NSRFILE = 173,
    /// Out of memory
    NSRNOMEM = 174,
    /// Application terminated lookup
    NSRDESTRUCTION = 175,
    /// Domain name is too long
    NSRQUERYDOMAINTOOLONG = 176,
    /// Domain name is too long
    NSRCNAMELOOP = 177,

    _,

    pub const NOTSUP = Errno.OPNOTSUPP;
};

// =============================================================================
// fcntl.h
// =============================================================================

pub const O = abi.O;

pub const F = struct {
    pub const DUPFD = 0;
    pub const GETFD = 1;
    pub const SETFD = 2;
    pub const GETFL = 3;
    pub const SETFL = 4;

    pub const GETLK = GET_SET_LK.GETLK;
    pub const SETLK = GET_SET_LK.SETLK;
    pub const SETLKW = GET_SET_LK.SETLKW;

    const GET_SET_LK = extern struct {
        pub const GETLK = 5;
        pub const SETLK = 6;
        pub const SETLKW = 7;
    };
    pub const SETOWN = 8;
    pub const GETOWN = 9;

    pub const SETSIG = 10;
    pub const GETSIG = 11;

    pub const SETOWN_EX = 15;
    pub const GETOWN_EX = 16;

    pub const GETOWNER_UIDS = 17;

    pub const OFD_GETLK = 36;
    pub const OFD_SETLK = 37;
    pub const OFD_SETLKW = 38;

    pub const RDLCK = 0;
    pub const WRLCK = 1;
    pub const UNLCK = 2;

    pub const LINUX_SPECIFIC_BASE = 1024;

    pub const SETLEASE = LINUX_SPECIFIC_BASE + 0;
    pub const GETLEASE = LINUX_SPECIFIC_BASE + 1;
    pub const NOTIFY = LINUX_SPECIFIC_BASE + 2;
    pub const DUPFD_QUERY = LINUX_SPECIFIC_BASE + 3;
    pub const CREATED_QUERY = LINUX_SPECIFIC_BASE + 4;
    pub const CANCELLK = LINUX_SPECIFIC_BASE + 5;
    pub const DUPFD_CLOEXEC = LINUX_SPECIFIC_BASE + 6;
    pub const SETPIPE_SZ = LINUX_SPECIFIC_BASE + 7;
    pub const GETPIPE_SZ = LINUX_SPECIFIC_BASE + 8;
    pub const ADD_SEALS = LINUX_SPECIFIC_BASE + 9;
    pub const GET_SEALS = LINUX_SPECIFIC_BASE + 10;

    pub const SEAL_SEAL = 0x0001;
    pub const SEAL_SHRINK = 0x0002;
    pub const SEAL_GROW = 0x0004;
    pub const SEAL_WRITE = 0x0008;
    pub const SEAL_FUTURE_WRITE = 0x0010;
    pub const SEAL_EXEC = 0x0020;

    pub const GET_RW_HINT = LINUX_SPECIFIC_BASE + 11;
    pub const SET_RW_HINT = LINUX_SPECIFIC_BASE + 12;
    pub const GET_FILE_RW_HINT = LINUX_SPECIFIC_BASE + 13;
    pub const SET_FILE_RW_HINT = LINUX_SPECIFIC_BASE + 14;
};

pub const ACCMODE = enum(u2) {
    RDONLY = 0,
    WRONLY = 1,
    RDWR = 2,
};

pub const AT = struct {
    pub const FDCWD = -100;
    pub const SYMLINK_NOFOLLOW = 0x100;
    pub const REMOVEDIR = 0x200;
    pub const SYMLINK_FOLLOW = 0x400;
    pub const NO_AUTOMOUNT = 0x800;
    pub const EMPTY_PATH = 0x1000;
    pub const STATX_SYNC_TYPE = 0x6000;
    pub const STATX_SYNC_AS_STAT = 0x0000;
    pub const STATX_FORCE_SYNC = 0x2000;
    pub const STATX_DONT_SYNC = 0x4000;
    pub const RECURSIVE = 0x8000;
    pub const HANDLE_FID = REMOVEDIR;
};

pub fn open(path: [:0]const u8, flags: O, mode: mode_t) Error!fd_t {
    const rc = syscall3(.open, @intFromPtr(path.ptr), @as(u32, @bitCast(flags)), mode);
    if (check_errno(rc)) |e| return switch (e) {
        .ACCES => error.PermissionDenied,
        .EXIST => error.FileExists,
        .ISDIR => error.UnexpectedDirFD,
        .MFILE => error.TooManyProcessFiles,
        .NFILE => error.TooManyFiles,
        .NODEV => error.InvalidDevice,
        .NOENT => error.FileDoesNotExist,
        .LOOP => error.TooManySymbolicLinks,
        .NAMETOOLONG => error.NameTooLong,
        else => blk: {
            log.warn("Unexpected errno for open: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };

    return @intCast(rc);
}

pub fn openat(dir_fd: dirfd_t, sub_path: [:0]const u8, flags: O, mode: mode_t) Error!fd_t {
    const rc = syscall4(
        .openat,
        zeroExtendToUsize(dir_fd),
        @intFromPtr(sub_path.ptr),
        zeroExtendToUsize(flags),
        mode,
    );
    if (check_errno(rc)) |e| return switch (e) {
        .BADF => error.InvalidFD,
        .ACCES => error.PermissionDenied,
        .EXIST => error.FileExists,
        .ISDIR => error.IsDirectory,
        .MFILE => error.TooManyProcessFiles,
        .NFILE => error.TooManyFiles,
        .NOENT => error.FileDoesNotExist,
        .NOTDIR => error.InvalidPath,
        .LOOP => error.TooManySymbolicLinks,
        .NAMETOOLONG => error.NameTooLong,
        else => blk: {
            log.warn("Unexpected errno for openat: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };

    return safeTrunc(c_int, rc);
}

pub fn fcntl(fd: fd_t, op: c_int, arg: usize) !c_int {
    const rc = syscall3(.fcntl, @as(u32, @bitCast(fd)), @as(u32, @bitCast(op)), arg);
    if (check_errno(rc)) |e| return switch (e) {
        else => blk: {
            log.warn("Unexpected errno for fcntl: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
    return @as(c_int, @intCast(rc));
}

// =============================================================================
// inotify.h
// =============================================================================

pub const InotifyEvent = extern struct {
    wd: i32,
    mask: IN,
    cookie: u32,
    len: u32,
    name: [0]u8,
};

pub const IN = packed struct(u32) {
    ACCESS: bool = false,
    MODIFY: bool = false,
    ATTRIB: bool = false,
    CLOSE_WRITE: bool = false,
    CLOSE_NOWRITE: bool = false,
    OPEN: bool = false,
    MOVED_FROM: bool = false,
    MOVED_TO: bool = false,
    CREATE: bool = false,
    DELETE: bool = false,
    DELETE_SELF: bool = false,
    MOVE_SELF: bool = false,

    __reserved0__: u1 = 0,

    UNMOUNT: bool = false,
    Q_OVERFLOW: bool = false,
    IGNORED: bool = false,

    __reserved1__: u8 = 0,

    ONLYDIR: bool = false,
    DONT_FOLLOW: bool = false,
    EXCL_UNLINK: bool = false,

    __reserved2__: u1 = 0,

    MASK_CREATE: bool = false,
    MASK_ADD: bool = false,
    ISDIR: bool = false,
    ONESHOT: bool = false,

    pub const CLOSE: IN = .{ .CLOSE_WRITE = true, .CLOSE_NOWRITE = true };
    pub const MOVE: IN = .{ .MOVED_FROM = true, .MOVED_TO = true };
};

pub fn inotify_init() Error!fd_t {
    const rc = syscall0(.inotify_init);
    if (check_errno(rc)) |e| return switch (e) {
        .MFILE => error.TooManyProcessFiles,
        .NFILE => error.TooManyFiles,
        .NOMEM => error.NoMemory,
        else => blk: {
            log.warn("Unexpected errno for inotify_init: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };

    return safeTrunc(fd_t, rc);
}

pub fn inotify_init1(flags: O) Error!fd_t {
    const rc = syscall1(
        .inotify_init1,
        zeroExtendToUsize(flags),
    );
    if (check_errno(rc)) |e| return switch (e) {
        .INVAL => error.InvalidArg,
        .MFILE => error.TooManyProcessFiles,
        .NFILE => error.TooManyFiles,
        .NOMEM => error.NoMemory,
        else => blk: {
            log.warn("Unexpected errno for inotify_init1: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };

    return safeTrunc(fd_t, rc);
}

pub fn inotify_add_watch(fd: fd_t, path: [:0]const u8, mask: IN) Error!c_int {
    const rc = syscall3(
        .inotify_add_watch,
        safeExtendToUsize(fd),
        @intFromPtr(path.ptr),
        zeroExtendToUsize(mask),
    );
    if (check_errno(rc)) |e| return switch (e) {
        .ACCES => error.PermissionDenied,
        .BADF => error.InvalidFD,
        .EXIST => error.FileExists,
        .INVAL => error.InvalidArg,
        .NAMETOOLONG => error.NameTooLong,
        .NOENT => error.FileDoesNotExist,
        .NOMEM => error.NoMemory,
        .NOSPC => error.NoSpaceLeft,
        .NOTDIR => error.InvalidPath,
        else => blk: {
            log.warn("Unexpected errno for inotify_add_watch: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };

    return safeTrunc(c_int, rc);
}

pub fn inotify_rm_watch(fd: fd_t, wd: c_int) Error!void {
    const rc = syscall2(
        .inotify_rm_watch,
        safeExtendToUsize(fd),
        safeExtendToUsize(wd),
    );
    if (check_errno(rc)) |e| return switch (e) {
        .BADF => error.InvalidFD,
        .INVAL => error.InvalidArg,
        else => blk: {
            log.warn("Unexpected errno for inotify_rm_watch: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
}

// =============================================================================
// input.h
// =============================================================================

pub const InputEvent = extern struct {
    time: timeval = .{ .sec = 0, .usec = 0 },
    type: EV = @enumFromInt(0),
    code: u16 = 0,
    value: i32 = 0,
};

pub const InputId = extern struct {
    bus_type: u16 = 0,
    vendor: u16 = 0,
    product: u16 = 0,
    version: u16 = 0,
};

pub const InputAbsInfo = extern struct {
    value: i32 = 0,
    minimum: i32 = 0,
    maximum: i32 = 0,
    fuzz: i32 = 0,
    flat: i32 = 0,
    resolution: i32 = 0,
};

pub const InputKeymapEntry = extern struct {
    flags: Flags = .{},
    len: u8 = 0,
    index: u16 = 0,
    keycode: u32 = 0,
    scancode: [32]u8 = @splat(0),

    pub const Flags = packed struct(u8) {
        KEYMAP_BY_INDEX: bool = false,
        __unused__: u7 = 0,
    };
};

pub const InputMask = extern struct {
    type: u32,
    codes_size: u32,
    codes_ptr: u64,
};

pub const FfEffect = extern struct {
    type: FF.EFFECT,
    id: i16 = 0,
    direction: u16 = 0,
    trigger: FfTrigger = .{},
    replay: FfReplay = .{},

    u: extern union {
        constant: FfConstantEffect,
        ramp: FfRampEffect,
        periodic: FfPeriodicEffect,
        condition: [2]FfConditionEffect,
        rumble: FfRumbleEffect,
        haptic: FfHapticEffect,
    },
};

pub const FfTrigger = extern struct {
    button: u16 = 0,
    interval: u16 = 0,
};

pub const FfReplay = extern struct {
    length: u16 = 0,
    delay: u16 = 0,
};

pub const FfConstantEffect = extern struct {
    level: i16 = 0,
    envelope: FfEnvelope = .{},
};

pub const FfRampEffect = extern struct {
    start_level: i16 = 0,
    end_level: i16 = 0,
    envelope: FfEnvelope = .{},
};

pub const FfPeriodicEffect = extern struct {
    waveform: FF.WAVEFORM,
    period: u16 = 0,
    magnitude: i16 = 0,
    offset: i16 = 0,
    phase: u16 = 0,
    envelope: FfEnvelope = .{},
    custom_len: u32 = 0,
    custom_data: ?*i16 = null,
};

pub const FfConditionEffect = extern struct {
    right_saturation: u16 = 0,
    left_saturation: u16 = 0,
    right_coeff: i16 = 0,
    left_coeff: i16 = 0,
    deadband: u16 = 0,
    center: i16 = 0,
};

pub const FfRumbleEffect = extern struct {
    strong_magnitude: u16 = 0,
    weak_magnitude: u16 = 0,
};

pub const FfHapticEffect = extern struct {
    hid_usage: u16 = 0,
    vendor_id: u16 = 0,
    vendor_waveform_page: u8 = 0,
    intensity: u16 = 0,
    repeat_count: u16 = 0,
    retrigger_period: u16 = 0,
};

pub const FfEnvelope = extern struct {
    attack_length: u16 = 0,
    attack_level: u16 = 0,
    fade_length: u16 = 0,
    fade_level: u16 = 0,
};

/// Get device id
pub const EVIOCGID: _IOC = _IOR('E', 0x02, InputId);
/// Get repeat settings
pub const EVIOCGREP: _IOC = _IOR('E', 0x03, [2]c_uint);
/// Set repeat settings
pub const EVIOCSREP: _IOC = _IOW('E', 0x03, [2]c_uint);
/// Get keycode
pub const EVIOCGKEYCODE: _IOC = _IOR('E', 0x04, [2]c_uint);
/// Get keycode
pub const EVIOCGKEYCODE_V2: _IOC = _IOR('E', 0x04, InputKeymapEntry);
/// Set keycode
pub const EVIOCSKEYCODE: _IOC = _IOW('E', 0x04, [2]c_uint);
/// Set keycode
pub const EVIOCSKEYCODE_V2: _IOC = _IOW('E', 0x04, InputKeymapEntry);
/// Get device name
pub inline fn EVIOCGNAME(len: _IOC.SizeInt) _IOC {
    return _IOC.init(IOC.READ, 'E', 0x06, len);
}
/// Get physical location
pub inline fn EVIOCGPHYS(len: _IOC.SizeInt) _IOC {
    return _IOC.init(IOC.READ, 'E', 0x07, len);
}
/// Get unique identifier
pub inline fn EVIOCGUNIQ(len: _IOC.SizeInt) _IOC {
    return _IOC.init(IOC.READ, 'E', 0x08, len);
}
/// Get device properties
pub inline fn EVIOCGPROP(len: _IOC.SizeInt) _IOC {
    return _IOC.init(IOC.READ, 'E', 0x09, len);
}
/// Get MT slot values
pub inline fn EVIOCGMTSLOTS(len: _IOC.SizeInt) _IOC {
    return _IOC.init(IOC.READ, 'E', 0x0a, len);
}
/// Get global key state
pub inline fn EVIOCGKEY(len: _IOC.SizeInt) _IOC {
    return _IOC.init(IOC.READ, 'E', 0x18, len);
}
/// Get all LEDs
pub inline fn EVIOCGLED(len: _IOC.SizeInt) _IOC {
    return _IOC.init(IOC.READ, 'E', 0x19, len);
}
/// Get all sounds status
pub inline fn EVIOCGSND(len: _IOC.SizeInt) _IOC {
    return _IOC.init(IOC.READ, 'E', 0x1a, len);
}
/// Get all switch states
pub inline fn EVIOCGSW(len: _IOC.SizeInt) _IOC {
    return _IOC.init(IOC.READ, 'E', 0x1b, len);
}
/// Get event bits
pub inline fn EVIOCGBIT(ev: u8, len: _IOC.SizeInt) _IOC {
    return _IOC.init(IOC.READ, 'E', 0x20 + ev, len);
}
/// Get abs value/limits
pub inline fn EVIOCGABS(abs: ABS) _IOC {
    return _IOR('E', 0x40 + @intFromEnum(abs), InputAbsInfo);
}
/// Set abs value/limits
pub inline fn EVIOCSABS(abs: ABS) _IOC {
    return _IOW('E', 0xc0 + @intFromEnum(abs), InputAbsInfo);
}
/// Send a force effect to a force feedback device
pub const EVIOCSFF: _IOC = _IOW('E', 0x80, FfEffect);
/// Erase a force effect
pub const EVIOCRMFF: _IOC = _IOW('E', 0x81, c_int);
/// Report number of effects playable at the same time
pub const EVIOCGEFFECTS: _IOC = _IOR('E', 0x84, c_int);
/// Grab/Release device
pub const EVIOCGRAB: _IOC = _IOW('E', 0x90, c_int);
/// Revoke device access
pub const EVIOCREVOKE: _IOC = _IOW('E', 0x91, c_int);
/// Retrieve current event mask
pub const EVIOCGMASK: _IOC = _IOR('E', 0x92, InputMask);
/// Set event mask
pub const EVIOCSMASK: _IOC = _IOW('E', 0x93, InputMask);
/// Set clockid to be used for timestamps
pub const EVIOCSCLOCKID: _IOC = _IOW('E', 0xa0, c_int);

// =============================================================================
// EVIOC-ioctl helpers
// =============================================================================

const sizeRequestFn = fn (_IOC.SizeInt) callconv(.@"inline") _IOC;

fn EnumBitSet(comptime T: type) type {
    return std.StaticBitSet(T.CNT);
}

pub inline fn ioctlRead(fd: fd_t, request: _IOC, arg: *anyopaque) IOCTLError!usize {
    assert(request.dir & IOC.READ == IOC.READ);
    const result = ioctl(fd, request, @intFromPtr(arg));
    return result;
}

pub inline fn ioctlWrite(fd: fd_t, request: _IOC, arg: *const anyopaque) IOCTLError!void {
    assert(request.dir & IOC.WRITE == IOC.WRITE);
    const result = try ioctl(fd, request, @intFromPtr(arg));
    assert(result == 0);
}

/// Functional buf size is buf.len - 1, null terminator is included
inline fn ioctlString(fd: fd_t, buf: []u8, comptime requestFn: sizeRequestFn) IOCTLError![:0]const u8 {
    assert(buf.len >= 1);

    const rc = try ioctlRead(fd, requestFn(@intCast(buf.len - 1)), buf.ptr);

    const result: [:0]const u8 = std.mem.span(@as([*:0]const u8, @ptrCast(buf.ptr)));
    assert(result.len == rc or result.len + 1 == rc);

    return result;
}

inline fn ioctlReadType(comptime T: type, fd: fd_t, comptime request: _IOC) IOCTLError!T {
    var result: T = std.mem.zeroes(T);
    const rc = try ioctlRead(fd, request, &result);
    assert(rc == 0);
    return result;
}

inline fn ioctlReadTypeSize(comptime T: type, fd: fd_t, comptime requestFn: sizeRequestFn) IOCTLError!T {
    var result: T = std.mem.zeroes(T);
    const rc = try ioctlRead(fd, requestFn(@sizeOf(T)), &result);
    assert(rc == @sizeOf(T));
    return result;
}

/// Get device id
pub inline fn ioctl_EVIOCGID(fd: fd_t) IOCTLError!InputId {
    const result = try ioctlReadType(InputId, fd, EVIOCGID);
    return result;
}

/// Get repeat settings
pub inline fn ioctl_EVIOCGREP(fd: fd_t) IOCTLError!?[2]c_uint {
    const result = ioctlReadType([2]c_uint, fd, EVIOCGREP) catch |e| switch (e) {
        error.Unsupported => null,
        else => e,
    };
    return result;
}

/// Set repeat settings
pub inline fn ioctl_EVIOCSREP(fd: fd_t, rep: [2]c_uint) IOCTLError!void {
    try ioctlWrite(fd, EVIOCSREP, &rep);
}

/// Get keycode
pub inline fn ioctl_EVIOCGKEYCODE(fd: fd_t, scancode: c_uint) IOCTLError!c_uint {
    var result: [2]c_uint = .{ scancode, 0 };
    const rc = try ioctlRead(fd, EVIOCGKEYCODE, &result);
    assert(rc == 0);
    return result[1];
}

/// Get keycode
pub inline fn ioctl_EVIOCGKEYCODE_V2(fd: fd_t, index: u16) IOCTLError!?InputKeymapEntry {
    var result: IOCTLError!?InputKeymapEntry = null;
    var entry: InputKeymapEntry = .{ .index = index, .flags = .{ .KEYMAP_BY_INDEX = true } };

    if (ioctl(fd, EVIOCGKEYCODE_V2, @intFromPtr(&entry))) |rc| {
        assert(rc == 0);
        result = entry;
    } else |e| switch (e) {
        error.InvalidRequestOrArg => result = null,
        else => result = e,
    }
    return result;
}

/// Set keycode
pub inline fn ioctl_EVIOCSKEYCODE(fd: fd_t, scancode: c_uint, keycode: c_uint) IOCTLError!void {
    const new_map: [2]c_uint = .{ scancode, keycode };
    try ioctlWrite(fd, EVIOCSKEYCODE, &new_map);
}

/// Set keycode
pub inline fn ioctl_EVIOCSKEYCODE_V2(fd: fd_t, entry: *const InputKeymapEntry) IOCTLError!void {
    try ioctlWrite(fd, EVIOCSKEYCODE_V2, entry);
}

/// Get device name
/// Functional buf size is buf.len - 1, null terminator is included
pub inline fn ioctl_EVIOCGNAME(fd: fd_t, buf: []u8) IOCTLError![:0]const u8 {
    const result = try ioctlString(fd, buf, EVIOCGNAME);
    return result;
}

/// Get physical location
/// Functional buf size is buf.len - 1, null terminator is included
pub inline fn ioctl_EVIOCGPHYS(fd: fd_t, buf: []u8) IOCTLError!?[:0]const u8 {
    const result: IOCTLError!?[:0]const u8 = ioctlString(fd, buf, EVIOCGPHYS) catch |e| switch (e) {
        error.FileDoesNotExist => null,
        else => e,
    };

    return result;
}

/// Get unique identifier
/// Functional buf size is buf.len - 1, null terminator is included
pub inline fn ioctl_EVIOCGUNIQ(fd: fd_t, buf: []u8) IOCTLError!?[:0]const u8 {
    const result: IOCTLError!?[:0]const u8 = ioctlString(fd, buf, EVIOCGUNIQ) catch |e| switch (e) {
        error.FileDoesNotExist => null,
        else => e,
    };

    return result;
}

/// Get device properties
pub inline fn ioctl_EVIOCGPROP(fd: fd_t) IOCTLError!InputProp {
    const result = try ioctlReadTypeSize(InputProp, fd, EVIOCGPROP);
    return result;
}

/// Get MT slot values
/// The length of 'slot_buf' must be 'slot_count + 1' because the code is put in the first slot for the ioctl request.
pub inline fn ioctl_EVIOCGMTSLOTS(fd: fd_t, slot: ABS.MT, slot_count: usize, slot_buf: []i32) IOCTLError![]i32 {
    assert(slot_count + 1 == slot_buf.len);
    slot_buf[0] = @intFromEnum(slot);
    const rc = try ioctlRead(fd, EVIOCGMTSLOTS(@intCast(slot_buf.len * @sizeOf(i32))), slot_buf.ptr);
    assert(rc == 0);
    return slot_buf[1..];
}

/// Get global key state
pub inline fn ioctl_EVIOCGKEY(fd: fd_t) IOCTLError!KEY.BitSet {
    const result = try ioctlReadTypeSize(KEY.BitSet, fd, EVIOCGKEY);
    return result;
}

/// Get all LEDs
pub inline fn ioctl_EVIOCGLED(fd: fd_t) IOCTLError!LED.BitSet {
    const result = try ioctlReadTypeSize(LED.BitSet, fd, EVIOCGLED);
    return result;
}

/// Get all sounds status
pub inline fn ioctl_EVIOCGSND(fd: fd_t) IOCTLError!SND.BitSet {
    const result = try ioctlReadTypeSize(SND.BitSet, fd, EVIOCGSND);
    return result;
}

/// Get all switch states
pub inline fn ioctl_EVIOCGSW(fd: fd_t) IOCTLError!SW.BitSet {
    const result = try ioctlReadTypeSize(SW.BitSet, fd, EVIOCGSW);
    return result;
}

/// Get event bits
pub inline fn ioctl_EVIOCGBIT(fd: fd_t, comptime ET: type) IOCTLError!EnumBitSet(ET) {
    const BitSet = EnumBitSet(ET);
    var result: BitSet = .empty;

    const ev: u8 = @intCast(EV.uintFromType(ET));

    const rc = try ioctlRead(fd, EVIOCGBIT(ev, @sizeOf(BitSet)), &result);
    assert(rc == @sizeOf(BitSet));

    return result;
}

/// Get abs value/limits
pub inline fn ioctl_EVIOCGABS(fd: fd_t, abs: ABS) IOCTLError!InputAbsInfo {
    var result: InputAbsInfo = .{};
    const rc = try ioctlRead(fd, EVIOCGABS(abs), &result);
    assert(rc == 0);
    return result;
}

/// Set abs value/limits
pub inline fn ioctl_EVIOCSABS(fd: fd_t, abs: ABS, abs_info: InputAbsInfo) IOCTLError!void {
    try ioctlWrite(fd, EVIOCSABS(abs), &abs_info);
}

/// Send a force effect to a force feedback device
/// New id is written back to 'effect'
pub inline fn ioctl_EVIOCSFF(fd: fd_t, effect: *FfEffect) IOCTLError!void {
    // Note: ioctlWrite takes a '*const anyopaque' and converts it to usize.
    //        Because the original pointer is mutable, the pointed-to storage can
    //        be written to by the kernel.
    try ioctlWrite(fd, EVIOCSFF, effect);
}

/// Erase a force effect
pub inline fn ioctl_EVIOCRMFF(fd: fd_t, id: u16) IOCTLError!void {
    const rc = try ioctl(fd, EVIOCRMFF, id);
    assert(rc == 0);
}

/// Report number of effect playable at the same time
pub inline fn ioctl_EVIOCGEFFECTS(fd: fd_t) IOCTLError!c_int {
    const result = try ioctlReadType(c_int, fd, EVIOCGEFFECTS);
    return result;
}

/// Grab/Release device
pub inline fn ioctl_EVIOCGRAB(fd: fd_t, grab: bool) IOCTLError!void {
    const rc = try ioctl(fd, EVIOCGRAB, @intFromBool(grab));
    assert(rc == 0);
}

/// Revoke device access
pub inline fn ioctl_EVIOCREVOKE(fd: fd_t) IOCTLError!void {
    const rc = try ioctl(fd, EVIOCREVOKE, 0);
    assert(rc == 0);
}

/// Retrieve current event mask
pub inline fn ioctl_EVIOCGMASK(fd: fd_t, comptime ET: type) IOCTLError!EnumBitSet(ET) {
    const BitSet = EnumBitSet(ET);
    var result: BitSet = .empty;

    var input_mask = InputMask{
        .type = EV.uintFromType(ET),
        .codes_size = @sizeOf(BitSet),
        .codes_ptr = @intFromPtr(&result),
    };

    const rc = try ioctlRead(fd, EVIOCGMASK, &input_mask);
    assert(rc == 0);

    return result;
}

/// Set event mask
pub inline fn ioctl_EVIOCSMASK(fd: fd_t, comptime ET: type, new_mask: *const EnumBitSet(ET)) IOCTLError!void {
    const input_mask = InputMask{
        .type = EV.uintFromType(ET),
        .codes_size = @sizeOf(EnumBitSet(ET)),
        .codes_ptr = @intFromPtr(new_mask),
    };

    try ioctlWrite(fd, EVIOCSMASK, &input_mask);
}

/// Set clockid to be used for timestamps
pub inline fn ioctl_EVIOCSCLOCKID(fd: fd_t, id: c_int) IOCTLError!void {
    try ioctlWrite(fd, EVIOCSCLOCKID, &id);
}

// =============================================================================
// input-event-codes.h
// =============================================================================

pub const InputProp = packed struct(u8) {
    pointer: bool = false,
    direct: bool = false,
    button_pad: bool = false,
    semi_mt: bool = false,
    top_button_pad: bool = false,
    pointing_stick: bool = false,
    accelerometer: bool = false,
    pressure_pad: bool = false,

    pub const MAX: u8 = 0x1f;
    pub const CNT: u8 = MAX + 1;
};

pub const EV = enum(u16) {
    SYN = 0x00,
    KEY = 0x01,
    REL = 0x02,
    ABS = 0x03,
    MSC = 0x04,
    SW = 0x05,
    LED = 0x11,
    SND = 0x12,
    REP = 0x14,
    FF = 0x15,
    PWR = 0x16,
    FF_STATUS = 0x17,

    pub const MAX: u16 = 0x1f;
    pub const CNT: u16 = MAX + 1;

    pub const BitSet = EnumBitSet(@This());

    fn uintFromType(comptime T: type) u16 {
        return switch (T) {
            else => @compileError("Invalid event type"),
            EV => 0,
            ABS, KEY, FF, REL, MSC, LED, SND, SW => @intFromEnum(@field(EV, meta.typeNameLeaf(T))),
        };
    }
};

pub const ABS = enum(u8) {
    X = 0x00,
    Y = 0x01,
    Z = 0x02,
    RX = 0x03,
    RY = 0x04,
    RZ = 0x05,
    THROTTLE = 0x06,
    RUDDER = 0x07,
    WHEEL = 0x08,
    GAS = 0x09,
    BRAKE = 0x0a,
    HAT0X = 0x10,
    HAT0Y = 0x11,
    HAT1X = 0x12,
    HAT1Y = 0x13,
    HAT2X = 0x14,
    HAT2Y = 0x15,
    HAT3X = 0x16,
    HAT3Y = 0x17,
    PRESSURE = 0x18,
    DISTANCE = 0x19,
    TILT_X = 0x1a,
    TILT_Y = 0x1b,
    TOOL_WIDTH = 0x1c,
    VOLUME = 0x20,
    PROFILE = 0x21,
    SND_PROFILE = 0x22,
    MISC = 0x28,
    RESERVED = 0x2e,
    MT_SLOT = 0x2f,
    MT_TOUCH_MAJOR = 0x30,
    MT_TOUCH_MINOR = 0x31,
    MT_WIDTH_MAJOR = 0x32,
    MT_WIDTH_MINOR = 0x33,
    MT_ORIENTATION = 0x34,
    MT_POSITION_X = 0x35,
    MT_POSITION_Y = 0x36,
    MT_TOOL_TYPE = 0x37,
    MT_BLOB_ID = 0x38,
    MT_TRACKING_ID = 0x39,
    MT_PRESSURE = 0x3a,
    MT_DISTANCE = 0x3b,
    MT_TOOL_X = 0x3c,
    MT_TOOL_Y = 0x3d,

    pub const MAX: u16 = 0x3f;
    pub const CNT: u16 = (MAX + 1);

    pub const MT = enum(u8) {
        TOUCH_MAJOR = @intFromEnum(ABS.MT_TOUCH_MAJOR),
        TOUCH_MINOR = @intFromEnum(ABS.MT_TOUCH_MINOR),
        WIDTH_MAJOR = @intFromEnum(ABS.MT_WIDTH_MAJOR),
        WIDTH_MINOR = @intFromEnum(ABS.MT_WIDTH_MINOR),
        ORIENTATION = @intFromEnum(ABS.MT_ORIENTATION),
        POSITION_X = @intFromEnum(ABS.MT_POSITION_X),
        POSITION_Y = @intFromEnum(ABS.MT_POSITION_Y),
        TOOL_TYPE = @intFromEnum(ABS.MT_TOOL_TYPE),
        BLOB_ID = @intFromEnum(ABS.MT_BLOB_ID),
        TRACKING_ID = @intFromEnum(ABS.MT_TRACKING_ID),
        PRESSURE = @intFromEnum(ABS.MT_PRESSURE),
        DISTANCE = @intFromEnum(ABS.MT_DISTANCE),
        TOOL_X = @intFromEnum(ABS.MT_TOOL_X),
        TOOL_Y = @intFromEnum(ABS.MT_TOOL_Y),
    };

    pub const BitSet = EnumBitSet(@This());
};

pub const FF = enum(u16) {
    HAPTIC = 0x4f,
    RUMBLE = 0x50,
    PERIODIC = 0x51,
    CONSTANT = 0x52,
    SPRING = 0x53,
    FRICTION = 0x54,
    DAMPER = 0x55,
    INERTIA = 0x56,
    RAMP = 0x57,

    SQUARE = 0x58,
    TRIANGLE = 0x59,
    SINE = 0x5a,
    SAW_UP = 0x5b,
    SAW_DOWN = 0x5c,
    CUSTOM = 0x5d,

    GAIN = 0x60,
    AUTOCENTER = 0x61,

    pub const EFFECT = enum(u16) {
        HAPTIC = @intFromEnum(FF.HAPTIC),
        RUMBLE = @intFromEnum(FF.RUMBLE),
        PERIODIC = @intFromEnum(FF.PERIODIC),
        CONSTANT = @intFromEnum(FF.CONSTANT),
        SPRING = @intFromEnum(FF.SPRING),
        FRICTION = @intFromEnum(FF.FRICTION),
        DAMPER = @intFromEnum(FF.DAMPER),
        INERTIA = @intFromEnum(FF.INERTIA),
        RAMP = @intFromEnum(FF.RAMP),
    };

    pub const WAVEFORM = enum(u16) {
        SQUARE = @intFromEnum(FF.SQUARE),
        TRIANGLE = @intFromEnum(FF.TRIANGLE),
        SINE = @intFromEnum(FF.SINE),
        SAW_UP = @intFromEnum(FF.SAW_UP),
        SAW_DOWN = @intFromEnum(FF.SAW_DOWN),
        CUSTOM = @intFromEnum(FF.CUSTOM),
    };

    pub const EFFECT_MIN: FF = .HAPTIC;
    pub const EFFECT_MAX: FF = .RAMP;
    pub const WAVEFORM_MIN: FF = .SQUARE;
    pub const WAVEFORM_MAX: FF = .CUSTOM;
    pub const MAX_EFFECTS: u16 = @intFromEnum(FF.GAIN);

    pub const MAX: u16 = 0x7f;
    pub const CNT: u16 = 0x80;

    pub const BitSet = EnumBitSet(@This());
};

pub const KEY = enum(u16) {
    RESERVED = 0,
    ESC = 1,
    @"1" = 2,
    @"2" = 3,
    @"3" = 4,
    @"4" = 5,
    @"5" = 6,
    @"6" = 7,
    @"7" = 8,
    @"8" = 9,
    @"9" = 10,
    @"0" = 11,
    MINUS = 12,
    EQUAL = 13,
    BACKSPACE = 14,
    TAB = 15,
    Q = 16,
    W = 17,
    E = 18,
    R = 19,
    T = 20,
    Y = 21,
    U = 22,
    I = 23,
    O = 24,
    P = 25,
    LEFTBRACE = 26,
    RIGHTBRACE = 27,
    ENTER = 28,
    LEFTCTRL = 29,
    A = 30,
    S = 31,
    D = 32,
    F = 33,
    G = 34,
    H = 35,
    J = 36,
    K = 37,
    L = 38,
    SEMICOLON = 39,
    APOSTROPHE = 40,
    GRAVE = 41,
    LEFTSHIFT = 42,
    BACKSLASH = 43,
    Z = 44,
    X = 45,
    C = 46,
    V = 47,
    B = 48,
    N = 49,
    M = 50,
    COMMA = 51,
    DOT = 52,
    SLASH = 53,
    RIGHTSHIFT = 54,
    KPASTERISK = 55,
    LEFTALT = 56,
    SPACE = 57,
    CAPSLOCK = 58,
    F1 = 59,
    F2 = 60,
    F3 = 61,
    F4 = 62,
    F5 = 63,
    F6 = 64,
    F7 = 65,
    F8 = 66,
    F9 = 67,
    F10 = 68,
    NUMLOCK = 69,
    SCROLLLOCK = 70,
    KP7 = 71,
    KP8 = 72,
    KP9 = 73,
    KPMINUS = 74,
    KP4 = 75,
    KP5 = 76,
    KP6 = 77,
    KPPLUS = 78,
    KP1 = 79,
    KP2 = 80,
    KP3 = 81,
    KP0 = 82,
    KPDOT = 83,
    ZENKAKUHANKAKU = 85,
    @"102ND" = 86,
    F11 = 87,
    F12 = 88,
    RO = 89,
    KATAKANA = 90,
    HIRAGANA = 91,
    HENKAN = 92,
    KATAKANAHIRAGANA = 93,
    MUHENKAN = 94,
    KPJPCOMMA = 95,
    KPENTER = 96,
    RIGHTCTRL = 97,
    KPSLASH = 98,
    SYSRQ = 99,
    RIGHTALT = 100,
    LINEFEED = 101,
    HOME = 102,
    UP = 103,
    PAGEUP = 104,
    LEFT = 105,
    RIGHT = 106,
    END = 107,
    DOWN = 108,
    PAGEDOWN = 109,
    INSERT = 110,
    DELETE = 111,
    MACRO = 112,
    MUTE = 113,
    VOLUMEDOWN = 114,
    VOLUMEUP = 115,
    POWER = 116,
    KPEQUAL = 117,
    KPPLUSMINUS = 118,
    PAUSE = 119,
    SCALE = 120,
    KPCOMMA = 121,
    HANGEUL = 122,
    HANJA = 123,
    YEN = 124,
    LEFTMETA = 125,
    RIGHTMETA = 126,
    COMPOSE = 127,
    STOP = 128,
    AGAIN = 129,
    PROPS = 130,
    UNDO = 131,
    FRONT = 132,
    COPY = 133,
    OPEN = 134,
    PASTE = 135,
    FIND = 136,
    CUT = 137,
    HELP = 138,
    MENU = 139,
    CALC = 140,
    SETUP = 141,
    SLEEP = 142,
    WAKEUP = 143,
    FILE = 144,
    SENDFILE = 145,
    DELETEFILE = 146,
    XFER = 147,
    PROG1 = 148,
    PROG2 = 149,
    WWW = 150,
    MSDOS = 151,
    COFFEE = 152,
    ROTATE_DISPLAY = 153,
    CYCLEWINDOWS = 154,
    MAIL = 155,
    BOOKMARKS = 156,
    COMPUTER = 157,
    BACK = 158,
    FORWARD = 159,
    CLOSECD = 160,
    EJECTCD = 161,
    EJECTCLOSECD = 162,
    NEXTSONG = 163,
    PLAYPAUSE = 164,
    PREVIOUSSONG = 165,
    STOPCD = 166,
    RECORD = 167,
    REWIND = 168,
    PHONE = 169,
    ISO = 170,
    CONFIG = 171,
    HOMEPAGE = 172,
    REFRESH = 173,
    EXIT = 174,
    MOVE = 175,
    EDIT = 176,
    SCROLLUP = 177,
    SCROLLDOWN = 178,
    KPLEFTPAREN = 179,
    KPRIGHTPAREN = 180,
    NEW = 181,
    REDO = 182,
    F13 = 183,
    F14 = 184,
    F15 = 185,
    F16 = 186,
    F17 = 187,
    F18 = 188,
    F19 = 189,
    F20 = 190,
    F21 = 191,
    F22 = 192,
    F23 = 193,
    F24 = 194,
    PLAYCD = 200,
    PAUSECD = 201,
    PROG3 = 202,
    PROG4 = 203,
    ALL_APPLICATIONS = 204,
    SUSPEND = 205,
    CLOSE = 206,
    PLAY = 207,
    FASTFORWARD = 208,
    BASSBOOST = 209,
    PRINT = 210,
    HP = 211,
    CAMERA = 212,
    SOUND = 213,
    QUESTION = 214,
    EMAIL = 215,
    CHAT = 216,
    SEARCH = 217,
    CONNECT = 218,
    FINANCE = 219,
    SPORT = 220,
    SHOP = 221,
    ALTERASE = 222,
    CANCEL = 223,
    BRIGHTNESSDOWN = 224,
    BRIGHTNESSUP = 225,
    MEDIA = 226,
    SWITCHVIDEOMODE = 227,
    KBDILLUMTOGGLE = 228,
    KBDILLUMDOWN = 229,
    KBDILLUMUP = 230,
    SEND = 231,
    REPLY = 232,
    FORWARDMAIL = 233,
    SAVE = 234,
    DOCUMENTS = 235,
    BATTERY = 236,
    BLUETOOTH = 237,
    WLAN = 238,
    UWB = 239,
    UNKNOWN = 240,
    VIDEO_NEXT = 241,
    VIDEO_PREV = 242,
    BRIGHTNESS_CYCLE = 243,
    BRIGHTNESS_AUTO = 244,
    DISPLAY_OFF = 245,
    WWAN = 246,
    RFKILL = 247,
    MICMUTE = 248,
    BTN_0 = 0x100,
    BTN_1 = 0x101,
    BTN_2 = 0x102,
    BTN_3 = 0x103,
    BTN_4 = 0x104,
    BTN_5 = 0x105,
    BTN_6 = 0x106,
    BTN_7 = 0x107,
    BTN_8 = 0x108,
    BTN_9 = 0x109,
    BTN_LEFT = 0x110,
    BTN_RIGHT = 0x111,
    BTN_MIDDLE = 0x112,
    BTN_SIDE = 0x113,
    BTN_EXTRA = 0x114,
    BTN_FORWARD = 0x115,
    BTN_BACK = 0x116,
    BTN_TASK = 0x117,
    BTN_TRIGGER = 0x120,
    BTN_THUMB = 0x121,
    BTN_THUMB2 = 0x122,
    BTN_TOP = 0x123,
    BTN_TOP2 = 0x124,
    BTN_PINKIE = 0x125,
    BTN_BASE = 0x126,
    BTN_BASE2 = 0x127,
    BTN_BASE3 = 0x128,
    BTN_BASE4 = 0x129,
    BTN_BASE5 = 0x12a,
    BTN_BASE6 = 0x12b,
    BTN_DEAD = 0x12f,
    BTN_SOUTH = 0x130,
    BTN_EAST = 0x131,
    BTN_C = 0x132,
    BTN_NORTH = 0x133,
    BTN_WEST = 0x134,
    BTN_Z = 0x135,
    BTN_TL = 0x136,
    BTN_TR = 0x137,
    BTN_TL2 = 0x138,
    BTN_TR2 = 0x139,
    BTN_SELECT = 0x13a,
    BTN_START = 0x13b,
    BTN_MODE = 0x13c,
    BTN_THUMBL = 0x13d,
    BTN_THUMBR = 0x13e,
    BTN_TOOL_PEN = 0x140,
    BTN_TOOL_RUBBER = 0x141,
    BTN_TOOL_BRUSH = 0x142,
    BTN_TOOL_PENCIL = 0x143,
    BTN_TOOL_AIRBRUSH = 0x144,
    BTN_TOOL_FINGER = 0x145,
    BTN_TOOL_MOUSE = 0x146,
    BTN_TOOL_LENS = 0x147,
    BTN_TOOL_QUINTTAP = 0x148,
    BTN_STYLUS3 = 0x149,
    BTN_TOUCH = 0x14a,
    BTN_STYLUS = 0x14b,
    BTN_STYLUS2 = 0x14c,
    BTN_TOOL_DOUBLETAP = 0x14d,
    BTN_TOOL_TRIPLETAP = 0x14e,
    BTN_TOOL_QUADTAP = 0x14f,
    BTN_GEAR_DOWN = 0x150,
    BTN_GEAR_UP = 0x151,
    OK = 0x160,
    SELECT = 0x161,
    GOTO = 0x162,
    CLEAR = 0x163,
    POWER2 = 0x164,
    OPTION = 0x165,
    INFO = 0x166,
    TIME = 0x167,
    VENDOR = 0x168,
    ARCHIVE = 0x169,
    PROGRAM = 0x16a,
    CHANNEL = 0x16b,
    FAVORITES = 0x16c,
    EPG = 0x16d,
    PVR = 0x16e,
    MHP = 0x16f,
    LANGUAGE = 0x170,
    TITLE = 0x171,
    SUBTITLE = 0x172,
    ANGLE = 0x173,
    FULL_SCREEN = 0x174,
    MODE = 0x175,
    KEYBOARD = 0x176,
    ASPECT_RATIO = 0x177,
    PC = 0x178,
    TV = 0x179,
    TV2 = 0x17a,
    VCR = 0x17b,
    VCR2 = 0x17c,
    SAT = 0x17d,
    SAT2 = 0x17e,
    CD = 0x17f,
    TAPE = 0x180,
    RADIO = 0x181,
    TUNER = 0x182,
    PLAYER = 0x183,
    TEXT = 0x184,
    DVD = 0x185,
    AUX = 0x186,
    MP3 = 0x187,
    AUDIO = 0x188,
    VIDEO = 0x189,
    DIRECTORY = 0x18a,
    LIST = 0x18b,
    MEMO = 0x18c,
    CALENDAR = 0x18d,
    RED = 0x18e,
    GREEN = 0x18f,
    YELLOW = 0x190,
    BLUE = 0x191,
    CHANNELUP = 0x192,
    CHANNELDOWN = 0x193,
    FIRST = 0x194,
    LAST = 0x195,
    AB = 0x196,
    NEXT = 0x197,
    RESTART = 0x198,
    SLOW = 0x199,
    SHUFFLE = 0x19a,
    BREAK = 0x19b,
    PREVIOUS = 0x19c,
    DIGITS = 0x19d,
    TEEN = 0x19e,
    TWEN = 0x19f,
    VIDEOPHONE = 0x1a0,
    GAMES = 0x1a1,
    ZOOMIN = 0x1a2,
    ZOOMOUT = 0x1a3,
    ZOOMRESET = 0x1a4,
    WORDPROCESSOR = 0x1a5,
    EDITOR = 0x1a6,
    SPREADSHEET = 0x1a7,
    GRAPHICSEDITOR = 0x1a8,
    PRESENTATION = 0x1a9,
    DATABASE = 0x1aa,
    NEWS = 0x1ab,
    VOICEMAIL = 0x1ac,
    ADDRESSBOOK = 0x1ad,
    MESSENGER = 0x1ae,
    DISPLAYTOGGLE = 0x1af,
    SPELLCHECK = 0x1b0,
    LOGOFF = 0x1b1,
    DOLLAR = 0x1b2,
    EURO = 0x1b3,
    FRAMEBACK = 0x1b4,
    FRAMEFORWARD = 0x1b5,
    CONTEXT_MENU = 0x1b6,
    MEDIA_REPEAT = 0x1b7,
    @"10CHANNELSUP" = 0x1b8,
    @"10CHANNELSDOWN" = 0x1b9,
    IMAGES = 0x1ba,
    NOTIFICATION_CENTER = 0x1bc,
    PICKUP_PHONE = 0x1bd,
    HANGUP_PHONE = 0x1be,
    LINK_PHONE = 0x1bf,
    DEL_EOL = 0x1c0,
    DEL_EOS = 0x1c1,
    INS_LINE = 0x1c2,
    DEL_LINE = 0x1c3,
    FN = 0x1d0,
    FN_ESC = 0x1d1,
    FN_F1 = 0x1d2,
    FN_F2 = 0x1d3,
    FN_F3 = 0x1d4,
    FN_F4 = 0x1d5,
    FN_F5 = 0x1d6,
    FN_F6 = 0x1d7,
    FN_F7 = 0x1d8,
    FN_F8 = 0x1d9,
    FN_F9 = 0x1da,
    FN_F10 = 0x1db,
    FN_F11 = 0x1dc,
    FN_F12 = 0x1dd,
    FN_1 = 0x1de,
    FN_2 = 0x1df,
    FN_D = 0x1e0,
    FN_E = 0x1e1,
    FN_F = 0x1e2,
    FN_S = 0x1e3,
    FN_B = 0x1e4,
    FN_RIGHT_SHIFT = 0x1e5,
    BRL_DOT1 = 0x1f1,
    BRL_DOT2 = 0x1f2,
    BRL_DOT3 = 0x1f3,
    BRL_DOT4 = 0x1f4,
    BRL_DOT5 = 0x1f5,
    BRL_DOT6 = 0x1f6,
    BRL_DOT7 = 0x1f7,
    BRL_DOT8 = 0x1f8,
    BRL_DOT9 = 0x1f9,
    BRL_DOT10 = 0x1fa,
    NUMERIC_0 = 0x200,
    NUMERIC_1 = 0x201,
    NUMERIC_2 = 0x202,
    NUMERIC_3 = 0x203,
    NUMERIC_4 = 0x204,
    NUMERIC_5 = 0x205,
    NUMERIC_6 = 0x206,
    NUMERIC_7 = 0x207,
    NUMERIC_8 = 0x208,
    NUMERIC_9 = 0x209,
    NUMERIC_STAR = 0x20a,
    NUMERIC_POUND = 0x20b,
    NUMERIC_A = 0x20c,
    NUMERIC_B = 0x20d,
    NUMERIC_C = 0x20e,
    NUMERIC_D = 0x20f,
    CAMERA_FOCUS = 0x210,
    WPS_BUTTON = 0x211,
    TOUCHPAD_TOGGLE = 0x212,
    TOUCHPAD_ON = 0x213,
    TOUCHPAD_OFF = 0x214,
    CAMERA_ZOOMIN = 0x215,
    CAMERA_ZOOMOUT = 0x216,
    CAMERA_UP = 0x217,
    CAMERA_DOWN = 0x218,
    CAMERA_LEFT = 0x219,
    CAMERA_RIGHT = 0x21a,
    ATTENDANT_ON = 0x21b,
    ATTENDANT_OFF = 0x21c,
    ATTENDANT_TOGGLE = 0x21d,
    LIGHTS_TOGGLE = 0x21e,
    BTN_DPAD_UP = 0x220,
    BTN_DPAD_DOWN = 0x221,
    BTN_DPAD_LEFT = 0x222,
    BTN_DPAD_RIGHT = 0x223,
    ALS_TOGGLE = 0x230,
    ROTATE_LOCK_TOGGLE = 0x231,
    REFRESH_RATE_TOGGLE = 0x232,
    BUTTONCONFIG = 0x240,
    TASKMANAGER = 0x241,
    JOURNAL = 0x242,
    CONTROLPANEL = 0x243,
    APPSELECT = 0x244,
    SCREENSAVER = 0x245,
    VOICECOMMAND = 0x246,
    ASSISTANT = 0x247,
    KBD_LAYOUT_NEXT = 0x248,
    EMOJI_PICKER = 0x249,
    DICTATE = 0x24a,
    CAMERA_ACCESS_ENABLE = 0x24b,
    CAMERA_ACCESS_DISABLE = 0x24c,
    CAMERA_ACCESS_TOGGLE = 0x24d,
    ACCESSIBILITY = 0x24e,
    DO_NOT_DISTURB = 0x24f,
    BRIGHTNESS_MIN = 0x250,
    BRIGHTNESS_MAX = 0x251,
    EPRIVACY_SCREEN_ON = 0x252,
    EPRIVACY_SCREEN_OFF = 0x253,
    ACTION_ON_SELECTION = 0x254,
    CONTEXTUAL_INSERT = 0x255,
    CONTEXTUAL_QUERY = 0x256,
    KBDINPUTASSIST_PREV = 0x260,
    KBDINPUTASSIST_NEXT = 0x261,
    KBDINPUTASSIST_PREVGROUP = 0x262,
    KBDINPUTASSIST_NEXTGROUP = 0x263,
    KBDINPUTASSIST_ACCEPT = 0x264,
    KBDINPUTASSIST_CANCEL = 0x265,
    RIGHT_UP = 0x266,
    RIGHT_DOWN = 0x267,
    LEFT_UP = 0x268,
    LEFT_DOWN = 0x269,
    ROOT_MENU = 0x26a,
    MEDIA_TOP_MENU = 0x26b,
    NUMERIC_11 = 0x26c,
    NUMERIC_12 = 0x26d,
    AUDIO_DESC = 0x26e,
    @"3D_MODE" = 0x26f,
    NEXT_FAVORITE = 0x270,
    STOP_RECORD = 0x271,
    PAUSE_RECORD = 0x272,
    VOD = 0x273,
    UNMUTE = 0x274,
    FASTREVERSE = 0x275,
    SLOWREVERSE = 0x276,
    DATA = 0x277,
    ONSCREEN_KEYBOARD = 0x278,
    PRIVACY_SCREEN_TOGGLE = 0x279,
    SELECTIVE_SCREENSHOT = 0x27a,
    NEXT_ELEMENT = 0x27b,
    PREVIOUS_ELEMENT = 0x27c,
    AUTOPILOT_ENGAGE_TOGGLE = 0x27d,
    MARK_WAYPOINT = 0x27e,
    SOS = 0x27f,
    NAV_CHART = 0x280,
    FISHING_CHART = 0x281,
    SINGLE_RANGE_RADAR = 0x282,
    DUAL_RANGE_RADAR = 0x283,
    RADAR_OVERLAY = 0x284,
    TRADITIONAL_SONAR = 0x285,
    CLEARVU_SONAR = 0x286,
    SIDEVU_SONAR = 0x287,
    NAV_INFO = 0x288,
    BRIGHTNESS_MENU = 0x289,
    MACRO1 = 0x290,
    MACRO2 = 0x291,
    MACRO3 = 0x292,
    MACRO4 = 0x293,
    MACRO5 = 0x294,
    MACRO6 = 0x295,
    MACRO7 = 0x296,
    MACRO8 = 0x297,
    MACRO9 = 0x298,
    MACRO10 = 0x299,
    MACRO11 = 0x29a,
    MACRO12 = 0x29b,
    MACRO13 = 0x29c,
    MACRO14 = 0x29d,
    MACRO15 = 0x29e,
    MACRO16 = 0x29f,
    MACRO17 = 0x2a0,
    MACRO18 = 0x2a1,
    MACRO19 = 0x2a2,
    MACRO20 = 0x2a3,
    MACRO21 = 0x2a4,
    MACRO22 = 0x2a5,
    MACRO23 = 0x2a6,
    MACRO24 = 0x2a7,
    MACRO25 = 0x2a8,
    MACRO26 = 0x2a9,
    MACRO27 = 0x2aa,
    MACRO28 = 0x2ab,
    MACRO29 = 0x2ac,
    MACRO30 = 0x2ad,
    MACRO_RECORD_START = 0x2b0,
    MACRO_RECORD_STOP = 0x2b1,
    MACRO_PRESET_CYCLE = 0x2b2,
    MACRO_PRESET1 = 0x2b3,
    MACRO_PRESET2 = 0x2b4,
    MACRO_PRESET3 = 0x2b5,
    KBD_LCD_MENU1 = 0x2b8,
    KBD_LCD_MENU2 = 0x2b9,
    KBD_LCD_MENU3 = 0x2ba,
    KBD_LCD_MENU4 = 0x2bb,
    KBD_LCD_MENU5 = 0x2bc,
    BTN_TRIGGER_HAPPY1 = 0x2c0,
    BTN_TRIGGER_HAPPY2 = 0x2c1,
    BTN_TRIGGER_HAPPY3 = 0x2c2,
    BTN_TRIGGER_HAPPY4 = 0x2c3,
    BTN_TRIGGER_HAPPY5 = 0x2c4,
    BTN_TRIGGER_HAPPY6 = 0x2c5,
    BTN_TRIGGER_HAPPY7 = 0x2c6,
    BTN_TRIGGER_HAPPY8 = 0x2c7,
    BTN_TRIGGER_HAPPY9 = 0x2c8,
    BTN_TRIGGER_HAPPY10 = 0x2c9,
    BTN_TRIGGER_HAPPY11 = 0x2ca,
    BTN_TRIGGER_HAPPY12 = 0x2cb,
    BTN_TRIGGER_HAPPY13 = 0x2cc,
    BTN_TRIGGER_HAPPY14 = 0x2cd,
    BTN_TRIGGER_HAPPY15 = 0x2ce,
    BTN_TRIGGER_HAPPY16 = 0x2cf,
    BTN_TRIGGER_HAPPY17 = 0x2d0,
    BTN_TRIGGER_HAPPY18 = 0x2d1,
    BTN_TRIGGER_HAPPY19 = 0x2d2,
    BTN_TRIGGER_HAPPY20 = 0x2d3,
    BTN_TRIGGER_HAPPY21 = 0x2d4,
    BTN_TRIGGER_HAPPY22 = 0x2d5,
    BTN_TRIGGER_HAPPY23 = 0x2d6,
    BTN_TRIGGER_HAPPY24 = 0x2d7,
    BTN_TRIGGER_HAPPY25 = 0x2d8,
    BTN_TRIGGER_HAPPY26 = 0x2d9,
    BTN_TRIGGER_HAPPY27 = 0x2da,
    BTN_TRIGGER_HAPPY28 = 0x2db,
    BTN_TRIGGER_HAPPY29 = 0x2dc,
    BTN_TRIGGER_HAPPY30 = 0x2dd,
    BTN_TRIGGER_HAPPY31 = 0x2de,
    BTN_TRIGGER_HAPPY32 = 0x2df,
    BTN_TRIGGER_HAPPY33 = 0x2e0,
    BTN_TRIGGER_HAPPY34 = 0x2e1,
    BTN_TRIGGER_HAPPY35 = 0x2e2,
    BTN_TRIGGER_HAPPY36 = 0x2e3,
    BTN_TRIGGER_HAPPY37 = 0x2e4,
    BTN_TRIGGER_HAPPY38 = 0x2e5,
    BTN_TRIGGER_HAPPY39 = 0x2e6,
    BTN_TRIGGER_HAPPY40 = 0x2e7,

    pub const MAX: u16 = 0x2ff;
    pub const BTN_MISC: KEY = .BTN_0;
    pub const BTN_MOUSE: KEY = .BTN_LEFT;
    pub const BTN_JOYSTICK: KEY = .BTN_TRIGGER;
    pub const BTN_GAMEPAD: KEY = .BTN_SOUTH;
    pub const BTN_DIGI: KEY = .BTN_TOOL_PEN;
    pub const BTN_WHEEL: KEY = .BTN_GEAR_DOWN;
    pub const BTN_TRIGGER_HAPPY: KEY = .BTN_TRIGGER_HAPPY1;
    pub const HANGUEL: KEY = .HANGEUL;
    pub const SCREENLOCK: KEY = .COFFEE;
    pub const DIRECTION: KEY = .ROTATE_DISPLAY;
    pub const DASHBOARD: KEY = .ALL_APPLICATIONS;
    pub const BRIGHTNESS_ZERO: KEY = .BRIGHTNESS_AUTO;
    pub const WIMAX: KEY = .WWAN;
    pub const BTN_A: KEY = .BTN_SOUTH;
    pub const BTN_B: KEY = .BTN_EAST;
    pub const BTN_X: KEY = .BTN_NORTH;
    pub const BTN_Y: KEY = .BTN_WEST;
    pub const ZOOM: KEY = .FULL_SCREEN;
    pub const SCREEN: KEY = .ASPECT_RATIO;
    pub const BRIGHTNESS_TOGGLE: KEY = .DISPLAYTOGGLE;
    pub const MIN_INTERESTING: KEY = .MUTE;

    pub const CNT: u16 = (MAX + 1);

    pub const BitSet = EnumBitSet(@This());
};

pub const SYN = enum(u16) {
    REPORT = 0,
    CONFIG = 1,
    MT_REPORT = 2,
    DROPPED = 3,

    pub const MAX: u16 = 0xf;
    pub const CNT: u16 = MAX + 1;
};

pub const REL = enum(u8) {
    X = 0x00,
    Y = 0x01,
    Z = 0x02,
    RX = 0x03,
    RY = 0x04,
    RZ = 0x05,
    HWHEEL = 0x06,
    DIAL = 0x07,
    WHEEL = 0x08,
    MISC = 0x09,

    /// 0x0a is reserved and should not be used in input drivers.
    /// It was used by HID as REL_MISC+1 and userspace needs to detect if
    /// the next REL_* event is correct or is just REL_MISC + n.
    /// We define here REL_RESERVED so userspace can rely on it and detect
    /// the situation described above.
    RESERVED = 0x0a,
    WHEEL_HI_RES = 0x0b,
    HWHEEL_HI_RES = 0x0c,

    pub const MAX: u8 = 0x0f;
    pub const CNT: u8 = MAX + 1;
};

pub const MSC = enum(u8) {
    SERIAL = 0x00,
    PULSELED = 0x01,
    GESTURE = 0x02,
    RAW = 0x03,
    SCAN = 0x04,
    TIMESTAMP = 0x05,

    pub const MAX: u8 = 0x07;
    pub const CNT: u8 = MAX + 1;
};

pub const LED = enum(u8) {
    NUML = 0x00,
    CAPSL = 0x01,
    SCROLLL = 0x02,
    COMPOSE = 0x03,
    KANA = 0x04,
    SLEEP = 0x05,
    SUSPEND = 0x06,
    MUTE = 0x07,
    MISC = 0x08,
    MAIL = 0x09,
    CHARGING = 0x0a,

    pub const MAX: u8 = 0x0f;
    pub const CNT: u8 = MAX + 1;

    pub const BitSet = EnumBitSet(@This());
};

pub const SND = enum(u8) {
    CLICK = 0x00,
    BELL = 0x01,
    TONE = 0x02,

    pub const MAX: u8 = 0x07;
    pub const CNT: u8 = MAX + 1;

    pub const BitSet = EnumBitSet(@This());
};

pub const SW = enum(u8) {
    /// set = lid shut
    LID = 0x00,
    /// set = tablet mode
    TABLET_MODE = 0x01,
    /// set = inserted
    HEADPHONE_INSERT = 0x02,
    /// rfkill master switch, type "any"
    RFKILL_ALL = 0x03,
    /// set = inserted
    MICROPHONE_INSERT = 0x04,
    /// set = plugged into dock
    DOCK = 0x05,
    /// set = inserted
    LINEOUT_INSERT = 0x06,
    /// set = mechanical switch set
    JACK_PHYSICAL_INSERT = 0x07,
    /// set = inserted
    VIDEOOUT_INSERT = 0x08,
    /// set = lens covered
    CAMERA_LENS_COVER = 0x09,
    /// set = keypad slide out
    KEYPAD_SLIDE = 0x0a,
    /// set = front proximity sensor active
    FRONT_PROXIMITY = 0x0b,
    /// set = rotate locked/disabled
    ROTATE_LOCK = 0x0c,
    /// set = inserted
    LINEIN_INSERT = 0x0d,
    /// set = device disabled
    MUTE_DEVICE = 0x0e,
    /// set = pen inserted
    PEN_INSERTED = 0x0f,
    /// set = cover closed
    MACHINE_COVER = 0x10,
    /// set = USB audio device connected
    USB_INSERT = 0x11,

    /// deprecated
    /// set = radio enabled
    pub const SW_RADIO: SW = .RFKILL_ALL;

    pub const MAX: u8 = 0x11;
    pub const CNT: u8 = MAX + 1;

    pub const BitSet = EnumBitSet(@This());
};

// =============================================================================
// ioctl.h
// =============================================================================

pub const IOCTLError = Error || error{
    // Unknown,
    Unsupported,
    ArgIsInvalidPointer,
    InvalidRequestOrArg,
    InvalidFDForRequest,
};

pub const _IOC = packed struct(u32) {
    pub const SizeInt = @Int(.unsigned, IOC.SIZE);
    pub const DirectionInt = @Int(.unsigned, IOC.DIR);

    nr: u8,
    type: u8,
    size: SizeInt,
    dir: DirectionInt,

    pub inline fn init(dir: DirectionInt, @"type": u8, nr: u8, size: SizeInt) _IOC {
        const result: _IOC = .{ .nr = nr, .type = @"type", .size = size, .dir = dir };
        return result;
    }
};

pub inline fn _IOR(@"type": u8, nr: u8, comptime T: type) _IOC {
    return _IOC.init(IOC.READ, @"type", nr, @sizeOf(T));
}

pub inline fn _IOW(@"type": u8, nr: u8, comptime T: type) _IOC {
    return _IOC.init(IOC.WRITE, @"type", nr, @sizeOf(T));
}

pub inline fn _IOWR(@"type": u8, nr: u8, comptime T: type) _IOC {
    return _IOC.init(IOC.READ | IOC.WRITE, @"type", nr, @sizeOf(T));
}

pub fn ioctl(fd: fd_t, request: _IOC, arg: usize) IOCTLError!usize {
    const rc = syscall3(.ioctl, @as(u32, @bitCast(fd)), @as(u32, @bitCast(request)), arg);

    if (check_errno(rc)) |e| return switch (e) {
        .BADF => error.InvalidFD,
        .FAULT => error.ArgIsInvalidPointer,
        .INVAL => error.InvalidRequestOrArg,
        .IO => error.IO,
        .NOTTY => error.InvalidFDForRequest,
        .INTR => error.Interrupt,
        .ACCES, .PERM => error.PermissionDenied,
        .NOENT => error.FileDoesNotExist,
        .NODEV => error.InvalidDevice,
        .NOSYS => error.Unsupported,
        else => blk: {
            log.warn("Unexpected errno for ioctl: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };

    return @intCast(rc);
}

// =============================================================================
// ioctls.h
// =============================================================================

pub const IOC = abi.IOC;

// =============================================================================
// limits.h
// =============================================================================
//
pub const NR_OPEN = 1024;

/// supplemental group IDs are available
pub const NGROUPS_MAX = 65536;
/// # bytes of args + environ for exec()
pub const ARG_MAX = 131072;
/// # links a file may have
pub const LINK_MAX = 127;
/// size of the canonical input queue
pub const MAX_CANON = 255;
/// size of the type-ahead buffer
pub const MAX_INPUT = 255;
/// # chars in a file name
pub const NAME_MAX = 255;
/// # chars in a path name including nul
pub const PATH_MAX = 4096;
/// # bytes in atomic write to a pipe
pub const PIPE_BUF = 4096;
/// # chars in an extended attribute name
pub const XATTR_NAME_MAX = 255;
/// size of an extended attribute value (64k)
pub const XATTR_SIZE_MAX = 65536;
/// size of extended attribute namelist (64k)
pub const XATTR_LIST_MAX = 65536;

pub const RTSIG_MAX = 32;

// =============================================================================
// mman-common.h
// =============================================================================

pub const MAP = abi.MAP;
pub const PROT = abi.PROT;

pub const MAP_TYPE = enum(u4) {
    SHARED = 0x01,
    PRIVATE = 0x02,
    SHARED_VALIDATE = 0x03,
    DROPPABLE = 0x08,
};

pub fn mmap(addr: ?[*]align(page_size) u8, length: usize, prot: PROT, flags: MAP, fd: fd_t, offset: off_t) Error![]align(page_size) u8 {
    const rc = syscall6(
        .mmap,
        @intFromPtr(addr),
        length,
        @as(u32, @bitCast(prot)),
        @as(u32, @bitCast(flags)),
        @as(u32, @bitCast(fd)),
        @bitCast(offset),
    );
    if (check_errno(rc)) |e| return switch (e) {
        .BADF => error.InvalidFD,
        .INVAL => error.InvalidArg,
        .ACCES => error.PermissionDenied,
        .NOMEM => error.NoMemory,
        .AGAIN => error.Lock,
        else => blk: {
            log.warn("Unexpected errno for mmap: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };

    return @as([*]align(page_size) u8, @ptrFromInt(@as(usize, @bitCast(rc))))[0..length];
}

pub fn mprotect(slice: []align(page_size) const u8, prot: PROT) Error!void {
    const rc = syscall3(.mprotect, @intFromPtr(slice.ptr), slice.len, @as(u32, @bitCast(prot)));
    if (check_errno(rc)) |e| return switch (e) {
        .INVAL => error.InvalidArg,
        else => blk: {
            log.warn("Unexpected errno for mprotect: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
}

pub fn munmap(memory: []align(page_size) const u8) Error!void {
    const rc = syscall2(.munmap, @intFromPtr(memory.ptr), memory.len);
    if (check_errno(rc)) |e| return switch (e) {
        .INVAL => error.InvalidArg,
        else => blk: {
            log.warn("Unexpected errno for munmap: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
}

// =============================================================================
// net.h
// =============================================================================

pub const SOCK = struct {
    pub const STREAM = 1;
    pub const DGRAM = 2;
    pub const RAW = 3;
    pub const RDM = 4;
    pub const SEQPACKET = 5;
    pub const DCCP = 6;
    pub const PACKET = 10;
    pub const CLOEXEC = 0o2000000;
    pub const NONBLOCK = 0o4000;
};

// =============================================================================
// poll.h
// =============================================================================

pub const POLL = abi.POLL;

pub const pollfd = extern struct {
    fd: fd_t,
    events: i16,
    revents: i16,
};

pub fn poll(fds: []pollfd, timeout: c_int) Error!c_int {
    const rc = syscall3(.poll, @intFromPtr(fds.ptr), fds.len, @as(u32, @bitCast(timeout)));
    if (check_errno(rc)) |e| return switch (e) {
        .BADF => error.InvalidFD,
        .FAULT => error.InvalidPointer,
        .INTR => error.Interrupt,
        .INVAL => error.InvalidArg,
        else => blk: {
            log.warn("Unexpected errno for poll: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
    return @intCast(rc);
}

// =============================================================================
// posix_acl.h
// =============================================================================

pub const ACL = struct {
    pub const UNDEFINED_ID = -1;

    pub const TYPE = enum(u16) {
        ACCESS = 0x8000,
        DEFAULT = 0x400,
    };

    pub const Tag = enum(u16) {
        USER_OBJ = 0x01,
        USER = 0x02,
        GROUP_OBJ = 0x04,
        GROUP = 0x08,
        MASK = 0x10,
        OTHER = 0x20,
    };

    pub const Permission = packed struct(u16) {
        EXECUTE: bool = false,
        WRITE: bool = false,
        READ: bool = false,
        __reserved__: u13 = 0,
    };
};

// =============================================================================
// posix_acl_xattr.h
// =============================================================================

pub const PosixAclXattrHeader = extern struct {
    a_version: u32,
};

pub const PosixAclXattrEntry = extern struct {
    e_tag: ACL.Tag,
    e_perm: ACL.Permission,
    e_id: u32,
};

// =============================================================================
// socket.h
// =============================================================================

pub const SO = abi.SO;

pub const SOL = struct {
    pub const SOCKET = 1;

    pub const IP = 0;
    pub const IPV6 = 41;
    pub const ICMPV6 = 58;

    pub const RAW = 255;
    pub const DECNET = 261;
    pub const X25 = 262;
    pub const PACKET = 263;
    pub const ATM = 264;
    pub const AAL = 265;
    pub const IRDA = 266;
    pub const NETBEUI = 267;
    pub const LLC = 268;
    pub const DCCP = 269;
    pub const NETLINK = 270;
    pub const TIPC = 271;
    pub const RXRPC = 272;
    pub const PPPOL2TP = 273;
    pub const BLUETOOTH = 274;
    pub const PNPIPE = 275;
    pub const RDS = 276;
    pub const IUCV = 277;
    pub const CAIF = 278;
    pub const ALG = 279;
    pub const NFC = 280;
    pub const KCM = 281;
    pub const TLS = 282;
    pub const XDP = 283;
};

pub const PF = struct {
    pub const UNSPEC = 0;
    pub const LOCAL = 1;
    pub const UNIX = LOCAL;
    pub const FILE = LOCAL;
    pub const INET = 2;
    pub const AX25 = 3;
    pub const IPX = 4;
    pub const APPLETALK = 5;
    pub const NETROM = 6;
    pub const BRIDGE = 7;
    pub const ATMPVC = 8;
    pub const X25 = 9;
    pub const INET6 = 10;
    pub const ROSE = 11;
    pub const DECnet = 12;
    pub const NETBEUI = 13;
    pub const SECURITY = 14;
    pub const KEY = 15;
    pub const NETLINK = 16;
    pub const ROUTE = PF.NETLINK;
    pub const PACKET = 17;
    pub const ASH = 18;
    pub const ECONET = 19;
    pub const ATMSVC = 20;
    pub const RDS = 21;
    pub const SNA = 22;
    pub const IRDA = 23;
    pub const PPPOX = 24;
    pub const WANPIPE = 25;
    pub const LLC = 26;
    pub const IB = 27;
    pub const MPLS = 28;
    pub const CAN = 29;
    pub const TIPC = 30;
    pub const BLUETOOTH = 31;
    pub const IUCV = 32;
    pub const RXRPC = 33;
    pub const ISDN = 34;
    pub const PHONET = 35;
    pub const IEEE802154 = 36;
    pub const CAIF = 37;
    pub const ALG = 38;
    pub const NFC = 39;
    pub const VSOCK = 40;
    pub const KCM = 41;
    pub const QIPCRTR = 42;
    pub const SMC = 43;
    pub const XDP = 44;
    pub const MAX = 45;
};

pub const AF = struct {
    pub const UNSPEC = PF.UNSPEC;
    pub const LOCAL = PF.LOCAL;
    pub const UNIX = AF.LOCAL;
    pub const FILE = AF.LOCAL;
    pub const INET = PF.INET;
    pub const AX25 = PF.AX25;
    pub const IPX = PF.IPX;
    pub const APPLETALK = PF.APPLETALK;
    pub const NETROM = PF.NETROM;
    pub const BRIDGE = PF.BRIDGE;
    pub const ATMPVC = PF.ATMPVC;
    pub const X25 = PF.X25;
    pub const INET6 = PF.INET6;
    pub const ROSE = PF.ROSE;
    pub const DECnet = PF.DECnet;
    pub const NETBEUI = PF.NETBEUI;
    pub const SECURITY = PF.SECURITY;
    pub const KEY = PF.KEY;
    pub const NETLINK = PF.NETLINK;
    pub const ROUTE = PF.ROUTE;
    pub const PACKET = PF.PACKET;
    pub const ASH = PF.ASH;
    pub const ECONET = PF.ECONET;
    pub const ATMSVC = PF.ATMSVC;
    pub const RDS = PF.RDS;
    pub const SNA = PF.SNA;
    pub const IRDA = PF.IRDA;
    pub const PPPOX = PF.PPPOX;
    pub const WANPIPE = PF.WANPIPE;
    pub const LLC = PF.LLC;
    pub const IB = PF.IB;
    pub const MPLS = PF.MPLS;
    pub const CAN = PF.CAN;
    pub const TIPC = PF.TIPC;
    pub const BLUETOOTH = PF.BLUETOOTH;
    pub const IUCV = PF.IUCV;
    pub const RXRPC = PF.RXRPC;
    pub const ISDN = PF.ISDN;
    pub const PHONET = PF.PHONET;
    pub const IEEE802154 = PF.IEEE802154;
    pub const CAIF = PF.CAIF;
    pub const ALG = PF.ALG;
    pub const NFC = PF.NFC;
    pub const VSOCK = PF.VSOCK;
    pub const KCM = PF.KCM;
    pub const QIPCRTR = PF.QIPCRTR;
    pub const SMC = PF.SMC;
    pub const XDP = PF.XDP;
    pub const MAX = PF.MAX;
};

pub const sa_family_t = u16;
pub const socklen_t = u32;

pub const sockaddr = extern struct {
    family: sa_family_t,
    data: [14]u8,

    pub const SS_MAXSIZE = 128;
    pub const storage = extern struct {
        family: sa_family_t align(8),
        padding: [SS_MAXSIZE - @sizeOf(sa_family_t)]u8 = undefined,

        comptime {
            assert(@sizeOf(storage) == SS_MAXSIZE);
            assert(@alignOf(storage) == 8);
        }
    };

    /// UNIX domain socket address
    pub const un = extern struct {
        family: sa_family_t = AF.UNIX,
        path: [108]u8,
    };
};

pub const msghdr = extern struct {
    name: ?*sockaddr,
    namelen: socklen_t,
    iov: [*]iovec,
    /// The kernel and glibc use `usize` for this field; POSIX and musl use `c_int`.
    iovlen: usize,
    control: ?*anyopaque,
    /// The kernel and glibc use `usize` for this field; POSIX and musl use `socklen_t`.
    controllen: usize,
    flags: u32,
};

pub const cmsghdr = extern struct {
    /// The kernel and glibc use `usize` for this field; musl uses `socklen_t`.
    len: usize,
    level: i32,
    type: i32,
};

pub const MSG = struct {
    pub const OOB = 0x0001;
    pub const PEEK = 0x0002;
    pub const DONTROUTE = 0x0004;
    pub const CTRUNC = 0x0008;
    pub const PROXY = 0x0010;
    pub const TRUNC = 0x0020;
    pub const DONTWAIT = 0x0040;
    pub const EOR = 0x0080;
    pub const WAITALL = 0x0100;
    pub const FIN = 0x0200;
    pub const SYN = 0x0400;
    pub const CONFIRM = 0x0800;
    pub const RST = 0x1000;
    pub const ERRQUEUE = 0x2000;
    pub const NOSIGNAL = 0x4000;
    pub const MORE = 0x8000;
    pub const WAITFORONE = 0x10000;
    pub const BATCH = 0x40000;
    pub const ZEROCOPY = 0x4000000;
    pub const FASTOPEN = 0x20000000;
    pub const CMSG_CLOEXEC = 0x40000000;
};

pub const SCM = struct {
    // https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/linux/socket.h?id=f777d1112ee597d7f7dd3ca232220873a34ad0c8#n178
    pub const RIGHTS = 1;
    pub const CREDENTIALS = 2;
    pub const SECURITY = 3;
    pub const PIDFD = 4;

    pub const WIFI_STATUS = SO.WIFI_STATUS;
    pub const TIMESTAMPING_OPT_STATS = 54;
    pub const TIMESTAMPING_PKTINFO = 58;
    pub const TXTIME = SO.TXTIME;
};

pub fn socket(domain: c_int, @"type": c_uint, protocol: c_uint) Error!fd_t {
    const rc = syscall3(.socket, @as(u32, @bitCast(domain)), @"type", protocol);
    if (check_errno(rc)) |e| return switch (e) {
        .ACCES => error.PermissionDenied,
        .AFNOSUPPORT => error.InvalidAddressFamily,
        .INVAL => error.InvalidArg,
        .MFILE => error.TooManyProcessFiles,
        .NFILE => error.TooManyFiles,
        .NOBUFS, .NOMEM => error.NoMemory,
        .PROTONOSUPPORT => error.InvalidProtocol,
        else => blk: {
            log.warn("Unexpected errno for socket: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };

    return @intCast(rc);
}

pub fn connect(sock_fd: fd_t, addr: *const sockaddr, addrlen: socklen_t) Error!c_int {
    const rc = syscall3(.connect, @as(u32, @bitCast(sock_fd)), @intFromPtr(addr), addrlen);
    if (check_errno(rc)) |e| return switch (e) {
        .PERM, .ACCES => error.PermissionDenied,
        .ADDRNOTAVAIL => error.AddressNotAvailable,
        .AFNOSUPPORT => error.InvalidAddressFamily,
        .ALREADY => error.AlreadyConnecting,
        .BADF => error.InvalidFD,
        .CONNREFUSED => error.ConnectionRefused,
        .FAULT => error.InvalidPointer,
        .INPROGRESS => error.ConnectingInProgress,
        .INTR => error.Interrupt,
        .INVAL => error.InvalidArg,
        .NOTSOCK => error.NotSocket,
        .TIMEDOUT => error.Timeout,
        .NETUNREACH => error.NetworkUnreachable,
        .HOSTUNREACH => error.HostUnreachable,
        else => blk: {
            log.warn("Unexpected errno for connect: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
    assert(rc == 0);
    return @intCast(rc);
}

pub fn sendmsg(sock_fd: fd_t, header: *msghdr, flags: c_uint) Error!usize {
    const rc = syscall3(.sendmsg, @as(u32, @bitCast(sock_fd)), @intFromPtr(header), flags);
    if (check_errno(rc)) |e| return switch (e) {
        .BADF => error.InvalidFD,
        .AGAIN => error.NoSpaceLeft, // send buffer full
        .INTR => error.Interrupt,
        .PIPE => error.ConnectionClosed, // peer closed connection
        .CONNRESET => error.ConnectionReset,
        .MSGSIZE => error.MessageTooBig,
        .INVAL => error.InvalidArg,
        .NOMEM => error.NoMemory,
        else => blk: {
            log.warn("Unexpected errno for sendmsg: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
    return @intCast(rc);
}

pub fn recvmsg(sock_fd: fd_t, header: *msghdr, flags: c_uint) Error!usize {
    const rc = syscall3(.recvmsg, @as(u32, @bitCast(sock_fd)), @intFromPtr(header), flags);
    if (check_errno(rc)) |e| return switch (e) {
        .BADF => error.InvalidFD,
        .AGAIN, .TIMEDOUT => error.Timeout,
        .FAULT => error.InvalidPointer,
        .INTR => error.Interrupt,
        .NOTCONN => error.NotConnected,
        .NOTSOCK => error.InvalidFD,
        .OPNOTSUPP => error.InvalidFlags,
        .INVAL => error.InvalidArg,
        .NOMEM => error.NoMemory,
        else => blk: {
            log.warn("Unexpected errno for recvmsg: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
    return @intCast(rc);
}

pub inline fn CMSG_NXTHDR(msg: *msghdr, cmsg: *cmsghdr) ?*cmsghdr {
    assert(cmsg.len >= @sizeOf(cmsghdr));
    const next = @as([*]u8, @ptrCast(cmsg)) + CMSG_ALIGN(cmsg.len);
    const end = @as([*]u8, @ptrCast(msg.control)) + msg.controllen;

    if (end - next < @sizeOf(cmsghdr)) {
        return null;
    }

    return @ptrCast(@alignCast(next));
}

pub inline fn CMSG_FIRSTHDR(msg: *msghdr) ?*cmsghdr {
    return if (msg.controllen >= @sizeOf(cmsghdr)) @ptrCast(@alignCast(msg.control)) else null;
}

pub inline fn CMSG_SPACE(len: usize) usize {
    return CMSG_ALIGN(len) + CMSG_ALIGN(@sizeOf(cmsghdr));
}

pub inline fn CMSG_ALIGN(len: usize) usize {
    const algn: usize = @alignOf(cmsghdr);
    return (len + algn - 1) & ~(algn - 1);
}

pub inline fn CMSG_LEN(len: usize) usize {
    return @sizeOf(cmsghdr) + len;
}

pub inline fn CMSG_DATA(msg: *cmsghdr) []u8 {
    const offset = CMSG_ALIGN(@sizeOf(cmsghdr));
    return (@as([*]u8, @ptrCast(msg)) + offset)[0 .. msg.len - offset];
}

// =============================================================================
// stat.h
// =============================================================================

pub const S = struct {
    pub const IFMT = 0o170000;

    pub const IFDIR = 0o040000;
    pub const IFCHR = 0o020000;
    pub const IFBLK = 0o060000;
    pub const IFREG = 0o100000;
    pub const IFIFO = 0o010000;
    pub const IFLNK = 0o120000;
    pub const IFSOCK = 0o140000;

    pub const ISUID = 0o4000;
    pub const ISGID = 0o2000;
    pub const ISVTX = 0o1000;
    pub const IRUSR = 0o400;
    pub const IWUSR = 0o200;
    pub const IXUSR = 0o100;
    pub const IRWXU = 0o700;
    pub const IRGRP = 0o040;
    pub const IWGRP = 0o020;
    pub const IXGRP = 0o010;
    pub const IRWXG = 0o070;
    pub const IROTH = 0o004;
    pub const IWOTH = 0o002;
    pub const IXOTH = 0o001;
    pub const IRWXO = 0o007;

    pub fn ISREG(m: mode_t) bool {
        return m & IFMT == IFREG;
    }

    pub fn ISDIR(m: mode_t) bool {
        return m & IFMT == IFDIR;
    }

    pub fn ISCHR(m: mode_t) bool {
        return m & IFMT == IFCHR;
    }

    pub fn ISBLK(m: mode_t) bool {
        return m & IFMT == IFBLK;
    }

    pub fn ISFIFO(m: mode_t) bool {
        return m & IFMT == IFIFO;
    }

    pub fn ISLNK(m: mode_t) bool {
        return m & IFMT == IFLNK;
    }

    pub fn ISSOCK(m: mode_t) bool {
        return m & IFMT == IFSOCK;
    }
};

pub const Stat = abi.Stat;
pub const mode_t = u32;

pub fn stat(pathname: [:0]const u8, statbuf: *Stat) Error!void {
    const rc = syscall2(.stat, @intFromPtr(pathname.ptr), @intFromPtr(statbuf));
    if (check_errno(rc)) |e| return switch (e) {
        .ACCES => error.PermissionDenied,
        .BADF => error.InvalidFD,
        .FAULT => error.InvalidPointer,
        .INVAL => error.InvalidArg,
        .LOOP => error.TooManySymbolicLinks,
        .NAMETOOLONG => error.NameTooLong,
        .NOENT => error.FileDoesNotExist,
        .NOMEM => error.NoMemory,
        .NOTDIR => error.InvalidPath,
        .OVERFLOW => error.Overflow,
        else => blk: {
            log.warn("Unexpected errno for stat: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
}

pub fn fstatat(dir_fd: dirfd_t, path: [:0]const u8, statbuf: *Stat, flags: c_int) Error!void {
    const rc = syscall4(
        .fstatat64,
        zeroExtendToUsize(dir_fd),
        @intFromPtr(path.ptr),
        @intFromPtr(statbuf),
        zeroExtendToUsize(flags),
    );
    if (check_errno(rc)) |e| return switch (e) {
        .ACCES => error.PermissionDenied,
        .BADF => error.InvalidFD,
        .FAULT => error.InvalidPointer,
        .INVAL => error.InvalidArg,
        .LOOP => error.TooManySymbolicLinks,
        .NAMETOOLONG => error.NameTooLong,
        .NOENT => error.FileDoesNotExist,
        .NOMEM => error.NoMemory,
        .NOTDIR => error.InvalidPath,
        .OVERFLOW => error.Overflow,
        else => blk: {
            log.warn("Unexpected errno for stat: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
}

// =============================================================================
// time.h
// =============================================================================

pub const timespec = extern struct {
    sec: isize,
    nsec: isize,

    pub const NOW: timespec = .{
        .sec = 0,
        .nsec = 0x3fffffff,
    };

    pub const OMIT: timespec = .{
        .sec = 0,
        .nsec = 0x3ffffffe,
    };
};

pub const timeval = extern struct {
    sec: isize,
    usec: i64,
};

pub const CLOCK = enum(c_int) {
    REALTIME = 0,
    MONOTONIC = 1,
    PROCESS_CPUTIME_ID = 2,
    THREAD_CPUTIME_ID = 3,
    MONOTONIC_RAW = 4,
    REALTIME_COARSE = 5,
    MONOTONIC_COARSE = 6,
    BOOTTIME = 7,
    REALTIME_ALARM = 8,
    BOOTTIME_ALARM = 9,

    // The driver implementing this got removed. The clock ID is kept as a
    // place holder. Do not reuse!
    CLOCK_SGI_CYCLE = 10,
    CLOCK_TAI = 11,

    pub const MAX_CLOCKS = 16;

    // AUX clock support. AUXiliary clocks are dynamically configured by
    // enabling a clock ID. These clock can be steered independently of the
    // core timekeeper. The kernel can support up to 8 auxiliary clocks, but
    // the actual limit depends on eventual architecture constraints vs. VDSO.
    pub const CLOCK_AUX = MAX_CLOCKS;
    pub const MAX_AUX_CLOCKS = 8;
    pub const CLOCK_AUX_LAST = (CLOCK_AUX + MAX_AUX_CLOCKS - 1);

    pub const CLOCKS_MASK: c_int = (@intFromEnum(CLOCK.REALTIME) | @intFromEnum(CLOCK.MONOTONIC));
    pub const CLOCKS_MONO: c_int = @intFromEnum(CLOCK.MONOTONIC);
};

// =============================================================================
// uio.h
// =============================================================================

pub const iovec = extern struct {
    base: [*]u8,
    len: usize,
};

// =============================================================================
// unistd.h
// =============================================================================

pub const SYS = abi.SYS;
pub const fd_t = c_int;
pub const dirfd_t = c_int;
pub const off_t = isize;

pub inline fn check_errno(err: isize) ?Errno {
    if (err < 0) {
        return @enumFromInt(-err);
    }
    return null;
}

pub fn read(fd: fd_t, buf: []u8) Error![]u8 {
    const rc = syscall3(.read, @as(u32, @bitCast(fd)), @intFromPtr(buf.ptr), buf.len);
    if (check_errno(rc)) |e| return switch (e) {
        .INTR => error.Interrupt,
        .AGAIN => error.NoData,
        .BADF => error.InvalidFD,
        .FAULT => error.InvalidPointer,
        .INVAL => error.InvalidArg,
        .IO => error.IO,
        .ISDIR => error.UnexpectedDirFD,
        else => blk: {
            log.warn("Unexpected errno for read: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };

    if (rc == 0) {
        return error.EndOfFile;
    } else {
        return buf[0..@intCast(rc)];
    }
}

pub fn write(fd: fd_t, buf: []const u8) Error!usize {
    const rc = syscall3(.write, @as(u32, @bitCast(fd)), @intFromPtr(buf.ptr), buf.len);
    if (check_errno(rc)) |e| return switch (e) {
        .INTR => error.Interrupt,
        .AGAIN => error.NoData,
        .BADF => error.InvalidFD,
        .FAULT => error.InvalidPointer,
        .INVAL => error.InvalidArg,
        .IO => error.IO,
        .NOSPC => error.NoSpaceLeft,
        .DQUOT => error.DiskQuotaExceeded,
        else => blk: {
            log.warn("Unexpected errno for write: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };

    return @intCast(rc);
}

pub fn close(fd: fd_t) Error!void {
    const rc = syscall1(.close, @as(u32, @bitCast(fd)));
    if (check_errno(rc)) |e| return switch (e) {
        .BADF => error.InvalidFD,
        .INTR => error.Interrupt,
        .IO => error.IO,
        else => blk: {
            log.warn("Unexpected errno for close: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
}

pub fn pipe(fds: *[2]fd_t) Error!void {
    const rc = syscall1(.pipe, @intFromPtr(fds));
    if (check_errno(rc)) |e| return switch (e) {
        .FAULT => error.InvalidPointer,
        .MFILE => error.TooManyProcessFiles,
        .NFILE => error.TooManyFiles,
        else => blk: {
            log.warn("Unexpected errno for pipe: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
}

pub fn pipe2(fds: *[2]fd_t, flags: O) Error!void {
    const rc = syscall2(.pipe2, @intFromPtr(fds), @as(u32, @bitCast(flags)));
    if (check_errno(rc)) |e| return switch (e) {
        .FAULT => error.InvalidPointer,
        .MFILE => error.TooManyProcessFiles,
        .NFILE => error.TooManyFiles,
        .INVAL => error.InvalidArg,
        .NOPKG => error.PackageNotCompiled,
        else => blk: {
            log.warn("Unexpected errno for pipe: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
}

pub fn ftruncate(fd: fd_t, length: usize) !void {
    const rc = syscall2(.ftruncate, @as(u32, @bitCast(fd)), length);
    if (check_errno(rc)) |e| return switch (e) {
        .BADF => error.InvalidFD,
        .INVAL => error.InvalidArg,
        else => blk: {
            log.warn("Unexpected errno for ftruncate: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
}

pub fn unlink(pathname: [:0]const u8) Error!void {
    const rc = syscall1(.unlink, @intFromPtr(pathname.ptr));
    if (check_errno(rc)) |e| return switch (e) {
        .ACCES => error.PermissionDenied,
        .PERM => error.UnlinkDirectoryAttempt,
        .NOENT => error.FileDoesNotExist,
        .BUSY => error.FileBusy,
        .ROFS => error.ReadOnly,
        .NOTDIR => error.InvalidPath,
        .NAMETOOLONG => error.NameTooLong,
        .LOOP => error.TooManySymbolicLinks,
        .IO => error.IO,
        else => blk: {
            log.warn("Unexpected errno for unlink: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
}

// =============================================================================
// xattr.h
// =============================================================================

pub const XATTR = struct {
    pub const CREATE = 0x1;
    pub const REPLACE = 0x2;

    pub const OS2_PREFIX = "os2.";
    pub const MAC_OSX_PREFIX = "osx.";
    pub const BTRFS_PREFIX = "btrfs.";
    pub const HURD_PREFIX = "gnu.";
    pub const SECURITY_PREFIX = "security.";
    pub const SYSTEM_PREFIX = "system.";
    pub const TRUSTED_PREFIX = "trusted.";
    pub const USER_PREFIX = "user.";

    pub const EVM_SUFFIX = "evm";
    pub const NAME_EVM = SECURITY_PREFIX ++ EVM_SUFFIX;

    pub const IMA_SUFFIX = "ima";
    pub const NAME_IMA = SECURITY_PREFIX ++ IMA_SUFFIX;

    pub const SELINUX_SUFFIX = "selinux";
    pub const NAME_SELINUX = SECURITY_PREFIX ++ SELINUX_SUFFIX;

    pub const SMACK_SUFFIX = "SMACK64";
    pub const NAME_SMACK = SECURITY_PREFIX ++ SMACK_SUFFIX;
    pub const SMACK_IPIN = "SMACK64IPIN";
    pub const NAME_SMACKIPIN = SECURITY_PREFIX ++ SMACK_IPIN;
    pub const SMACK_IPOUT = "SMACK64IPOUT";
    pub const NAME_SMACKIPOUT = SECURITY_PREFIX ++ SMACK_IPOUT;
    pub const SMACK_EXEC = "SMACK64EXEC";
    pub const NAME_SMACKEXEC = SECURITY_PREFIX ++ SMACK_EXEC;
    pub const SMACK_TRANSMUTE = "SMACK64TRANSMUTE";
    pub const NAME_SMACKTRANSMUTE = SECURITY_PREFIX ++ SMACK_TRANSMUTE;
    pub const SMACK_MMAP = "SMACK64MMAP";
    pub const NAME_SMACKMMAP = SECURITY_PREFIX ++ SMACK_MMAP;

    pub const APPARMOR_SUFFIX = "apparmor";
    pub const NAME_APPARMOR = SECURITY_PREFIX ++ APPARMOR_SUFFIX;

    pub const CAPS_SUFFIX = "capability";
    pub const NAME_CAPS = SECURITY_PREFIX ++ CAPS_SUFFIX;

    pub const BPF_LSM_SUFFIX = "bpf.";
    pub const NAME_BPF_LSM = SECURITY_PREFIX ++ BPF_LSM_SUFFIX;

    pub const POSIX_ACL_ACCESS = "posix_acl_access";
    pub const NAME_POSIX_ACL_ACCESS = SYSTEM_PREFIX ++ POSIX_ACL_ACCESS;
    pub const POSIX_ACL_DEFAULT = "posix_acl_default";
    pub const NAME_POSIX_ACL_DEFAULT = SYSTEM_PREFIX ++ POSIX_ACL_DEFAULT;
};

pub fn getxattr(path: [:0]const u8, name: [:0]const u8, value_buf: []u8) Error!usize {
    const rc = syscall4(
        .getxattr,
        @intFromPtr(path.ptr),
        @intFromPtr(name.ptr),
        if (value_buf.len > 0) @intFromPtr(value_buf.ptr) else 0,
        value_buf.len,
    );
    if (check_errno(rc)) |e| return switch (e) {
        .@"2BIG" => error.ValueTooBig,
        .NODATA => error.NoData,
        .NOTSUP => error.NotSupported,
        .RANGE => error.BufferTooSmall,
        else => blk: {
            log.warn("Unexpected errno for getxattr: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };

    return safeExtendToUsize(rc);
}

// =============================================================================
// private helpers
// =============================================================================

fn safeExtendToUsize(x: anytype) usize {
    comptime {
        const T = @TypeOf(x);
        meta.expectSignedType(T);
        assert(@sizeOf(T) <= @sizeOf(usize));
    }
    return @intCast(x);
}

inline fn zeroExtendToUsize(x: anytype) usize {
    const T = @TypeOf(x);
    const Int = blk: switch (@typeInfo(T)) {
        .int => {
            meta.expectSignedType(T);
            break :blk T;
        },

        .@"struct" => |si| {
            if (si.layout == .@"packed") {
                break :blk si.backing_integer.?;
            } else @compileError("Expected signed integer or packed struct");
        },
        else => @compileError("Expected signed integer or packed struct"),
    };

    comptime {
        assert(@sizeOf(Int) <= @sizeOf(usize));
    }

    const UnSigned = @Int(.unsigned, @bitSizeOf(Int));
    return @intCast(@as(UnSigned, @bitCast(x)));
}

inline fn safeTrunc(comptime T: type, x: anytype) T {
    comptime {
        meta.expectIntType(T);
        const XT = @TypeOf(x);
        meta.expectIntType(XT);
    }
    return @intCast(x);
}

// =============================================================================
// tests
// =============================================================================

test dirnameN {
    try testDirnameN("/a/b/c", "/a/b", 1);
    try testDirnameN("/a/b/c///", "/a/b", 1);
    try testDirnameN("a/b", "a", 1);
    try testDirnameN("a/b/c", "a/b", 1);
    try testDirnameN("a/b/c///", "a/b", 1);
    try testDirnameN("/a", "/", 1);
    try testDirnameN("/", null, 1);
    try testDirnameN("//", null, 1);
    try testDirnameN("///", null, 1);
    try testDirnameN("////", null, 1);
    try testDirnameN("", null, 1);
    try testDirnameN("a", null, 1);
    try testDirnameN("a/", null, 1);
    try testDirnameN("a//", null, 1);

    try testDirnameN("/a/b/c", "/a", 2);
    try testDirnameN("/a/b/c///", "/a", 2);
    try testDirnameN("a/b/c", "a", 2);
    try testDirnameN("a/b", null, 2);
    try testDirnameN("a/b/c///", "a", 2);
    try testDirnameN("/a", null, 2);
    try testDirnameN("/", null, 2);
    try testDirnameN("//", null, 2);
    try testDirnameN("///", null, 2);
    try testDirnameN("////", null, 2);
    try testDirnameN("", null, 2);
    try testDirnameN("a", null, 2);
    try testDirnameN("a/", null, 2);
    try testDirnameN("a//", null, 2);

    try testDirnameN("a/b/c", null, 3);
    try testDirnameN("a/b/c///", null, 3);
    try testDirnameN("a/b", null, 3);

    try testDirnameN("a//b", "a", 1);
    try testDirnameN("a///b", "a", 1);
    try testDirnameN("a//b//c", "a//b", 1);
    try testDirnameN("a//b//c", "a", 2);
    try testDirnameN("a//b//c", null, 3);

    try testDirnameN("/a//b", "/a", 1);
    try testDirnameN("/a///b", "/a", 1);
    try testDirnameN("/a//b//c", "/a//b", 1);
    try testDirnameN("/a//b//c", "/a", 2);
    try testDirnameN("/a//b//c", "/", 3);
    try testDirnameN("/a//b//c", null, 4);

    try testDirnameN("///a/b", "///a", 1);
    try testDirnameN("///a/b", "/", 2);
    try testDirnameN("///a/b", null, 3);

    try testDirnameN("a//b///c////d", "a//b///c", 1);
    try testDirnameN("a//b///c////d", "a//b", 2);
    try testDirnameN("a//b///c////d", "a", 3);
    try testDirnameN("a//b///c////d", null, 4);
}

fn testDirnameN(input: []const u8, expected_output_opt: ?[]const u8, n: usize) !void {
    var std_result_opt: ?[]const u8 = input;
    for (0..n) |_| {
        std_result_opt = if (std_result_opt) |std_result| std.fs.path.dirnamePosix(std_result) else null;
    }

    const output_opt = dirnameN(input, n);

    try std.testing.expectEqualDeep(expected_output_opt, std_result_opt);
    try std.testing.expectEqualDeep(expected_output_opt, output_opt);
    try std.testing.expectEqualDeep(std_result_opt, output_opt);
}
