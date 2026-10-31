const linux = @import("../linux.zig");

const assert = @import("../../../debug.zig").assert;

// =============================================================================
// fcntl.h
// =============================================================================

const ACCMODE = linux.ACCMODE;

pub const O = packed struct(c_int) {
    ACCMODE: ACCMODE = .RDONLY,
    _2: u4 = 0,
    CREAT: bool = false,
    EXCL: bool = false,
    NOCTTY: bool = false,
    TRUNC: bool = false,
    APPEND: bool = false,
    NONBLOCK: bool = false,
    DSYNC: bool = false,
    ASYNC: bool = false,
    DIRECT: bool = false,
    _15: u1 = 0,
    DIRECTORY: bool = false,
    NOFOLLOW: bool = false,
    NOATIME: bool = false,
    CLOEXEC: bool = false,
    SYNC: bool = false,
    PATH: bool = false,
    TMPFILE: bool = false,
    _23: u9 = 0,
};

// =============================================================================
// ioctls.h
// =============================================================================

pub const IOC = struct {
    pub const SIZE = 14;
    pub const DIR = 2;
    pub const NONE = 0;
    pub const READ = 2;
    pub const WRITE = 1;
};

// =============================================================================
// mman-common.h
// =============================================================================

const MAP_TYPE = linux.MAP_TYPE;

pub const MAP = packed struct(u32) {
    TYPE: MAP_TYPE,
    FIXED: bool = false,
    ANONYMOUS: bool = false,
    @"32BIT": bool = false,
    _7: u1 = 0,
    GROWSDOWN: bool = false,
    _9: u2 = 0,
    DENYWRITE: bool = false,
    EXECUTABLE: bool = false,
    LOCKED: bool = false,
    NORESERVE: bool = false,
    POPULATE: bool = false,
    NONBLOCK: bool = false,
    STACK: bool = false,
    HUGETLB: bool = false,
    SYNC: bool = false,
    FIXED_NOREPLACE: bool = false,
    _21: u5 = 0,
    UNINITIALIZED: bool = false,
    _: u5 = 0,
};

pub const PROT = packed struct(u32) {
    READ: bool = false,
    WRITE: bool = false,
    EXEC: bool = false,
    SEM: bool = false,
    __: u20 = 0,
    GROWSDOWN: bool = false,
    GROWSUP: bool = false,
    ___: u6 = 0,
};

// =============================================================================
// poll.h
// =============================================================================

pub const POLL = packed struct(u16) {
    IN: bool = false,
    PRI: bool = false,
    OUT: bool = false,
    ERR: bool = false,
    HUP: bool = false,
    NVAL: bool = false,
    RDNORM: bool = false,
    RDBAND: bool = false,
    WRNORM: bool = false,
    WRBAND: bool = false,
    MSG: bool = false,
    __reserved__: u1 = 0,
    REMOVE: bool = false,
    RDHUP: bool = false,
    __reserved2__: u2 = 0,
};

// =============================================================================
// signal.h
// =============================================================================

const _NSIG = 64;
const _NSIG_BPW = @bitSizeOf(c_long);
const _NSIG_WORDS = (_NSIG / _NSIG_BPW);

// Generig NSIG=64, MIPS=128
pub const sigset_t = extern struct {
    sig: [_NSIG_WORDS]c_ulong,
};

// =============================================================================
// socket.h
// =============================================================================

pub const SO = struct {
    pub const DEBUG = 1;
    pub const REUSEADDR = 2;
    pub const TYPE = 3;
    pub const ERROR = 4;
    pub const DONTROUTE = 5;
    pub const BROADCAST = 6;
    pub const SNDBUF = 7;
    pub const RCVBUF = 8;
    pub const KEEPALIVE = 9;
    pub const OOBINLINE = 10;
    pub const NO_CHECK = 11;
    pub const PRIORITY = 12;
    pub const LINGER = 13;
    pub const BSDCOMPAT = 14;
    pub const REUSEPORT = 15;
    pub const PASSCRED = 16;
    pub const PEERCRED = 17;
    pub const RCVLOWAT = 18;
    pub const SNDLOWAT = 19;
    pub const RCVTIMEO = 20;
    pub const SNDTIMEO = 21;
    pub const ACCEPTCONN = 30;
    pub const PEERSEC = 31;
    pub const SNDBUFFORCE = 32;
    pub const RCVBUFFORCE = 33;
    pub const PROTOCOL = 38;
    pub const DOMAIN = 39;
    pub const SECURITY_AUTHENTICATION = 22;
    pub const SECURITY_ENCRYPTION_TRANSPORT = 23;
    pub const SECURITY_ENCRYPTION_NETWORK = 24;
    pub const BINDTODEVICE = 25;
    pub const ATTACH_FILTER = 26;
    pub const DETACH_FILTER = 27;
    pub const GET_FILTER = ATTACH_FILTER;
    pub const PEERNAME = 28;
    pub const TIMESTAMP_OLD = 29;
    pub const PASSSEC = 34;
    pub const TIMESTAMPNS_OLD = 35;
    pub const MARK = 36;
    pub const TIMESTAMPING_OLD = 37;
    pub const RXQ_OVFL = 40;
    pub const WIFI_STATUS = 41;
    pub const PEEK_OFF = 42;
    pub const NOFCS = 43;
    pub const LOCK_FILTER = 44;
    pub const SELECT_ERR_QUEUE = 45;
    pub const BUSY_POLL = 46;
    pub const MAX_PACING_RATE = 47;
    pub const BPF_EXTENSIONS = 48;
    pub const INCOMING_CPU = 49;
    pub const ATTACH_BPF = 50;
    pub const DETACH_BPF = DETACH_FILTER;
    pub const ATTACH_REUSEPORT_CBPF = 51;
    pub const ATTACH_REUSEPORT_EBPF = 52;
    pub const CNX_ADVICE = 53;
    pub const MEMINFO = 55;
    pub const INCOMING_NAPI_ID = 56;
    pub const COOKIE = 57;
    pub const PEERGROUPS = 59;
    pub const ZEROCOPY = 60;
    pub const TXTIME = 61;
    pub const BINDTOIFINDEX = 62;
    pub const TIMESTAMP_NEW = 63;
    pub const TIMESTAMPNS_NEW = 64;
    pub const TIMESTAMPING_NEW = 65;
    pub const RCVTIMEO_NEW = 66;
    pub const SNDTIMEO_NEW = 67;
    pub const DETACH_REUSEPORT_BPF = 68;
};

// =============================================================================
// stat.h
// =============================================================================
pub const Statx = extern struct {
    mask: Mask,

    blksize: u32,
    attributes: u64,
    nlink: u32,
    uid: u32,
    gid: u32,
    mode: u16,
    __spare0: u16,
    ino: u64,
    size: u64,
    blocks: u64,
    attributes_mask: u64,

    atime: Timestamp,
    btime: Timestamp,
    ctime: Timestamp,
    mtime: Timestamp,

    rdev_major: u32,
    rdev_minor: u32,

    dev_major: u32,
    dev_minor: u32,

    mnt_id: u64,

    dio_mem_align: u32,
    dio_offset_align: u32,

    subvol: u64,

    atomic_write_unit_min: u32,
    atomic_write_unit_max: u32,
    atomic_write_segments_max: u32,

    dio_read_offset_align: u32,

    atomic_write_unit_max_opt: u32,
    __spare2: u32,

    __spare3: [8]u64,

    pub const Mask = packed struct(u32) {
        TYPE: bool = false,
        MODE: bool = false,
        NLINK: bool = false,
        UID: bool = false,
        GID: bool = false,
        ATIME: bool = false,
        MTIME: bool = false,
        CTIME: bool = false,
        INO: bool = false,
        SIZE: bool = false,
        BLOCKS: bool = false,
        BTIME: bool = false,
        MNT_ID: bool = false,
        DIOALIGN: bool = false,
        MNT_ID_UNIQUE: bool = false,
        SUBVOL: bool = false,
        WRITE_ATOMIC: bool = false,
        DIO_READ_ALIGN: bool = false,

        __reserved__: u14 = 0,

        pub const BASIC_STATS: Mask = .{
            .TYPE = true,
            .MODE = true,
            .NLINK = true,
            .UID = true,
            .GID = true,
            .ATIME = true,
            .MTIME = true,
            .CTIME = true,
            .INO = true,
            .SIZE = true,
            .BLOCKS = true,
        };
    };

    pub const Timestamp = extern struct {
        sec: i64,
        nsec: u32,
        __reserved__: i32,
    };

    comptime {
        assert(@sizeOf(@This()) == 0x100);
    }
};
