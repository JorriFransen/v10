const std = @import("std");
const arena = @import("arena.zig");

const assert = std.debug.assert;

pub const Arena = arena.Arena;
pub const TempArena = arena.TempArena;

pub const KiB = 1024;
pub const MiB = 1024 * KiB;
pub const GiB = 1024 * MiB;

threadlocal var temp_initialized = false;
threadlocal var temp_arena_a: Arena = undefined;
threadlocal var temp_arena_b: Arena = undefined;
threadlocal var temp_arena_next: *Arena = undefined;

pub fn init() !void {
    initTemp();
}

pub fn deinit() !void {
    deinitTemp();
}

/// Must be called on each thread using temp/scratch arenas
pub fn initTemp() void {
    assert(!temp_initialized);

    const options = Arena.InitOptions{ .virtual = .{ .reserved_capacity = 1 * GiB } };
    temp_arena_a = Arena.init(options) catch @panic("Temp arena init failed");
    temp_arena_b = Arena.init(options) catch @panic("Temp arena init failed");
    temp_arena_next = &temp_arena_a;

    temp_initialized = true;
}

pub fn deinitTemp() void {
    assert(temp_initialized);

    temp_arena_a.deinit();
    temp_arena_b.deinit();

    temp_arena_a = undefined;
    temp_arena_b = undefined;
    temp_arena_next = undefined;

    temp_initialized = false;
}

pub fn getTemp() TempArena {
    assert(temp_initialized);

    const use = temp_arena_next;

    if (temp_arena_next == &temp_arena_a) {
        temp_arena_next = &temp_arena_b;
    } else {
        temp_arena_next = &temp_arena_a;
    }

    return TempArena.init(use);
}

pub fn getScratch(conflict: *Arena) TempArena {
    assert(temp_initialized);

    var use: *Arena = temp_arena_next;

    if (conflict == &temp_arena_a) {
        use = &temp_arena_b;
        temp_arena_next = &temp_arena_a;
    } else if (conflict == &temp_arena_b) {
        use = &temp_arena_a;
        temp_arena_next = &temp_arena_b;
    } else if (temp_arena_next == &temp_arena_a) {
        temp_arena_next = &temp_arena_b;
    } else {
        assert(temp_arena_next == &temp_arena_b);
        temp_arena_next = &temp_arena_a;
    }

    return TempArena.init(use);
}

/// Resets all temp/scratch arenas
pub fn resetTemp() void {
    assert(temp_initialized);

    temp_arena_a.reset();
    temp_arena_b.reset();
}
