const std = @import("std");
const assert = std.debug.assert;

const common = @import("v10_common");

const MemoryArena = @This();

memory: []u8,
used: usize = 0,
temp_count: u32 = 0,

pub fn init(mem: []u8) MemoryArena {
    return .{
        .memory = mem,
        .used = 0,
    };
}

pub inline fn push(this: *MemoryArena, comptime T: type) *T {
    const result: *T = @ptrCast(this.pushSizeAligned(@sizeOf(T), @alignOf(T)));
    return result;
}

pub inline fn pushArray(this: *MemoryArena, len: usize, comptime T: type) []T {
    const size = len * @sizeOf(T);
    const result: []T = @ptrCast(this.pushSizeAligned(size, @alignOf(T))[0..size]);
    return result;
}

pub inline fn pushSize(this: *MemoryArena, size: usize) [*]u8 {
    const result = this.pushSizeAligned(size, 1);
    return result;
}

pub inline fn pushAligned(this: *MemoryArena, comptime T: type, comptime alignment: u29) *align(alignment) T {
    const result: *align(alignment) T = @ptrCast(this.pushSizeAligned(@sizeOf(T), alignment));
    return result;
}

pub inline fn pushArrayAligned(this: *MemoryArena, len: usize, comptime T: type, comptime alignment: u29) []align(alignment) T {
    const size = len * @sizeOf(T);
    const result: []align(alignment) T = @ptrCast(this.pushSizeAligned(size, alignment)[0..size]);
    return result;
}

pub inline fn pushSizeAligned(this: *MemoryArena, size: usize, comptime alignment: u29) [*]align(alignment) u8 {
    const aligned_used = common.alignForward(this.used, alignment);
    assert(this.memory.len - aligned_used >= size);

    const result = @as([*]align(alignment) u8, @ptrCast(@alignCast(this.memory.ptr + aligned_used)));
    this.used = aligned_used + size;
    return result;
}

pub const TemporaryMemory = struct {
    arena: *MemoryArena,
    used: usize,

    pub inline fn begin(arena: *MemoryArena) TemporaryMemory {
        const result = arena.beginTemporaryMemory();
        return result;
    }

    pub inline fn end(this: TemporaryMemory) void {
        endTemporaryMemory(this);
    }
};

pub inline fn beginTemporaryMemory(this: *MemoryArena) TemporaryMemory {
    const result: TemporaryMemory = .{ .arena = this, .used = this.used };
    this.temp_count += 1;
    return result;
}

pub inline fn endTemporaryMemory(tmp: TemporaryMemory) void {
    assert(tmp.arena.used >= tmp.used);
    tmp.arena.used = tmp.used;

    assert(tmp.arena.temp_count > 0);
    tmp.arena.temp_count -= 1;
}

pub fn check(this: *MemoryArena) void {
    if (this.temp_count != 0) {
        @trap();
    }
}
