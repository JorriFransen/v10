const std = @import("std");
const log = std.log.scoped(.linux_v10);
const wayland = @import("wayland");
const wl = wayland.wl;

const assert = std.debug.assert;

var wl_compositor: *wl.Compositor = undefined;

pub fn main() !void {
    var lwl = try std.DynLib.open("libwayland-client.so.0");
    defer lwl.close();

    try wl.load(&lwl);

    const display = wl.display_connect(null) orelse {
        log.err("wl_display_connect failed", .{});
        return error.UnexpectedWayland;
    };

    log.debug("Display connected", .{});

    const registry = display.get_registry() orelse {
        log.err("wl_display_get_registry failed", .{});
        return error.UnexpectedWayland;
    };

    const registry_listener = wl.Registry.Listener{
        .global = wlRegGlobal,
        .global_remove = wlRegGlobalRemove,
    };
    registry.add_listener(&registry_listener, null);

    _ = wl.display_roundtrip(display);
    log.debug("Display roundtrip finished", .{});

    registry.destroy();
}

fn wlRegGlobal(data: ?*anyopaque, registry_opt: ?*wl.Registry, name: u32, interface: [*:0]const u8, version: u32) callconv(.c) void {
    _ = data;
    _ = registry_opt;

    // const registry = registry_opt orelse unreachable;
    // const iface_name = std.mem.span(interface);

    log.debug("global: {} - {s} - {}", .{ name, interface, version });
}

fn wlRegGlobalRemove(data: ?*anyopaque, registry: ?*wl.Registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = name;
}

// fn LinuxUpdateWindow() void {
//     unreachable;
// }
