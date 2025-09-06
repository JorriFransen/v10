const std = @import("std");
const log = std.log.scoped(.linux_v10);
const wayland = @import("wayland");
const wl = wayland.wl;
const xdg = wayland.xdg_shell;

const c = @cImport({
    @cInclude("linux/input-event-codes.h");
});

const assert = std.debug.assert;

var initial_window_width: i32 = 800;
var initial_window_height: i32 = 600;

const WlInitData = struct {
    wl_shm: ?*wl.Shm = null,
    wl_compositor: ?*wl.Compositor = null,
    wl_seat: ?*wl.Seat = null,
    xdg_wm_base: ?*xdg.WmBase = null,

    argb8888: bool = false,
    seat_capabilities: wl.Seat.Capability = .{},
};

const Pixel = extern struct {
    b: u8,
    g: u8,
    r: u8,
    a: u8 = 255,
};

const WlData = struct {
    running: bool = true,
    should_draw: bool = false,

    display: *wl.Display = undefined,
    shm: *wl.Shm = undefined,
    compositor: *wl.Compositor = undefined,
    seat: *wl.Seat = undefined,
    surface: *wl.Surface = undefined,
    wm_base: *xdg.WmBase = undefined,
    xdg_surface: *xdg.Surface = undefined,
    toplevel: *xdg.Toplevel = undefined,
    keyboard: *wl.Keyboard = undefined,

    width: i32 = -1,
    height: i32 = -1,
    bound_width: i32 = undefined,
    bound_height: i32 = undefined,

    pool: *wl.ShmPool = undefined,
    buffer: ?*wl.Buffer = null,
    shm_ptr: [*]u8 = undefined,

    pending_resize: ?PendingResize = null,
};

const PendingResize = struct {
    width: i32,
    height: i32,
    serial: u32,
};

var wl_registry_listener = wl.Registry.Listener{
    .global = handleWlRegisterGlobal,
    .global_remove = handleWlRemoveGlobal,
};

var wl_shm_listener = wl.Shm.Listener{
    .format = handleWlShmFormat,
};

var wl_surface_listener = wl.Surface.Listener{
    .enter = @ptrCast(&nop),
    .leave = @ptrCast(&nop),
    .preferred_buffer_scale = @ptrCast(&nop),
    .preferred_buffer_transform = @ptrCast(&nop),
};

var xdg_wm_base_listener = xdg.WmBase.Listener{
    .ping = handleXdgPing,
};

var xdg_surface_listener = xdg.Surface.Listener{
    .configure = handleXdgSurfaceConfigure,
};

var xdg_toplevel_listener = xdg.Toplevel.Listener{
    .configure = handleXdgToplevelConfigure,
    .configure_bounds = handleXdgToplevelConfigureBounds,
    .wm_capabilities = handleXdgToplevelWmCapabilities,
    .close = handleXdgToplevelClose,
};

var wl_callback_listener = wl.Callback.Listener{
    .done = handleWlCallbackDone,
};

var wl_buffer_listener = wl.Buffer.Listener{
    .release = handleWlBufferRelease,
};

var wl_seat_listener = wl.Seat.Listener{
    .capabilities = handleWlSeatCapabilities,
    .name = @ptrCast(&nop),
};

var wl_keyboard_listener = wl.Keyboard.Listener{
    .key = handleWlKey,
    .enter = @ptrCast(&nop),
    .leave = @ptrCast(&nop),
    .modifiers = @ptrCast(&nop),
    .repeat_info = @ptrCast(&nop),
    .keymap = @ptrCast(&nop),
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

    const wl_registry = display.get_registry() orelse {
        log.err("wl_display_get_registry failed", .{});
        return error.UnexpectedWayland;
    };

    var wli = WlInitData{};
    wl_registry.add_listener(&wl_registry_listener, &wli);
    if (wl.display_roundtrip(display) == -1) {
        log.err("wl_display_roundtrip failed", .{});
        return error.UnexpectedWayland;
    }
    defer wl_registry.destroy();

    var wld: WlData = .{
        .running = true,
        .display = display,
    };

    if (wli.wl_shm) |shm| wld.shm = shm else {
        log.err("wl_shm not available", .{});
        return error.UnexpectedWayland;
    }
    if (wli.wl_compositor) |compositor| wld.compositor = compositor else {
        log.err("wl_compositor not available", .{});
        return error.UnexpectedWayland;
    }
    if (wli.wl_seat) |seat| wld.seat = seat else {
        log.err("wl_seat not available", .{});
        return error.UnexpectedWayland;
    }
    if (wli.xdg_wm_base) |wm_base| wld.wm_base = wm_base else {
        log.err("xdg_wm_base not available", .{});
        return error.UnexpectedWayland;
    }

    // for format events, seat
    wld.shm.add_listener(&wl_shm_listener, &wli);
    wld.seat.add_listener(&wl_seat_listener, &wli);
    _ = wl.display_roundtrip(display);
    log.debug("Format available", .{});
    log.debug("Seat capabilities: {}", .{wli.seat_capabilities});

    if (wli.seat_capabilities.keyboard == false) {
        log.debug("keyboard not available", .{});
        return error.UnexpectedWayland;
    }
    if (wli.seat_capabilities.pointer == false) {
        log.debug("mouse not available", .{});
        return error.UnexpectedWayland;
    }

    wld.keyboard = wld.seat.get_keyboard() orelse {
        log.debug("wl_seat_get_keyboard failed", .{});
        return error.UnexpectedWayland;
    };

    wld.keyboard.add_listener(&wl_keyboard_listener, &wld);

    if (wli.argb8888 == false) {
        log.err("argb8888 format not avaliable", .{});
        return error.UnexpectedWayland;
    }

    wld.wm_base.add_listener(&xdg_wm_base_listener, null);

    wld.surface = wld.compositor.create_surface() orelse {
        log.err("wl_compositor_create_surface failed", .{});
        return error.UnexpectedWayland;
    };
    wld.surface.add_listener(&wl_surface_listener, null);

    wld.xdg_surface = wld.wm_base.get_xdg_surface(wld.surface) orelse {
        log.err("xdg_wm_base_get_xdg_surface failed", .{});
        return error.UnexpectedWayland;
    };
    wld.xdg_surface.add_listener(&xdg_surface_listener, &wld);

    wld.toplevel = wld.xdg_surface.get_toplevel() orelse {
        log.err("xdg_surface_get_top_level failed", .{});
        return error.UnexpectedWayland;
    };
    wld.toplevel.add_listener(&xdg_toplevel_listener, &wld);
    wld.toplevel.set_min_size(initial_window_width, initial_window_height);
    wld.toplevel.set_app_id("v10");
    wld.toplevel.set_title("v10");

    wld.surface.commit();

    while (wld.pending_resize == null) {
        if (wl.display_dispatch(display) == -1) {
            log.debug("wl_display_dispatch failed", .{});
            return error.UnexpectedWayland;
        }
    }
    resize(&wld, wld.pending_resize.?);
    log.debug("Initial config done", .{});

    while (wl.display_dispatch(display) != -1 and wld.running) {
        if (wld.pending_resize) |r| {
            if (r.serial != 0) {
                resize(&wld, r);
            }
        }

        if (wld.should_draw) {
            draw(wld.shm_ptr, wld.width, wld.height);

            wld.surface.attach(wld.buffer, 0, 0);
            wld.surface.damage(0, 0, wld.width, wld.height);
            wld.surface.commit();
            const callback = wld.surface.frame();
            callback.?.add_listener(&wl_callback_listener, &wld);
            _ = wl.display_flush(display);
            wld.should_draw = false;
        }

        _ = wl.display_flush(display);
    }
}

fn resize(wld: *WlData, r: PendingResize) void {
    if (r.width == wld.width and r.height == wld.height) {
        wld.xdg_surface.ack_configure(r.serial);
        wld.surface.commit();
        wld.pending_resize = null;
        return;
    }

    if (wld.buffer) |buffer| {
        buffer.destroy();
        wld.pool.destroy();
        const old_size = @as(usize, @intCast(wld.width * wld.height)) * @sizeOf(Pixel);
        _ = std.c.munmap(@ptrCast(@alignCast(wld.shm_ptr)), old_size);
    }

    if (r.width == 0 and r.height == 0) {
        wld.width = initial_window_width;
        wld.height = initial_window_height;
    } else {
        wld.width = r.width;
        wld.height = r.height;
    }

    const stride = wld.width * @sizeOf(Pixel);
    const new_size = stride * wld.height;

    const fd = alloc_shm(new_size);
    defer _ = std.c.close(fd);

    const prot = std.c.PROT.READ | std.c.PROT.WRITE;
    const map = std.c.MAP{ .TYPE = .SHARED };
    const mapped = std.c.mmap(null, @intCast(new_size), prot, map, fd, 0);
    if (mapped == std.c.MAP_FAILED) {
        // TODO: Better error handling
        unreachable;
    }
    wld.shm_ptr = @ptrCast(mapped);

    wld.pool = wld.shm.create_pool(fd, new_size) orelse {
        log.err("wl_shm_create_pool_failed", .{});
        unreachable;
    };

    const buffer = wld.pool.create_buffer(0, wld.width, wld.height, stride, .argb8888) orelse {
        log.err("wl_pool_create_buffer_failed", .{});
        unreachable;
    };
    buffer.add_listener(&wl_buffer_listener, wld);
    wld.buffer = buffer;

    draw(wld.shm_ptr, wld.width, wld.height);

    wld.xdg_surface.ack_configure(r.serial);
    wld.surface.attach(wld.buffer, 0, 0);
    wld.surface.damage(0, 0, wld.width, wld.height);
    wld.surface.commit();
    const callback = wld.surface.frame();
    callback.?.add_listener(&wl_callback_listener, wld);
    _ = wl.display_flush(wld.display);
    wld.pending_resize = null;
}

fn alloc_shm(size: std.c.off_t) std.c.fd_t {
    const S = std.posix.S;

    var name_buf: [16]u8 = undefined;
    name_buf[0] = '/';
    name_buf[name_buf.len - 1] = 0;

    for (name_buf[1 .. name_buf.len - 1]) |*char| {
        char.* = std.crypto.random.intRangeAtMost(u8, 'a', 'z');
    }
    const name: [*:0]u8 = @ptrCast(&name_buf);

    const open_flags = std.posix.O{ .ACCMODE = .RDWR, .CREAT = true, .EXCL = true };
    const mode: std.c.mode_t = S.IWUSR | S.IRUSR | S.IWOTH | S.IROTH;
    // TODO: Check for shm_open error
    const fd = std.c.shm_open(name, @bitCast(open_flags), mode);
    if (fd >= 0) _ = std.c.shm_unlink(name);
    _ = std.c.ftruncate(fd, size);

    return fd;
}

fn handleWlRegisterGlobal(data: ?*anyopaque, registry_opt: ?*wl.Registry, name: u32, interface_name: [*:0]const u8, version: u32) callconv(.c) void {
    const wli: *WlInitData = @ptrCast(@alignCast(data));
    const registry = registry_opt.?;
    const iface_name = std.mem.span(interface_name);

    if (std.mem.eql(u8, iface_name, std.mem.span(wl.Shm.interface.name))) {
        log.debug("Binding {s} version {}", .{ iface_name, version });
        wli.wl_shm = registry.bind(name, wl.Shm, version) orelse @panic("Failed to bind wl_shm");
    } else if (std.mem.eql(u8, iface_name, std.mem.span(wl.Seat.interface.name))) {
        log.debug("Binding {s} version {}", .{ iface_name, version });
        wli.wl_seat = registry.bind(name, wl.Seat, version) orelse @panic("Failed to bind wl_seat");
    } else if (std.mem.eql(u8, iface_name, std.mem.span(wl.Compositor.interface.name))) {
        log.debug("Binding {s} version {}", .{ iface_name, version });
        wli.wl_compositor = registry.bind(name, wl.Compositor, version) orelse @panic("Failed to bind wl_compositor");
    } else if (std.mem.eql(u8, iface_name, std.mem.span(xdg.WmBase.interface.name))) {
        log.debug("Binding {s} version {}", .{ iface_name, version });
        wli.xdg_wm_base = registry.bind(name, xdg.WmBase, version);
    }
}

fn handleWlRemoveGlobal(data: ?*anyopaque, registry: ?*wl.Registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = name;
    unreachable;
}

fn handleWlShmFormat(data: ?*anyopaque, shm: ?*wl.Shm, format: wl.Shm.Format) callconv(.c) void {
    _ = shm;

    const wli: *WlInitData = @ptrCast(@alignCast(data));
    if (format == .argb8888) wli.argb8888 = true;
}

fn handleXdgPing(data: ?*anyopaque, wm_base: ?*xdg.WmBase, serial: u32) callconv(.c) void {
    _ = data;
    wm_base.?.pong(serial);
}

fn handleXdgSurfaceConfigure(data: ?*anyopaque, surface: ?*xdg.Surface, serial: u32) callconv(.c) void {
    const wld: *WlData = @ptrCast(@alignCast(data));
    if (wld.pending_resize) |*r| {
        r.serial = serial;
    } else {
        log.warn("xdg surface configure without pending resize from toplevel", .{});
        surface.?.ack_configure(serial);
    }
}

fn handleXdgToplevelConfigure(data: ?*anyopaque, toplevel: ?*xdg.Toplevel, width: i32, height: i32, states: wayland.Array) callconv(.c) void {
    _ = toplevel;
    _ = states;

    log.debug("toplevel configure: {},{}", .{ width, height });

    const wld: *WlData = @ptrCast(@alignCast(data));

    if (wld.pending_resize) |*r| {
        r.width = width;
        r.height = height;
    } else {
        wld.pending_resize = .{
            .width = width,
            .height = height,
            .serial = 0,
        };
    }
}

fn handleXdgToplevelConfigureBounds(data: ?*anyopaque, toplevel: ?*xdg.Toplevel, width: i32, height: i32) callconv(.c) void {
    _ = toplevel;

    const wld: *WlData = @ptrCast(@alignCast(data));
    wld.bound_width = width;
    wld.bound_height = height;
    log.debug("xdg toplevel configure bounds {},{}", .{ width, height });
}

fn handleXdgToplevelWmCapabilities(data: ?*anyopaque, toplevel: ?*xdg.Toplevel, capabilities: wayland.Array) callconv(.c) void {
    _ = data;
    _ = toplevel;
    log.debug("xdg toplevel capabilities count {}", .{capabilities.size});
}

fn handleXdgToplevelClose(data: ?*anyopaque, toplevel: ?*xdg.Toplevel) callconv(.c) void {
    _ = toplevel;

    const wld: *WlData = @ptrCast(@alignCast(data));
    wld.running = false;
    log.debug("xdg toplevel close", .{});
}

fn handleWlCallbackDone(data: ?*anyopaque, callback: ?*wl.Callback, callback_data: u32) callconv(.c) void {
    _ = callback_data;
    callback.?.destroy();

    log.debug("frame callback", .{});
    const wld: *WlData = @ptrCast(@alignCast(data));
    wld.should_draw = true;
}

fn handleWlBufferRelease(data: ?*anyopaque, buffer: ?*wl.Buffer) callconv(.c) void {
    _ = data;
    _ = buffer;
    log.debug("Buffer release", .{});
    unreachable;
}

fn handleWlSeatCapabilities(data: ?*anyopaque, seat: ?*wl.Seat, capabilities: wl.Seat.Capability) callconv(.c) void {
    _ = seat;

    const wli: *WlInitData = @ptrCast(@alignCast(data));
    wli.seat_capabilities = capabilities;
}

fn handleWlKey(data: ?*anyopaque, keyboard: ?*wl.Keyboard, serial: u32, time: u32, key: u32, state: wl.Keyboard.KeyState) callconv(.c) void {
    _ = keyboard;
    _ = time;
    _ = serial;
    _ = state;

    const wld: *WlData = @ptrCast(@alignCast(data));

    // TODO: Do this via the keymap with xkb!
    // 1 = esc, 58 = caps
    if (key == 1 or key == 58) {
        wld.running = false;
    }
}

var ry: usize = 0;
fn draw(buffer: [*]u8, width: i32, height: i32) void {
    const pixels = @as([*]Pixel, @ptrCast(buffer))[0..@intCast(width * height)];
    @memset(pixels, .{ .r = 0, .g = 0, .b = 0, .a = 255 });

    const w: usize = @intCast(width);
    const h: usize = @intCast(height);

    for (10..110) |x| {
        for (ry..ry + 100) |y| {
            pixels[x + (y * w)] = .{ .r = 255, .g = 0, .b = 0 };
        }
    }

    for (w - 110..w - 10) |x| {
        for (h - 110..h - 10) |y| {
            pixels[x + (y * w)] = .{ .r = 0, .g = 255, .b = 0 };
        }
    }

    // TODO: This should not be in draw!
    ry += 1;
}

fn nop() callconv(.c) void {}
