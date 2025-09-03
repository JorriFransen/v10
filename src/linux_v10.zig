const std = @import("std");
const log = std.log.scoped(.linux_v10);
const wayland = @import("wayland");
const wl = wayland.wl;

const assert = std.debug.assert;

var running = false;

pub fn main() !void {
    var lwl = try std.DynLib.open("libwayland-client.so.0");
    defer lwl.close();

    try wl.load(&lwl);

    if (wl.display_connect(null)) |display| {
        defer wl.display_disconnect(display);
        log.debug("display connected", .{});

        const registry = display.get_registry() orelse unreachable;
        const listener = wl.Registry.Listener{
            .global = wlGlobal,
            .global_remove = wlGlobalRemove,
        };
        wl.Registry.add_listener(registry, &listener, null);
        _ = wl.display_roundtrip(display);
        wl.Registry.destroy(registry);
    } else {
        log.err("wl_display_connect failed", .{});
        return error.DisplayConnectionFailed;
    }
}

fn wlGlobal(data: ?*anyopaque, registry: ?*wl.Registry, name: u32, interface: [*:0]const u8, version: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = version;

    log.debug("wlGlobal: {} - {s}", .{ name, interface });
}

fn wlGlobalRemove(data: ?*anyopaque, registry: ?*wl.Registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = name;
}

// fn LinuxUpdateWindow() void {
//     unreachable;
// }
