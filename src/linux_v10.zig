const std = @import("std");
const log = std.log.scoped(.linux_v10);
const wayland = @import("wayland");
const wl = wayland.wl;
const xdg = wayland.xdg_shell;

const c = @cImport({
    @cInclude("linux/input-event-codes.h");
});

const assert = std.debug.assert;

var window_width: i32 = 128;
var window_height: i32 = 128;

var configured = false;
var running = true;

var wl_shm: ?*wl.Shm = undefined;
var wl_compositor: ?*wl.Compositor = undefined;
var wl_seat: ?*wl.Seat = undefined;
var wl_surface: *wl.Surface = undefined;
var wl_callback: *wl.Callback = undefined;

var shm_fd: std.c.fd_t = undefined;
var shm_size: i64 = undefined;
var wl_pool: *wl.ShmPool = undefined;
var wl_buffer: *wl.Buffer = undefined;

var xdg_wm_base: ?*xdg.WmBase = undefined;
var xdg_toplevel: *xdg.Toplevel = undefined;

var shm_ptr: *u8 = undefined;

const registry_listener = wl.Registry.Listener{
    .global = wlRegGlobal,
    .global_remove = wlRegGlobalRemove,
};

const seat_listener = wl.Seat.Listener{
    .capabilities = wlSeatCapabilities,
    .name = @ptrCast(&nop),
};

const xdg_wm_base_listener = xdg.WmBase.Listener{
    .ping = xdgWmBasePing,
};

const xdg_surface_listener = xdg.Surface.Listener{
    .configure = xdgSurfaceConfigure,
};

const xdg_toplevel_listener = xdg.Toplevel.Listener{
    .configure = xdgToplevelConfigure,
    .close = xdgToplevelClose,
    .configure_bounds = xdgToplevelConfigureBounds,
    .wm_capabilities = xdgToplevelWmCapabilities,
};

const wl_pointer_listener = wl.Pointer.Listener{
    .button = wlPointerButton,
    .enter = @ptrCast(&nop),
    .leave = @ptrCast(&nop),
    .motion = @ptrCast(&nop),
    .axis = @ptrCast(&nop),
    .axis_source = @ptrCast(&nop),
    .axis_stop = @ptrCast(&nop),
    .axis_value120 = @ptrCast(&nop),
    .axis_relative_direction = @ptrCast(&nop),
    .frame = @ptrCast(&nop),
};

const wl_callback_listener = wl.Callback.Listener{
    .done = wlCallbackDone,
};

pub fn main() !void {
    var lwl = try std.DynLib.open("libwayland-client.so");
    defer lwl.close();

    try wl.load(&lwl);

    const display = wl.display_connect(null) orelse {
        log.err("wl_display_connect failed", .{});
        return error.UnexpectedWayland;
    };
    defer wl.display_disconnect(display);
    log.debug("Display connected", .{});

    const registry = display.get_registry() orelse {
        log.err("wl_display_get_registry failed", .{});
        return error.UnexpectedWayland;
    };
    registry.add_listener(&registry_listener, null);
    if (wl.display_roundtrip(display) == -1) {
        log.err("wl_display_roundtrip failed", .{});
        return error.UnexpectedWayland;
    }
    // registry.destroy();

    if (wl_shm == null) {
        log.err("wl_shm not available", .{});
        return error.UnexpectedWayland;
    }
    if (wl_compositor == null) {
        log.err("wl_compositor not available", .{});
        return error.UnexpectedWayland;
    }
    if (wl_seat == null) {
        log.err("wl_seat not available", .{});
        return error.UnexpectedWayland;
    }
    if (xdg_wm_base == null) {
        log.err("xdg_wm_base not available", .{});
        return error.UnexpectedWayland;
    }

    wl_surface = wl_compositor.?.create_surface() orelse {
        log.err("wl_compositor_create_surface failed", .{});
        return error.UnexpectedWayland;
    };
    defer wl_surface.destroy();
    log.debug("Surface created", .{});

    const xdg_surface = xdg_wm_base.?.get_xdg_surface(wl_surface) orelse {
        log.err("xdg_wm_base_get_xdg_surface failed", .{});
        return error.UnexpectedWayland;
    };
    defer xdg_surface.destroy();
    log.debug("Xdg surface created", .{});

    xdg_toplevel = xdg_surface.get_toplevel() orelse {
        log.err("xdg_surface_get_toplevel failed", .{});
        return error.UnexpectedWayland;
    };
    defer xdg_toplevel.destroy();
    log.debug("Xdg toplevel created", .{});

    xdg_surface.add_listener(&xdg_surface_listener, null);
    xdg_toplevel.add_listener(&xdg_toplevel_listener, null);

    wl_surface.commit();
    while (wl.display_dispatch(display) != -1 and !configured) {
        // block
    }
    log.debug("Initial config done", .{});

    wl_buffer = createBuffer();
    defer wl_buffer.destroy();
    log.debug("Buffer created", .{});

    wl_callback = wl_surface.frame() orelse {
        log.err("wl_surface_frame failed", .{});
        return error.UnexpectedWayland;
    };
    wl_callback.add_listener(&wl_callback_listener, null);

    wl_surface.attach(wl_buffer, 0, 0);
    wl_surface.commit();

    while (wl.display_dispatch(display) != -1 and running) {
        //
    }
}

fn createBuffer() *wl.Buffer {
    const stride = window_width * 4;
    const size: i64 = stride * window_height;

    shm_fd = alloc_shm(size);
    shm_size = size;

    const prot = std.c.PROT.READ | std.c.PROT.WRITE;
    const map = std.c.MAP{ .TYPE = .SHARED };
    const mapped = std.c.mmap(null, @intCast(size), prot, map, shm_fd, 0);
    if (mapped == std.c.MAP_FAILED) {
        // TODO: Better error handling
        unreachable;
    }
    shm_ptr = @ptrCast(mapped);

    const shm = wl_shm.?;
    wl_pool = shm.create_pool(shm_fd, @intCast(size)) orelse {
        log.err("wl_shm_create_pool failed", .{});
        // TODO: Better error handling
        unreachable;
    };

    const buffer = wl_pool.create_buffer(0, window_width, window_height, stride, .argb8888) orelse {
        log.err("wl_shm_pool_create_buffer failed", .{});
        // TODO: Better error handling
        unreachable;
    };

    return buffer;
}

fn alloc_shm(size: std.c.off_t) std.c.fd_t {
    // const S = std.posix.S;

    var name_buf: [16]u8 = undefined;
    name_buf[0] = '/';
    name_buf[name_buf.len - 1] = 0;

    for (name_buf[1 .. name_buf.len - 1]) |*char| {
        char.* = std.crypto.random.intRangeAtMost(u8, 'a', 'z');
    }
    const name: [*:0]u8 = @ptrCast(&name_buf);

    const open_flags = std.posix.O{ .ACCMODE = .RDWR, .CREAT = true, .EXCL = true };
    // const mode: std.c.mode_t = S.IWUSR | S.IRUSR | S.IWOTH | S.IROTH;

    // TODO: Check for shm_open error
    const fd = std.c.shm_open(name, @bitCast(open_flags), 600);
    if (fd >= 0) _ = std.c.shm_unlink(name);
    _ = std.c.ftruncate(fd, size);

    return fd;
}

fn wlRegGlobal(data: ?*anyopaque, registry_opt: ?*wl.Registry, name: u32, interface_name: [*:0]const u8, version: u32) callconv(.c) void {
    _ = data;

    const registry = registry_opt.?;
    const iface_name = std.mem.span(interface_name);

    if (std.mem.eql(u8, iface_name, std.mem.span(wl.Shm.interface.name))) {
        log.debug("Binding {s} version {}", .{ iface_name, version });
        wl_shm = registry.bind(name, wl.Shm, version) orelse @panic("Failed to bind wl_shm");
    } else if (std.mem.eql(u8, iface_name, std.mem.span(wl.Seat.interface.name))) {
        log.debug("Binding {s} version {}", .{ iface_name, version });
        const seat = registry.bind(name, wl.Seat, version) orelse @panic("Failed to bind wl_seat");
        seat.add_listener(&seat_listener, null);
        wl_seat = seat;
    } else if (std.mem.eql(u8, iface_name, std.mem.span(wl.Compositor.interface.name))) {
        log.debug("Binding {s} version {}", .{ iface_name, version });
        wl_compositor = registry.bind(name, wl.Compositor, version) orelse @panic("Failed to bind wl_compositor");
    } else if (std.mem.eql(u8, iface_name, std.mem.span(xdg.WmBase.interface.name))) {
        log.debug("Binding {s} version {}", .{ iface_name, version });
        xdg_wm_base = registry.bind(name, xdg.WmBase, version);
        if (xdg_wm_base) |base| base.add_listener(&xdg_wm_base_listener, null) else @panic("Failed to bind xdg_wm_base");
    }
}

fn wlRegGlobalRemove(data: ?*anyopaque, registry: ?*wl.Registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = name;
    unreachable;
}

fn wlSeatCapabilities(data: ?*anyopaque, seat_opt: ?*wl.Seat, capabilities: wl.Seat.Capability) callconv(.c) void {
    _ = data;
    log.debug("seat cap: {}", .{capabilities});

    if (capabilities.pointer) {
        const pointer = seat_opt.?.get_pointer();
        pointer.?.add_listener(&wl_pointer_listener, null);
    }
}

fn xdgWmBasePing(data: ?*anyopaque, base_opt: ?*xdg.WmBase, serial: u32) callconv(.c) void {
    _ = data;
    base_opt.?.pong(serial);
}

fn xdgSurfaceConfigure(data: ?*anyopaque, surface_opt: ?*xdg.Surface, serial: u32) callconv(.c) void {
    _ = data;

    surface_opt.?.ack_configure(serial);
    if (configured) {
        wl_surface.attach(wl_buffer, 0, 0);
        wl_surface.damage(0, 0, window_width, window_height);
        wl_surface.commit();
    }

    configured = true;
}

fn xdgToplevelConfigure(data: ?*anyopaque, toplevel_opt: ?*xdg.Toplevel, width: i32, height: i32, states: wayland.Array) callconv(.c) void {
    _ = data;
    _ = toplevel_opt;
    _ = states;

    if (width == 0 and height == 0) {
        xdg_toplevel.set_min_size(window_width, window_height);
        return;
    }

    const stride = width * 4;
    const new_size = stride * height;

    if (new_size > shm_size) {
        _ = std.c.munmap(@ptrCast(@alignCast(shm_ptr)), @intCast(shm_size));
        _ = std.c.ftruncate(shm_fd, new_size);
        shm_size = new_size;

        const prot = std.c.PROT.READ | std.c.PROT.WRITE;
        const map = std.c.MAP{ .TYPE = .SHARED };
        const mapped = std.c.mmap(null, @intCast(shm_size), prot, map, shm_fd, 0);
        if (mapped == std.c.MAP_FAILED) {

            // TODO: Better error handling
            unreachable;
        }
        shm_ptr = @ptrCast(mapped);

        wl_pool.resize(@intCast(shm_size));
    }

    wl_buffer.destroy();

    window_width = width;
    window_height = height;

    wl_buffer = wl_pool.create_buffer(0, width, height, stride, .argb8888) orelse unreachable;
}

fn xdgToplevelClose(data: ?*anyopaque, toplevel_opt: ?*xdg.Toplevel) callconv(.c) void {
    _ = data;
    _ = toplevel_opt;
    log.debug("xdg toplevel close", .{});
    running = false;
}

fn xdgToplevelConfigureBounds(data: ?*anyopaque, toplevel_opt: ?*xdg.Toplevel, width: i32, height: i32) callconv(.c) void {
    _ = data;
    _ = toplevel_opt;
    log.debug("xdg toplevel configure bounds: {},{}", .{ width, height });
}

fn xdgToplevelWmCapabilities(data: ?*anyopaque, toplevel_opt: ?*xdg.Toplevel, capabilities: wayland.Array) callconv(.c) void {
    _ = data;
    _ = toplevel_opt;
    log.debug("xdg toplevel wm capabilities", .{});
    log.debug("\tcap.size: {}, cap.alloc: {}", .{ capabilities.size, capabilities.alloc });
}

fn wlPointerButton(data: ?*anyopaque, pointer_opt: ?*wl.Pointer, serial: u32, time: u32, button: u32, state: wl.Pointer.ButtonState) callconv(.c) void {
    _ = time;
    _ = data;
    _ = pointer_opt;

    if (button == c.BTN_LEFT and state == .pressed) {
        xdg_toplevel.move(wl_seat, serial);
    }
}

const Pixel = extern struct {
    b: u8,
    g: u8,
    r: u8,
    a: u8,
};

fn wlCallbackDone(data: ?*anyopaque, callback: ?*wl.Callback, callback_data: u32) callconv(.c) void {
    _ = data;
    _ = callback_data;

    const next_callback = wl_surface.frame() orelse @panic("wl_surface_frame failed");
    next_callback.add_listener(&wl_callback_listener, null);

    linuxUpdateWindow();
    callback.?.destroy();
}

fn linuxUpdateWindow() void {
    const pixels: []Pixel = @as([*]Pixel, @ptrCast(shm_ptr))[0..@intCast(window_width * window_height)];
    @memset(pixels, Pixel{ .r = 0, .g = 0, .b = 0, .a = 255 });

    const w: usize = @intCast(window_width);
    const h: usize = @intCast(window_height);

    for (0..w) |x| {
        for (0..h) |y| {
            if (x > 10 and x < 110 and y > 10 and y < 110) {
                pixels[(w * y) + x] = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
            }
        }
    }

    wl_surface.attach(wl_buffer, 0, 0);
    wl_surface.commit();
}

fn nop() callconv(.c) void {}
