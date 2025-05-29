const std = @import("std");
const arena = @import("memory/arena.zig");

pub const Arena = arena.Arena;
pub const TempArena = arena.TempArena;

pub const KiB = 1024;
pub const MiB = 1024 * KiB;
pub const GiB = 1024 * MiB;

pub const assert = std.debug.assert;

pub var common_arena: Arena = undefined;
pub var swapchain_arena: Arena = undefined;

threadlocal var temp_initialized = false;
threadlocal var temp_arena_a: Arena = undefined;
threadlocal var temp_arena_b: Arena = undefined;
threadlocal var temp_arena_next: *Arena = undefined;

pub fn init() !void {
    common_arena = try Arena.init(.{ .virtual = .{} });
    swapchain_arena = try Arena.init(.{ .virtual = .{} });

    // temp_arena = try Arena.init(.{ .virtual = .{ .reserved_capacity = GiB } });
}

pub fn deinit() !void {
    common_arena.deinit();
    swapchain_arena.deinit();
}

inline fn initializeTemp() void {
    if (!temp_initialized) {
        temp_arena_a = Arena.init(.{ .virtual = .{ .reserved_capacity = GiB } }) catch @panic("Temp arena init failed");
        temp_arena_b = Arena.init(.{ .virtual = .{ .reserved_capacity = GiB } }) catch @panic("Temp arena init failed");
        temp_arena_next = &temp_arena_a;
        temp_initialized = true;
    } else assert(temp_arena_next == &temp_arena_a or temp_arena_next == &temp_arena_b);
}

pub fn get_temp() TempArena {
    initializeTemp();

    const use = temp_arena_next;

    if (temp_arena_next == &temp_arena_a) {
        temp_arena_next = &temp_arena_b;
    } else {
        temp_arena_next = &temp_arena_a;
    }

    return TempArena.init(use);
}

pub fn get_scratch(conflict: *Arena) TempArena {
    initializeTemp();

    var use: *Arena = undefined;

    if (conflict == &temp_arena_a) {
        use = &temp_arena_b;
        temp_arena_next = &temp_arena_a;
    } else if (conflict == &temp_arena_b) {
        use = &temp_arena_a;
        temp_arena_next = &temp_arena_b;
    } else if (temp_arena_next == &temp_arena_a) {
        use = &temp_arena_a;
        temp_arena_next = &temp_arena_b;
    } else {
        assert(temp_arena_next == &temp_arena_b);
        use = &temp_arena_b;
        temp_arena_next = &temp_arena_a;
    }

    return TempArena.init(use);
}
