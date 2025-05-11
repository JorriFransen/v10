const std = @import("std");

const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

pub const ArenaFlags = packed struct(u8) {
    noalign: bool = false,
    grow: bool = false,
    nozero: bool = false,
    __reserved__: u5 = 0,
};

pub const Arena = struct {
    data: []u8,
    used: usize,
    reserved_capacity: usize,

    flags: ArenaFlags,

    last_allocation: ?*anyopaque,
    last_size: usize,

    pub fn create(data: []u8) Arena {
        return .{
            .data = data,
            .used = 0,
            .reserved_capacity = data.len,
            .flags = .{},
            .last_allocation = null,
            .last_size = 0,
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

    pub fn alloc(ctx: *anyopaque, n: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;

        const this: *Arena = @ptrCast(@alignCast(ctx));
        const ptr_align = alignment.toByteUnits();

        const aligned_size = if (this.flags.noalign) n else n + ptr_align - 1;

        const available = this.data[this.used..];

        _ = aligned_size;
        _ = available;
        std.debug.assert(false);
        unreachable;
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
    var mem = [1]u8{0} ** 1024;
    try std.testing.expectEqual(@as(*u8, @ptrCast(&mem)), &mem[0]);
    var arena = Arena.create(&mem);
    const aa = arena.allocator();

    const first = try aa.create(u8);
    const second = try aa.create(u8);
    std.debug.assert(first == &mem[0]);
    std.debug.assert(second == &mem[1]);

    first.* = 11;
    second.* = 22;
}
