const std = @import("std");
const log = std.log.scoped(.linux_v10);
const wayland = @import("old_wayland.zig");
const wlc = wayland.core;
const wlp = wayland.protocol;

const assert = std.debug.assert;

var running = false;

pub fn main() !void {
    var lwl = try std.DynLib.open("libwayland-client.so.0");
    defer lwl.close();

    try wayland.load(&lwl);

    if (wlc.display_connect(null)) |display| {
        defer wlc.display_disconnect(display);
        log.debug("display connected", .{});

        const registry = wlp.get_registry(display) orelse unreachable;
        const listener = wlp.RegistryListener{
            .global = wlGlobal,
            .global_remove = wlGlobalRemove,
        };
        wlp.registry_add_listener(registry, &listener, null);
        _ = wlc.display_roundtrip(display);
        wlp.registry_destroy(registry);
    } else {
        log.err("wl_display_connect failed", .{});
        return error.DisplayConnectionFailed;
    }
}

fn wlGlobal(data: ?*anyopaque, registry: *wlc.Registry, name: u32, interface: [*c]const u8, version: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = version;

    log.debug("wlGlobal: {} - {s}", .{ name, interface });
}

fn wlGlobalRemove(registry: *wlc.Registry, name: u32) callconv(.c) void {
    _ = registry;
    _ = name;
    unreachable;
}

// fn LinuxUpdateWindow() void {
//     unreachable;
// }
