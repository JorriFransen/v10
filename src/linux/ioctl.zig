const std = @import("std");
const log = std.log.scoped(.@".linux.ioctl");
const linux = @import("linux.zig");
const abi = linux.abi;

pub const IOCTLError = linux.Error || error{
    ArgIsInvalidPointer,
    InvalidRequestOrArg,
    InvalidFDForRequest,
};

pub fn ioctl(fd: linux.fd_t, request: usize, arg: usize) IOCTLError!usize {
    const rc = abi.syscall3(.ioctl, @as(u32, @bitCast(fd)), request, arg);
    if (linux.check_errno(rc)) |e| return switch (e) {
        .BADF => error.InvalidFD,
        .FAULT => error.ArgIsInvalidPointer,
        .INVAL => error.InvalidRequestOrArg,
        .IO => error.IO,
        .NOTTY => error.InvalidFDForRequest,
        .INTR => error.Interrupt,
        .ACCES, .PERM => error.PermissionDenied,
        else => blk: {
            log.warn("Unexpected errno for ioctl: {}", .{e});
            break :blk error.UnexpectedErrno;
        },
    };

    return @intCast(rc);
}

pub const Request = packed struct {
    pub const SizeInt = @Int(.unsigned, abi.IOC.SIZE);
    pub const DirectionInt = @Int(.unsigned, abi.IOC.DIR);

    nr: u8,
    type: u8,
    size: SizeInt,
    dir: DirectionInt,
};

pub inline fn IOC(dir: Request.DirectionInt, @"type": u8, nr: u8, size: Request.SizeInt) u32 {
    const request = Request{
        .nr = nr,
        .type = @"type",
        .size = size,
        .dir = dir,
    };

    return @bitCast(request);
}

pub inline fn IOR(@"type": u8, nr: u8, comptime T: type) u32 {
    return IOC(abi.IOC.READ, @"type", nr, @sizeOf(T));
}

pub inline fn IOW(@"type": u8, nr: u8, comptime T: type) u32 {
    return IOC(abi.IOC.WRITE, @"type", nr, @sizeOf(T));
}

pub inline fn IOWR(@"type": u8, nr: u8, comptime T: type) u32 {
    return IOC(abi.IOC.READ | abi.IOC.WRITE, @"type", nr, @sizeOf(T));
}

comptime {
    std.debug.assert(@bitSizeOf(Request) == 32);
}
