const std = @import("std");
const assert = std.debug.assert;
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
pub const F = abi.F;
pub const SO = abi.SO;

pub const Error = error{
    ConnectionClosed,
    ConnectionReset,
    DiskQuotaExceeded,
    EndOfFile,
    FileBusy,
    FileDoesNotExist,
    FileExists,
    Interrupt,
    InvalidArg,
    InvalidDevice,
    InvalidFD,
    InvalidFlags,
    InvalidPath,
    InvalidPointer,
    IO,
    IsDirectory,
    Lock,
    MessageTooBig,
    NameTooLong,
    NoData,
    NoMemory,
    NoSpaceLeft,
    NotConnected,
    PermissionDenied,
    ReadOnly,
    Timeout,
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

pub fn sendmsg(sock_fd: fd_t, header: *msghdr, flags: c_uint) Error!usize {
    const rc = abi.syscall3(.sendmsg, @as(u32, @bitCast(sock_fd)), @intFromPtr(header), flags);
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
    const rc = abi.syscall3(.recvmsg, @as(u32, @bitCast(sock_fd)), @intFromPtr(header), flags);
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

pub fn fcntl(fd: fd_t, op: c_int, arg: usize) !u32 {
    const rc = abi.syscall3(.fcntl, @as(u32, @bitCast(fd)), @as(u32, @bitCast(op)), arg);
    if (check_errno(rc)) |e| return switch (e) {
        else => blk: {
            log.warn("Unexpected errno for fcntl: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };
    return @as(u32, @intCast(rc));
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
            std.debug.assert(@sizeOf(storage) == SS_MAXSIZE);
            std.debug.assert(@alignOf(storage) == 8);
        }
    };

    /// UNIX domain socket address
    pub const un = extern struct {
        family: sa_family_t = AF.UNIX,
        path: [108]u8,
    };
};

pub const iovec = extern struct {
    base: [*]u8,
    len: usize,
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
