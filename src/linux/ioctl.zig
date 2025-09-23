const std = @import("std");
const linux = @import("linux.zig");

// TODO: Zigs version returns usize, this doesn't work with -1...
//       If we return isize this doesn't work with -1...
//       I think syscall always uses size_t/usize?,
//        check this, make a sycall wrapper that handles -1 correctly.
pub extern "c" fn ioctl(fd: linux.fd_t, op: c_int, ...) callconv(.c) c_int;

pub const bits = switch (@import("builtin").cpu.arch) {
    .mips,
    .mipsel,
    .mips64,
    .mips64el,
    .powerpc,
    .powerpcle,
    .powerpc64,
    .powerpc64le,
    .sparc,
    .sparc64,
    => .{ .size = 13, .dir = 3, .none = 1, .read = 2, .write = 4 },
    else => .{ .size = 14, .dir = 2, .none = 0, .read = 2, .write = 1 },
};

const Direction = std.meta.Int(.unsigned, bits.dir);
const Size = std.meta.Int(.unsigned, bits.size);

pub const Request = packed struct {
    nr: u8,
    type: u8,
    size: std.meta.Int(.unsigned, bits.size),
    dir: Direction,
};

pub inline fn IOC(dir: Direction, @"type": u8, nr: u8, size: Size) c_int {
    const request = Request{
        .nr = nr,
        .type = @"type",
        .size = size,
        .dir = dir,
    };

    return @bitCast(request);
}

pub inline fn IOR(@"type": u8, nr: u8, comptime T: type) c_int {
    return IOC(bits.read, @"type", nr, @sizeOf(T));
}

pub inline fn IOW(@"type": u8, nr: u8, comptime T: type) c_int {
    return IOC(bits.write, @"type", nr, @sizeOf(T));
}

pub inline fn IOWR(@"type": u8, nr: u8, comptime T: type) c_int {
    return IOC(bits.read | bits.write, @"type", nr, @sizeOf(T));
}

comptime {
    std.debug.assert(@bitSizeOf(Request) == 32);
}
