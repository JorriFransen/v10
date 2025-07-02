const std = @import("std");
const builtin = @import("builtin");
const mem = @import("../memory.zig");
const posix = std.posix;
const windows = std.os.windows;

const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const assert = std.debug.assert;

const page_size_min = std.heap.page_size_min;
pub const max_cap: usize = mem.GiB * 4;

pub const Arena = struct {
    data: []const u8,
    used: usize,
    reserved_capacity: usize,

    flags: Flags = .{},

    last_allocation: ?[*]u8,
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
            reserved_capacity: usize = max_cap,
            initial_commit: usize = page_size_min,
        };

        slice: struct {
            flags: Flags = .{ .rvas = false },
            data: []u8,
        },
        virtual: Virtual,
    };

    pub const ArenaError = error{
        OutOfMemory,
        AccessDenied,
        CantGrow,
        ReachedReservedCapacity,
        Unexpected,
    };

    pub fn init(options: InitOptions) ArenaError!Arena {
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

    fn init_virtual(options: InitOptions.Virtual) ArenaError!Arena {
        assert(options.flags.rvas);

        assert(options.reserved_capacity >= options.initial_commit);

        switch (builtin.os.tag) {
            else => @compileError("missing implementation for platform for 'Arena.init_virtual'"),

            .linux => {
                const data: []align(page_size_min) u8 = posix.mmap(
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

                const committed = data[0..options.initial_commit];
                posix.mprotect(committed, std.c.PROT.READ | std.c.PROT.WRITE) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.AccessDenied => return error.AccessDenied,
                    error.Unexpected => return error.Unexpected,
                };

                return .{
                    .data = committed,
                    .used = 0,
                    .reserved_capacity = options.reserved_capacity,
                    .flags = options.flags,
                    .last_allocation = null,
                    .last_size = 0,
                };
            },

            .windows => {
                const reserved_ptr = windows.VirtualAlloc(
                    null,
                    options.reserved_capacity,
                    windows.MEM_RESERVE,
                    windows.PAGE_NOACCESS,
                ) catch |err| switch (err) {
                    error.Unexpected => return error.Unexpected,
                };

                const commit_ptr = windows.VirtualAlloc(
                    reserved_ptr,
                    options.initial_commit,
                    windows.MEM_COMMIT,
                    windows.PAGE_READWRITE,
                ) catch |err| switch (err) {
                    error.Unexpected => return error.Unexpected,
                };

                const ptr: [*]u8 = @ptrCast(commit_ptr);

                return .{
                    .data = ptr[0..options.initial_commit],
                    .used = 0,
                    .reserved_capacity = options.reserved_capacity,
                    .flags = options.flags,
                    .last_allocation = null,
                    .last_size = 0,
                };
            },
        }
    }

    pub fn deinit(this: *Arena) void {
        if (this.flags.rvas) {
            switch (builtin.os.tag) {
                else => @compileError("missing implementation for platforn for 'Arena.deinit'"),
                .linux => posix.munmap(@alignCast(this.data)),
                .windows => windows.VirtualFree(@ptrCast(@constCast(this.data.ptr)), 0, windows.MEM_RELEASE),
            }
        }

        this.data = &.{};
        this.used = 0;
        this.reserved_capacity = 0;
        this.last_allocation = null;
        this.last_size = 0;
    }

    pub fn allocator(this: *Arena) Allocator {
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

    pub fn reset(this: *Arena) void {
        this.used = 0;
    }

    fn grow(this: *Arena, min_cap: usize) ArenaError!void {
        if (!this.flags.rvas) return error.CantGrow;

        var new_cap = this.data.len * 2;
        while (new_cap < min_cap) new_cap *= 2;

        if (new_cap > max_cap or new_cap > this.reserved_capacity) return error.ReachedReservedCapacity;

        const old_cap = this.data.len;
        const base_ptr: [*]const u8 = this.data.ptr;

        assert(this.data.len % page_size_min == 0); // Newly committed blocks must start on page boundaries

        const new_slice: []align(page_size_min) u8 = @constCast(@alignCast(base_ptr[this.data.len .. this.data.len + (new_cap - old_cap)]));

        switch (builtin.os.tag) {
            else => @compileError("missing implementation for platform for 'Arena.grow'"),

            .linux => {
                posix.mprotect(new_slice, std.c.PROT.READ | std.c.PROT.WRITE) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.AccessDenied => return error.AccessDenied,
                    error.Unexpected => return error.Unexpected,
                };
            },

            .windows => {
                _ = windows.VirtualAlloc(
                    new_slice.ptr,
                    new_slice.len,
                    windows.MEM_COMMIT,
                    windows.PAGE_READWRITE,
                ) catch |err| switch (err) {
                    error.Unexpected => return error.Unexpected,
                };
            },
        }

        this.data = base_ptr[0..new_cap];
    }

    pub fn alloc(ctx: *anyopaque, n: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const this: *Arena = @ptrCast(@alignCast(ctx));

        if (builtin.mode == .Debug) {
            if (!this.flags.@"align") assert(alignment == .@"1");
        }

        const ptr_align = alignment.toByteUnits();
        const aligned_size = if (this.flags.@"align") n + ptr_align - 1 else n;
        const available = this.data[this.used..];

        if (aligned_size > available.len) {
            this.grow(this.data.len + aligned_size) catch {
                return null;
            };
        }

        const unaligned_addr: usize = @intFromPtr(available.ptr);
        var total_size = n;

        const result: ?[*]u8 = @ptrFromInt(blk: {
            if (this.flags.@"align") {
                const r = std.mem.alignForward(usize, unaligned_addr, ptr_align);
                const alignment_used = r - unaligned_addr;
                total_size += alignment_used;
                break :blk r;
            } else break :blk unaligned_addr;
        });

        this.used += total_size;
        this.last_allocation = result;
        this.last_size = total_size;
        return result;
    }

    pub fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = memory;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;

        if (builtin.mode == .Debug) {
            @panic("Invalid resize on memory allocated by arena");
        }

        return false;
    }

    pub fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;

        const this: *Arena = @ptrCast(@alignCast(ctx));

        if (new_len <= memory.len) {
            // When smallor or equal, just return the same slice
            assert(std.mem.isAligned(@intFromPtr(memory.ptr), alignment.toByteUnits()));
            return memory.ptr;
        } else if (this.last_allocation == memory.ptr) {
            // When bigger, grow if last allocation
            assert(this.last_size == memory.len);
            const diff = new_len - memory.len;
            if (this.used + diff > this.data.len) {
                this.grow(this.used + diff) catch return null;
            }

            this.used += diff;
            this.last_size += diff;

            return @ptrCast(this.last_allocation);
        } else {
            assert(false);
            return null;
        }
    }

    pub fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        _ = ret_addr;

        const this: *Arena = @ptrCast(@alignCast(ctx));

        if (@as(?[*]u8, @ptrCast(this.last_allocation)) == memory.ptr) {
            assert(alignment == .@"8");
            assert(std.mem.Alignment.check(alignment, @intFromPtr(memory.ptr)));

            this.used -= memory.len;
            this.last_allocation = null;
            this.last_size = 0;
        } else {
            //nop
        }
    }
};

pub const TempArena = struct {
    arena: *Arena,
    reset_to: usize,

    pub fn init(arena: *Arena) TempArena {
        return .{ .arena = arena, .reset_to = arena.used };
    }

    pub fn release(this: *TempArena) void {
        assert(this.arena.used >= this.reset_to);
        this.arena.used = this.reset_to;
    }

    pub fn allocator(this: *TempArena) Allocator {
        return this.arena.allocator();
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
    var arena = try Arena.init(.{ .virtual = .{ .reserved_capacity = page_size * 2 } });
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
