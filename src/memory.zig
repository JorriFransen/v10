const std = @import("std");

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
        grow: bool = false,
        __reserved__: u6 = 0,
    };

    pub fn init(data: []u8, flags: Flags) Arena {
        return .{
            .data = data,
            .used = 0,
            .reserved_capacity = data.len,
            .flags = flags,
            .last_allocation = null,
            .last_size = 0,
        };
    }

    // TODO: Merge with init, add InitOptions...
    pub fn create(flags: Flags) Arena {
        std.debug.assert(false);
        const data = [_]u8{};
        return init(&data, flags);
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
        if (!this.flags.grow) return false;

        _ = min_size;
        std.debug.assert(false);
        return true;
    }

    pub fn alloc(ctx: *anyopaque, n: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const this: *Arena = @ptrCast(@alignCast(ctx));

        const ptr_align = alignment.toByteUnits();
        const aligned_size = if (this.flags.@"align") n + ptr_align - 1 else n;
        const available = this.data[this.used..];

        if (aligned_size > available.len) {
            if (!this.grow(this.data.len + aligned_size)) {
                return null;
            }
        }

        var result_addr: usize = @intFromPtr(available.ptr);

        this.used += n;
        if (this.flags.@"align") {
            const old = result_addr;
            result_addr = std.mem.alignForward(usize, result_addr, ptr_align);
            this.used += result_addr - old;
        }

        return @ptrFromInt(result_addr);
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
    var mem: [70]u8 align(8) = [_]u8{1} ** 70; // Needs to be bigger to account for alignment
    try std.testing.expectEqual(@as(*u8, @ptrCast(&mem)), &mem[0]);

    var arena = Arena.init(&mem, .{});
    const aa = arena.allocator();

    const first = try aa.create(u8);
    const second = try aa.create(u8);

    try std.testing.expectEqual(first, &mem[0]);
    try std.testing.expectEqual(second, &mem[1]);

    if (@import("builtin").mode == .Debug) {
        try std.testing.expectEqual(0xaa, first.*);
        try std.testing.expectEqual(0xaa, second.*);
    }

    first.* = 11;
    second.* = 22;

    try std.testing.expectEqual(first.*, mem[0]);
    try std.testing.expectEqual(second.*, mem[1]);

    const third = try aa.alignedAlloc(u8, Alignment.@"4", 2);

    try std.testing.expectEqual(@as(*u8, @ptrCast(third.ptr)), &mem[4]);

    if (@import("builtin").mode == .Debug) {
        try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xaa }, third);
        try std.testing.expectEqual(0xaa, third[0]);
        try std.testing.expectEqual(0xaa, third[1]);
    }

    third[0] = 33;
    third[1] = 44;

    try std.testing.expectEqualSlices(u8, &.{ 33, 44 }, third);
    try std.testing.expectEqual(third[0], mem[4]);
    try std.testing.expectEqual(third[1], mem[5]);
}

test "Arena uncommitted" {
    var arena = Arena.create(.{});
    const aa = arena.allocator();

    const first = try aa.create(u8);
    const second = try aa.create(u8);

    _ = first;
    _ = second;

    // try std.testing.expectEqual(first, &mem[0]);
    // try std.testing.expectEqual(second, &mem[1]);
    //
    // if (@import("builtin").mode == .Debug) {
    //     try std.testing.expectEqual(0xaa, first.*);
    //     try std.testing.expectEqual(0xaa, second.*);
    // }
    //
    // first.* = 11;
    // second.* = 22;
    //
    // try std.testing.expectEqual(first.*, mem[0]);
    // try std.testing.expectEqual(second.*, mem[1]);
    //
    // const third = try aa.alignedAlloc(u8, Alignment.@"4", 2);
    //
    // try std.testing.expectEqual(@as(*u8, @ptrCast(third.ptr)), &mem[4]);
    //
    // if (@import("builtin").mode == .Debug) {
    //     try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xaa }, third);
    //     try std.testing.expectEqual(0xaa, third[0]);
    //     try std.testing.expectEqual(0xaa, third[1]);
    // }
    //
    // third[0] = 33;
    // third[1] = 44;
    //
    // try std.testing.expectEqualSlices(u8, &.{ 33, 44 }, third);
    // try std.testing.expectEqual(third[0], mem[4]);
    // try std.testing.expectEqual(third[1], mem[5]);
}
