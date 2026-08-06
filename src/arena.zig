const std = @import("std");
const assert = std.debug.assert;

const math = @import("math");

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

pub inline fn pushMemory(this: *MemoryArena, comptime T: type) *T {
    const size = @sizeOf(T);
    const aligned_used = alignForward(this.used, @alignOf(T));

    assert(this.memory.len - aligned_used >= size);

    const result: *T = @ptrCast(@alignCast(this.memory.ptr + aligned_used));
    this.used = aligned_used + size;
    return result;
}

pub inline fn pushArray(this: *MemoryArena, len: usize, comptime T: type) []T {
    const size: usize = @sizeOf(T) * len;
    const aligned_used = alignForward(this.used, @alignOf(T));
    assert(this.memory.len - aligned_used >= size);

    const result: []T = @as([*]T, @ptrCast(@alignCast(this.memory.ptr + aligned_used)))[0..len];
    this.used = aligned_used + size;
    return result;
}

inline fn alignForward(addr: usize, alignment: usize) usize {
    assert(alignment > 0 and math.isPowerOfTwo(alignment));

    const am1 = alignment - 1;
    const result = (addr + am1) & ~(am1);
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
