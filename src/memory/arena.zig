const std = @import("std");
const builtin = @import("builtin");
const mem = @import("../memory.zig");

const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

pub const Arena = struct {
    data: []u8,
    used: usize,
    reserved_capacity: usize,

    flags: Flags,

    last_allocation: ?*anyopaque,
    last_size: usize,

    pub const Flags = packed struct(u8) {
        @"align": bool = true,
        /// reserved_virtual_address_space
        rvas: bool = false,
        __reserved__: u6 = 0,
    };

    pub const InitOptions = union(enum) {
        pub const Virtual = struct {
            flags: Flags = .{ .rvas = true },
            reserved_capacity: usize,
        };

        slice: struct {
            flags: Flags = .{ .rvas = false },
            data: []u8,
        },
        virtual: Virtual,
    };

    pub const InitError = error{
        OutOfMemory,
        AccessDenied,
        Unexpected,
    };

    pub fn init(options: InitOptions) InitError!Arena {
        return switch (options) {
            .slice => |s| return .{
                .data = s.data,
                .used = 0,
                .reserved_capacity = s.data.len,
                .flags = s.flags,
                .last_allocation = null,
                .last_size = 0,
            },
            .virtual => |v| return init_virtual(v),
        };
    }

    fn init_virtual(options: InitOptions.Virtual) InitError!Arena {
        std.debug.assert(options.flags.rvas);

        const page_size = std.heap.pageSize();
        std.debug.assert(options.reserved_capacity >= page_size);

        return switch (builtin.os.tag) {
            else => @compileError("missing implementation for platforn for 'Arena.init_virtual'"),
            .linux => {
                const data = std.posix.mmap(
                    null,
                    options.reserved_capacity,
                    std.c.PROT.NONE,
                    .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
                    -1,
                    0,
                ) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => return error.Unexpected,
                };

                std.posix.mprotect(data[0..page_size], std.c.PROT.READ | std.c.PROT.WRITE) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.AccessDenied => return error.AccessDenied,
                    error.Unexpected => return error.Unexpected,
                };

                return .{
                    .data = data,
                    .used = 0,
                    .reserved_capacity = options.reserved_capacity,
                    .flags = options.flags,
                    .last_allocation = null,
                    .last_size = 0,
                };
            },
        };
    }

    pub fn allocator(this: *@This()) Allocator {
        return .{
            .ptr = this,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn grow(this: *@This(), min_size: usize) bool {
        if (!this.flags.rvas) return false;

        _ = min_size;
        std.debug.assert(false);
        return true;
    }

    pub fn alloc(ctx: *anyopaque, n: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const this: *Arena = @ptrCast(@alignCast(ctx));

        if (builtin.mode == .Debug) {
            if (!this.flags.@"align") std.debug.assert(alignment == .@"1");
        }

        const ptr_align = alignment.toByteUnits();
        const aligned_size = if (this.flags.@"align") n + ptr_align - 1 else n;
        const available = this.data[this.used..];

        if (aligned_size > available.len) {
            if (!this.grow(this.data.len + aligned_size)) {
                return null;
            }
        }

        const unaligned_addr: usize = @intFromPtr(available.ptr);
        this.used += n;

        return @ptrFromInt(blk: {
            if (this.flags.@"align") {
                const r = std.mem.alignForward(usize, unaligned_addr, ptr_align);
                this.used += r - unaligned_addr;
                break :blk r;
            } else break :blk unaligned_addr;
        });
    }

    pub fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = memory;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        std.debug.assert(false);
        unreachable;
    }

    pub fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = memory;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        std.debug.assert(false);
        unreachable;
    }

    pub fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = memory;
        _ = alignment;
        _ = ret_addr;
        std.debug.assert(false);
        unreachable;
    }
};

test "Arena from slice" {
    var buf: [70]u8 align(8) = [_]u8{1} ** 70; // Needs to be bigger to account for alignment
    try std.testing.expectEqual(@as(*u8, @ptrCast(&buf)), &buf[0]);

    var arena = try Arena.init(.{ .slice = .{ .data = &buf } });
    const aa = arena.allocator();

    const first = try aa.create(u8);
    const second = try aa.create(u8);

    try std.testing.expectEqual(first, &buf[0]);
    try std.testing.expectEqual(second, &buf[1]);

    if (@import("builtin").mode == .Debug) {
        try std.testing.expectEqual(0xaa, first.*);
        try std.testing.expectEqual(0xaa, second.*);
    }

    first.* = 11;
    second.* = 22;

    try std.testing.expectEqual(first.*, buf[0]);
    try std.testing.expectEqual(second.*, buf[1]);

    const third = try aa.alignedAlloc(u8, Alignment.@"4", 2);

    try std.testing.expectEqual(@as(*u8, @ptrCast(third.ptr)), &buf[4]);

    if (@import("builtin").mode == .Debug) {
        try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xaa }, third);
        try std.testing.expectEqual(0xaa, third[0]);
        try std.testing.expectEqual(0xaa, third[1]);
    }

    third[0] = 33;
    third[1] = 44;

    try std.testing.expectEqualSlices(u8, &.{ 33, 44 }, third);
    try std.testing.expectEqual(third[0], buf[4]);
    try std.testing.expectEqual(third[1], buf[5]);
}

test "Arena uncommitted" {
    const page_size = std.heap.pageSize();
    var arena = try Arena.init(.{ .virtual = .{ .reserved_capacity = page_size } });
    const aa = arena.allocator();

    const first = try aa.create(u8);
    const second = try aa.create(u8);

    if (@import("builtin").mode == .Debug) {
        try std.testing.expectEqual(0xaa, first.*);
        try std.testing.expectEqual(0xaa, second.*);
    }

    first.* = 11;
    second.* = 22;

    try std.testing.expectEqual(11, first.*);
    try std.testing.expectEqual(22, second.*);

    const third = try aa.alignedAlloc(u8, Alignment.@"4", 2);

    if (@import("builtin").mode == .Debug) {
        try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xaa }, third);
        try std.testing.expectEqual(0xaa, third[0]);
        try std.testing.expectEqual(0xaa, third[1]);
    }

    third[0] = 33;
    third[1] = 44;

    try std.testing.expectEqualSlices(u8, &.{ 33, 44 }, third);
    try std.testing.expectEqual(33, third[0]);
    try std.testing.expectEqual(44, third[1]);

    // fill remaining capacity
    const remaining = arena.data.len - arena.used;
    const remaining_data = try aa.alignedAlloc(u8, .@"1", remaining);

    try std.testing.expectEqual(remaining, remaining_data.len);
    try std.testing.expectEqual(arena.data.len, arena.used);

    // should trigger grow/commit
    const newmem = try aa.create(u64);
    _ = newmem;
}
