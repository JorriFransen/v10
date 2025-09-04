const std = @import("std");
const log = std.log.scoped(.linux_v10);
const wayland = @import("wayland");
const wl = wayland.wl;
const xdg = wayland.xdg_shell;

const assert = std.debug.assert;

var wl_compositor: *wl.Compositor = undefined;
var wl_shm: *wl.Shm = undefined;
var wl_buffer: *wl.Buffer = undefined;
var pixels: *u8 = undefined;
var xdg_shell: *xdg.WmBase = undefined;
var xdg_toplevel: *xdg.Toplevel = undefined;

// TODO: WLGEN
//  - Use defined enums for enum arguments

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

    registry.destroy();

    const surface = wl.Compositor.create_surface(wl_compositor) orelse {
        log.err("wl_compositor_create_surface failed", .{});
        return error.UnexpectedWayland;
    };
    defer surface.destroy();

    const xdg_surface = xdg_shell.get_xdg_surface(surface) orelse {
        log.err("xdg_wm_base_get_xdg_surface_failed", .{});
        return error.UnexpectedWayland;
    };
    defer xdg_surface.destroy();

    _ = alloc_shm(16);

    resize(200, 100);

    wl_buffer.destroy();
}

fn alloc_shm(size: std.c.off_t) std.c.fd_t {
    const S = std.posix.S;

    var name_buf: [16]u8 = undefined;
    name_buf[0] = '/';
    name_buf[name_buf.len - 1] = 0;

    for (name_buf[1 .. name_buf.len - 1]) |*c| {
        c.* = std.crypto.random.intRangeAtMost(u8, 'a', 'z');
    }
    const name: [*:0]u8 = @ptrCast(&name_buf);

    const open_flags = std.posix.O{ .ACCMODE = .RDWR, .CREAT = true, .EXCL = true };
    const mode: std.c.mode_t = S.IWUSR | S.IRUSR | S.IWOTH | S.IROTH;

    // TODO: Check for shm_open error
    const fd = std.c.shm_open(name, @bitCast(open_flags), mode);
    _ = std.c.shm_unlink(name);
    _ = std.c.ftruncate(fd, size);

    return fd;
}

fn resize(width: u32, height: u32) void {
    const size = width * height * 4;

    const fd = alloc_shm(size);

    const prot = std.c.PROT.READ | std.c.PROT.WRITE;
    const flags = std.c.MAP{ .TYPE = .SHARED };
    pixels = @ptrCast(std.c.mmap(null, size, prot, flags, fd, 0));

    const pool = wl_shm.create_pool(fd, @intCast(size)) orelse {
        @panic("wl_shm_create_pool failed");
    };
    wl_buffer = pool.create_buffer(0, @intCast(width), @intCast(height), @intCast(width * 4), @intFromEnum(wl.Shm.Format.argb8888)) orelse {
        @panic("wl_shm_pool_create_buffer failed");
    };
    pool.destroy();

    _ = std.c.close(fd);
}

fn wlRegGlobal(data: ?*anyopaque, registry_opt: ?*wl.Registry, name: u32, interface_name: [*:0]const u8, version: u32) callconv(.c) void {
    _ = data;

    const registry = registry_opt orelse unreachable;
    const iface_name = std.mem.span(interface_name);

    if (std.mem.eql(u8, iface_name, std.mem.span(wl.Compositor.interface.name))) {
        log.debug("Binding wl_compositor version {}", .{version});
        wl_compositor = @ptrCast(registry.bind(name, wl.Compositor.interface, version));
    } else if (std.mem.eql(u8, iface_name, std.mem.span(wl.Shm.interface.name))) {
        log.debug("Binding wl_shm version {}", .{version});
        wl_shm = @ptrCast(registry.bind(name, wl.Shm.interface, version));
    } else if (std.mem.eql(u8, iface_name, std.mem.span(xdg.WmBase.interface.name))) {
        log.debug("Binding xdg_wm_base version {}", .{version});
        xdg_shell = @ptrCast(registry.bind(name, xdg.WmBase.interface, version));
    }
}

fn wlRegGlobalRemove(data: ?*anyopaque, registry: ?*wl.Registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = name;
    unreachable;
}

// fn LinuxUpdateWindow() void {
//     unreachable;
// }
