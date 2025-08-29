const std = @import("std");
const log = std.log.scoped(.linux_v10);
const wl = @import("wayland.zig");

const assert = std.debug.assert;

var running = false;

pub fn main() !void {
    var lwl = try std.DynLib.open("libwayland-client.so.0");
    defer lwl.close();

    try wl.load(&lwl);

    if (wl.display_connect(null)) |display| {
        defer wl.display_disconnect(display);
        log.debug("display connected", .{});

        const registry = wl.get_registry(display) orelse unreachable;
        const listener = wl.RegistryListener{
            .global = wlGlobal,
            .global_remove = wlGlobalRemove,
        };
        wl.registry_add_listener(registry, &listener, null);
        _ = wl.display_roundtrip(display);
        wl.registry_destroy(registry);
    } else {
        log.err("wl_display_connect failed", .{});
        return error.DisplayConnectionFailed;
    }
}

fn wlGlobal(data: ?*anyopaque, registry: *wl.Registry, name: u32, interface: [*c]const u8, version: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = version;

    log.debug("wlGlobal: {} - {s}", .{ name, interface });
}

fn wlGlobalRemove(registry: *wl.Registry, name: u32) callconv(.c) void {
    _ = registry;
    _ = name;
    unreachable;
}

// fn LinuxUpdateWindow() void {
//     unreachable;
// }
