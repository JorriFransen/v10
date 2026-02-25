const std = @import("std");

const assert = std.debug.assert;

const MemoryArena = @This();

memory: []u8,
used: usize = 0,

pub fn init(mem: []u8) MemoryArena {
    return .{
        .memory = mem,
        .used = 0,
    };
}

pub fn pushMemory(this: *MemoryArena, comptime T: type) *T {
    assert(this.memory.len - this.used >= @sizeOf(T));

    const result: *T = @ptrCast(@alignCast(this.memory.ptr + this.used));
    this.used += @sizeOf(T);
    return result;
}
