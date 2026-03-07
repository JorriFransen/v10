const std = @import("std");
const log = std.log.scoped(.linux);
const arch = @import("arch").arch;

pub const abi = @import("abi.zig").abi;
pub const input = @import("input.zig");
pub const ioctl = @import("ioctl.zig");

pub const pulse = @import("pulse.zig");
pub const libudev = @import("libudev.zig");

pub const fd_t = c_int;
pub const off_t = isize;
pub const mode_t = u32;

pub const page_size = std.heap.page_size_min;

pub const O = abi.O;
pub const PROT = abi.PROT;
pub const MAP = abi.MAP;

pub const Error = error{
    DiskQuotaExceeded,
    EndOfFile,
    FileBusy,
    FileDoesNotExist,
    FileExists,
    Interrupt,
    InvalidArg,
    InvalidDevice,
    InvalidFD,
    InvalidPath,
    InvalidPointer,
    IO,
    IsDirectory,
    Lock,
    NameTooLong,
    NoData,
    NoMemory,
    NoSpaceLeft,
    PermissionDenied,
    ReadOnly,
    TooManyFiles,
    TooManyProcessFiles,
    TooManySymbolicLinks,
    UnexpectedDirFD,
    UnlinkDirectoryAttempt,

    UnexpectedErrno,
};

pub inline fn check_errno(err: isize) ?Errno {
    if (err < 0) {
        return @enumFromInt(-err);
    }
    return null;
}

pub fn read(fd: fd_t, buf: []u8) Error![]u8 {
    const rc = abi.syscall3(.read, @as(u32, @bitCast(fd)), @intFromPtr(buf.ptr), buf.len);
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
    const rc = abi.syscall3(.write, @as(u32, @bitCast(fd)), @intFromPtr(buf.ptr), buf.len);
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

pub fn open(path: [*:0]const u8, flags: O, mode: mode_t) Error!fd_t {
    const rc = abi.syscall3(.open, @intFromPtr(path), @as(u32, @bitCast(flags)), mode);
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

    return @as(fd_t, @truncate(rc));
}

pub fn close(fd: fd_t) Error!void {
    const rc = abi.syscall1(.close, @as(u32, @bitCast(fd)));
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

pub fn poll(fds: []pollfd, timeout: c_int) Error!c_int {
    const rc = abi.syscall3(.poll, @intFromPtr(fds.ptr), fds.len, @as(u32, @bitCast(timeout)));
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

pub fn mmap(addr: ?[*]align(page_size) u8, length: usize, prot: PROT, flags: MAP, fd: fd_t, offset: off_t) Error![]align(page_size) u8 {
    const rc = abi.syscall6(
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

pub fn mprotect(addr: [*]align(page_size) u8, size: usize, prot: PROT) Error!void {
    const rc = abi.syscall3(.mprotect, @intFromPtr(addr), size, @as(u32, @bitCast(prot)));
    if (check_errno(rc)) |e| return switch (e) {
        .INVAL => error.InvalidArg,
        else => blk: {
            log.warn("Unexpected errno for mprotect: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
}

pub fn munmap(memory: []align(page_size) const u8) Error!void {
    const rc = abi.syscall2(.munmap, @intFromPtr(memory.ptr), memory.len);
    if (check_errno(rc)) |e| return switch (e) {
        .INVAL => error.InvalidArg,
        else => blk: {
            log.warn("Unexpected errno for munmap: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
}

pub fn ftruncate(fd: fd_t, length: usize) !void {
    const rc = abi.syscall2(.ftruncate, @as(u32, @bitCast(fd)), length);
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
    const rc = abi.syscall1(.unlink, @intFromPtr(pathname.ptr));
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

pub fn openat(dir_fd: fd_t, filename: [*:0]const u8, flags: O, mode: mode_t) Error!fd_t {
    const rc = abi.syscall4(.openat, @as(u32, @bitCast(dir_fd)), @intFromPtr(filename), @as(u32, @bitCast(flags)), mode);
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
    return @as(fd_t, @truncate(@as(isize, @intCast(rc))));
}

pub fn stat(pathname: [:0]const u8, statbuf: *Stat) Error!void {
    const rc = abi.syscall4(.fstatat64, @bitCast(@as(isize, AT.FDCWD)), @intFromPtr(pathname.ptr), @intFromPtr(statbuf), 0);
    if (check_errno(rc)) |e| return switch (e) {
        .BADF => error.InvalidFD,
        .FAULT => error.InvalidPointer,
        .ACCES => error.PermissionDenied,
        .NOENT => error.FileDoesNotExist,
        .NOTDIR => error.InvalidPath,
        .LOOP => error.TooManySymbolicLinks,
        .NAMETOOLONG => error.NameTooLong,
        .NODEV => error.InvalidDevice,
        .ROFS => error.ReadOnly,
        .IO => error.IO,
        else => blk: {
            log.warn("Unexpected errno for stat: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
}

inline fn getShmPath(name: [:0]const u8) std.fmt.BufPrintError![:0]const u8 {
    var name_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_fmt = std.fs.path.fmtJoin(&.{ "/dev/shm/", name });
    return try std.fmt.bufPrintSentinel(&name_buf, "{f}", .{path_fmt}, 0);
}

pub const ShmError = Error || std.fmt.BufPrintError;
pub fn shm_open(name: [:0]const u8, oflag: O, mode: mode_t) ShmError!c_int {
    const path = try getShmPath(name);
    log.debug("shm_open name: {s}", .{path});

    const fd = try openat(AT.FDCWD, path, oflag, mode);
    return fd;
}

pub fn shm_unlink(name: [:0]const u8) ShmError!void {
    const path = try getShmPath(name);
    try unlink(path);
}

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

pub const POLL = struct {
    pub const IN = 0x001;
    pub const PRI = 0x002;
    pub const OUT = 0x004;
    pub const ERR = 0x008;
    pub const HUP = 0x010;
    pub const NVAL = 0x020;
    pub const RDNORM = 0x040;
    pub const RDBAND = 0x080;
};

pub const pollfd = extern struct {
    fd: fd_t,
    events: i16,
    revents: i16,
};

pub const Stat = extern struct {
    const __dev_t = c_ulong;
    const __ino_t = c_ulong;
    const __nlink_t = c_ulong;
    const __mode_t = c_uint;
    const __uid_t = c_uint;
    const __gid_t = c_uint;
    const __off_t = c_long;
    const __blksize_t = c_long;
    const __blkcnt_t = c_long;
    const __syscall_slong_t = c_long;

    st_dev: __dev_t = 0,
    st_ino: __ino_t = 0,
    st_nlink: __nlink_t = 0,
    st_mode: __mode_t = 0,
    st_uid: __uid_t = 0,
    st_gid: __gid_t = 0,
    __pad0: c_int = 0,
    st_rdev: __dev_t = 0,
    st_size: __off_t = 0,
    st_blksize: __blksize_t = 0,
    st_blocks: __blkcnt_t = 0,
    st_atim: timespec = std.mem.zeroes(timespec),
    st_mtim: timespec = std.mem.zeroes(timespec),
    st_ctim: timespec = std.mem.zeroes(timespec),
    __glibc_reserved: [3]__syscall_slong_t = std.mem.zeroes([3]__syscall_slong_t),
};

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
};
