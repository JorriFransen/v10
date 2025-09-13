const std = @import("std");
const log = std.log.scoped(.linux_v10);
const wayland = @import("wayland");
const wl = wayland.wl;
const xdg_shell = wayland.xdg_shell;
const xdg_decoration = wayland.xdg_decoration_unstable_v1;

// TODO: Check if preferred_buffer_scale is relevant
// TODO: Fix crash when disconnecting external display (maybe just unreachable in handler)

const assert = std.debug.assert;

const c = @cImport({
    @cInclude("libdecor.h");
});

const initial_window_width: i32 = 800;
const initial_window_height: i32 = 600;

const WlInitData = struct {
    wl_shm: ?*wl.Shm = null,
    wl_compositor: ?*wl.Compositor = null,
    wl_seat: ?*wl.Seat = null,
    xdg_wm_base: ?*xdg_shell.WmBase = null,
    xdg_decoration_manager: ?*xdg_decoration.DecorationManagerV1 = null,

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

    free_buffers: u8 = 0,
    buffer_index: usize = 0,
    pool: *wl.ShmPool = undefined,
    buffers: ?[2]*wl.Buffer = null,
    buffer_data: [2][*]u8 = undefined,

    display: *wl.Display = undefined,
    shm: *wl.Shm = undefined,
    compositor: *wl.Compositor = undefined,
    seat: *wl.Seat = undefined,
    surface: *wl.Surface = undefined,
    wm_base: *xdg_shell.WmBase = undefined,
    keyboard: *wl.Keyboard = undefined,

    toplevel: Toplevel = undefined,

    width: i32 = -1,
    height: i32 = -1,
    bound_width: i32 = undefined,
    bound_height: i32 = undefined,

    pending_resize: ?PendingResize = null,
};

const Toplevel = union(enum) {
    default: struct {
        xdg_surface: *xdg_shell.Surface,
        xdg_toplevel: *xdg_shell.Toplevel,
    },

    xdg_decoration: struct {
        xdg_surface: *xdg_shell.Surface,
        xdg_toplevel: *xdg_shell.Toplevel,
        xdg_toplevel_decoration: *xdg_decoration.ToplevelDecorationV1,
        supports_ssd: bool,
    },

    libdecor: struct {
        decor: *c.libdecor,
        frame: *c.libdecor_frame,
    },

    fn set_app_id(this: Toplevel, id: [*:0]const u8) void {
        switch (this) {
            .default => |d| d.xdg_toplevel.set_app_id(id),
            .xdg_decoration => |d| d.xdg_toplevel.set_app_id(id),
            .libdecor => |d| c.libdecor_frame_set_app_id(d.frame, id),
        }
    }

    fn set_title(this: Toplevel, id: [*:0]const u8) void {
        switch (this) {
            .default => |n| n.xdg_toplevel.set_title(id),
            .xdg_decoration => |n| n.xdg_toplevel.set_title(id),
            .libdecor => |d| c.libdecor_frame_set_title(d.frame, id),
        }
    }
};

const PendingResize = struct {
    width: i32,
    height: i32,
};

const wl_registry_listener = wl.Registry.Listener{
    .global = handleWlRegisterGlobal,
    .global_remove = handleWlRemoveGlobal,
};

const wl_shm_listener = wl.Shm.Listener{
    .format = handleWlShmFormat,
};

const wl_surface_listener = wl.Surface.Listener{
    .enter = @ptrCast(&nop),
    .leave = @ptrCast(&nop),
    .preferred_buffer_scale = @ptrCast(&nop),
    .preferred_buffer_transform = @ptrCast(&nop),
};

const xdg_wm_base_listener = xdg_shell.WmBase.Listener{
    .ping = handleXdgPing,
};

const xdg_surface_listener = xdg_shell.Surface.Listener{
    .configure = handleXdgSurfaceConfigure,
};

const xdg_toplevel_listener = xdg_shell.Toplevel.Listener{
    .configure = handleXdgToplevelConfigure,
    .configure_bounds = handleXdgToplevelConfigureBounds,
    .wm_capabilities = handleXdgToplevelWmCapabilities,
    .close = handleXdgToplevelClose,
};

const wl_callback_listener = wl.Callback.Listener{
    .done = handleWlCallbackDone,
};

const wl_buffer_listener = wl.Buffer.Listener{
    .release = handleWlBufferRelease,
};

const wl_seat_listener = wl.Seat.Listener{
    .capabilities = handleWlSeatCapabilities,
    .name = @ptrCast(&nop),
};

const wl_keyboard_listener = wl.Keyboard.Listener{
    .key = handleWlKey,
    .enter = @ptrCast(&nop),
    .leave = @ptrCast(&nop),
    .modifiers = @ptrCast(&nop),
    .repeat_info = @ptrCast(&nop),
    .keymap = @ptrCast(&nop),
};

const libdecor_listener = c.libdecor_frame_interface{
    .configure = handleLibdecorConfigure,
    .commit = @ptrCast(&nop), // This should be safe to ignore, since we continuously redraw
    .close = handleLibdecorClose,
    .dismiss_popup = handleLibdecorDismissPopup,
};

const xdg_decoration_listener = xdg_decoration.ToplevelDecorationV1.Listener{
    .configure = handleXdgDecorationConfigure,
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

    // wld.toplevel = switch (toplevel_type) {
    //     .default => blk: {
    //         const xdg_surface = wld.wm_base.get_xdg_surface(wld.surface) orelse {
    //             log.err("xdg_wm_base_get_xdg_surface failed", .{});
    //             return error.UnexpectedWayland;
    //         };
    //         xdg_surface.add_listener(&xdg_surface_listener, &wld);
    //
    //         const toplevel = xdg_surface.get_toplevel() orelse {
    //             log.err("xdg_surface_get_top_level failed", .{});
    //             return error.UnexpectedWayland;
    //         };
    //         toplevel.add_listener(&xdg_toplevel_listener, &wld);
    //
    //         wld.surface.commit();
    //         _ = wl.display_roundtrip(display);
    //         assert(wld.pending_resize != null);
    //         const r = wld.pending_resize.?;
    //         try resize(&wld, r.width, r.height);
    //         draw(&wld);
    //
    //         break :blk .{ .default = .{ .xdg_surface = xdg_surface, .xdg_toplevel = toplevel } };
    //     },
    //
    //     .xdg_decoration => blk: {
    //         const xdg_surface = wld.wm_base.get_xdg_surface(wld.surface) orelse {
    //             log.err("xdg_wm_base_get_xdg_surface failed", .{});
    //             return error.UnexpectedWayland;
    //         };
    //         xdg_surface.add_listener(&xdg_surface_listener, &wld);
    //
    //         const toplevel = xdg_surface.get_toplevel() orelse {
    //             log.err("xdg_surface_get_top_level failed", .{});
    //             return error.UnexpectedWayland;
    //         };
    //         toplevel.add_listener(&xdg_toplevel_listener, &wld);
    //
    //         const toplevel_decoration = wli.xdg_decoration_manager.?.get_toplevel_decoration(toplevel) orelse {
    //             log.err("zxdg_decoration_manager_v1_get_toplevel_decoration failed", .{});
    //             return error.UnexpectedWayland;
    //         };
    //         toplevel_decoration.set_mode(.server_side);
    //
    //         var mode: xdg_decoration.ToplevelDecorationV1.Mode = undefined;
    //         toplevel_decoration.add_listener(&xdg_decoration_listener, &mode);
    //
    //         wld.surface.commit();
    //         _ = wl.display_roundtrip(display);
    //         assert(wld.pending_resize != null);
    //         const r = wld.pending_resize.?;
    //         try resize(&wld, r.width, r.height);
    //         draw(&wld);
    //
    //         break :blk .{
    //             .xdg_decoration = .{
    //                 .xdg_surface = xdg_surface,
    //                 .xdg_toplevel = toplevel,
    //                 .xdg_toplevel_decoration = toplevel_decoration,
    //             },
    //         };
    //     },
    //     .libdecor => blk: {
    //         const libdecor = c.libdecor_new(@ptrCast(display), null) orelse {
    //             log.err("libdecor_new failed", .{});
    //             return error.UnexpectedLibDecor;
    //         };
    //
    //         const frame = c.libdecor_decorate(libdecor, @ptrCast(wld.surface), &libdecor_listener, &wld) orelse {
    //             log.err("libdecor decorate failed", .{});
    //             return error.UnexpectedLibDecor;
    //         };
    //
    //         wld.surface.commit();
    //
    //         break :blk .{ .libdecor = .{ .decor = libdecor, .frame = frame } };
    //     },
    // };

    var xdg_decor_toplevel: Toplevel = undefined;
    if (wli.xdg_decoration_manager) |manager| {
        const xdg_surface = wld.wm_base.get_xdg_surface(wld.surface) orelse {
            log.err("xdg_wm_base_get_xdg_surface failed", .{});
            return error.UnexpectedWayland;
        };
        xdg_surface.add_listener(&xdg_surface_listener, &wld);

        const xdg_toplevel = xdg_surface.get_toplevel() orelse {
            log.err("xdg_surface_get_top_level failed", .{});
            return error.UnexpectedWayland;
        };
        xdg_toplevel.add_listener(&xdg_toplevel_listener, &wld);

        const toplevel_decoration = manager.get_toplevel_decoration(xdg_toplevel) orelse {
            log.err("zxdg_decoration_manager_v1_get_toplevel_decoration failed", .{});
            return error.UnexpectedWayland;
        };
        toplevel_decoration.set_mode(.server_side);

        var mode: xdg_decoration.ToplevelDecorationV1.Mode = undefined;
        toplevel_decoration.add_listener(&xdg_decoration_listener, &mode);

        wld.surface.commit();
        _ = wl.display_roundtrip(display);

        if (mode == .server_side) {
            log.debug("Using xdg_decoration", .{});
            assert(wld.pending_resize != null);
            const r = wld.pending_resize.?;
            try resize(&wld, r.width, r.height);
            draw(&wld);
        }

        xdg_decor_toplevel = .{
            .xdg_decoration = .{
                .xdg_surface = xdg_surface,
                .xdg_toplevel = xdg_toplevel,
                .xdg_toplevel_decoration = toplevel_decoration,
                .supports_ssd = mode == .server_side,
            },
        };
    }

    const use_xdg_decoration = wli.xdg_decoration_manager != null and
        xdg_decor_toplevel.xdg_decoration.supports_ssd;

    wld.toplevel = if (use_xdg_decoration) xdg_decor_toplevel else blk: {
        // TODO: Runtime load libdecor, fallback to no decorations
        log.debug("xdg_decoration not supported, falling back to libdecor", .{});

        // TODO: Only do this if libdecor is available, "no decorations" still need this
        if (wli.xdg_decoration_manager != null) {
            xdg_decor_toplevel.xdg_decoration.xdg_toplevel_decoration.destroy();
            xdg_decor_toplevel.xdg_decoration.xdg_toplevel.destroy();
            xdg_decor_toplevel.xdg_decoration.xdg_surface.destroy();
        }

        const libdecor = c.libdecor_new(@ptrCast(display), null) orelse {
            log.err("libdecor_new failed", .{});
            return error.UnexpectedLibDecor;
        };

        const frame = c.libdecor_decorate(libdecor, @ptrCast(wld.surface), @ptrCast(@constCast(&libdecor_listener)), &wld) orelse {
            log.err("libdecor decorate failed", .{});
            return error.UnexpectedLibDecor;
        };

        wld.surface.commit();

        break :blk .{ .libdecor = .{ .decor = libdecor, .frame = frame } };
    };

    wld.toplevel.set_app_id("v10");
    wld.toplevel.set_title("v10");

    while (wl.display_dispatch(display) != -1 and wld.running) {
        if (wld.pending_resize) |r| {
            try resize(&wld, r.width, r.height);
        }

        if (wld.should_draw and wld.free_buffers > 0) {
            draw(&wld);

            wld.should_draw = false;
        }

        _ = wl.display_flush(display);
    }
}

const ResizeError =
    PosixShmError ||
    error{
        MmapFailed,
        WlShmCreatePoolFailed,
        WlPoolCreateBufferFailed,
    };

fn resize(wld: *WlData, width: i32, height: i32) ResizeError!void {
    if (!(width == wld.width and height == wld.height)) {
        if (wld.buffers) |buffers| {
            const old_size = @as(usize, @intCast(wld.width * wld.height)) * @sizeOf(Pixel);
            _ = std.c.munmap(@ptrCast(@alignCast(wld.buffer_data[0])), old_size * 2);
            for (buffers) |buffer| {
                buffer.destroy();
            }

            wld.pool.destroy();
        }

        if (width == 0 and height == 0) {
            wld.width = initial_window_width;
            wld.height = initial_window_height;
        } else {
            wld.width = width;
            wld.height = height;
        }

        const stride = wld.width * @sizeOf(Pixel);
        const buffer_size = stride * wld.height;
        const new_size = buffer_size * 2;

        const fd = try alloc_shm(new_size);
        defer _ = std.c.close(fd);

        const prot = std.c.PROT.READ | std.c.PROT.WRITE;
        const map = std.c.MAP{ .TYPE = .SHARED };
        const mapped = std.c.mmap(null, @intCast(new_size), prot, map, fd, 0);
        if (mapped == std.c.MAP_FAILED) {
            log.err("mmap call failed during buffer resize", .{});
            return error.MmapFailed;
        }
        wld.buffer_data[0] = @ptrCast(mapped);
        wld.buffer_data[1] = @ptrCast(@as([*]u8, @ptrCast(mapped)) + @as(usize, @intCast(buffer_size)));

        wld.pool = wld.shm.create_pool(fd, new_size) orelse {
            log.err("wl_shm_create_pool_failed", .{});
            return error.WlShmCreatePoolFailed;
        };

        var buffers: [2]*wl.Buffer = undefined;
        buffers[0] = wld.pool.create_buffer(0, wld.width, wld.height, stride, .argb8888) orelse {
            log.err("wl_pool_create_buffer_failed", .{});
            return error.WlPoolCreateBufferFailed;
        };
        buffers[0].add_listener(&wl_buffer_listener, wld);

        buffers[1] = wld.pool.create_buffer(buffer_size, wld.width, wld.height, stride, .argb8888) orelse {
            log.err("wl_pool_create_buffer_failed", .{});
            return error.WlPoolCreateBufferFailed;
        };
        buffers[1].add_listener(&wl_buffer_listener, wld);

        wld.free_buffers = 2;
        wld.buffers = buffers;
    }

    wld.should_draw = true;
    wld.pending_resize = null;
}

const PosixShmError = error{
    ShmOpenFailed,
    ShmUnlinkFailed,
    FtruncateFailed,
};

fn alloc_shm(size: std.c.off_t) PosixShmError!std.c.fd_t {
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
    if (fd < 0) {
        log.err("shm_open failed, errno: {}", .{std.posix.errno(fd)});
        return error.ShmOpenFailed;
    }

    if (std.c.shm_unlink(name) != 0) {
        log.err("shm_unlink failed, errno: {}", .{std.posix.errno(-1)});
        return error.ShmUnlinkFailed;
    }

    if (std.c.ftruncate(fd, size) != 0) {
        log.err("ftruncate failed, errno: {}", .{std.posix.errno(-1)});
        return error.FtruncateFailed;
    }

    return fd;
}

fn handleWlRegisterGlobal(data: ?*anyopaque, registry_opt: ?*wl.Registry, name: u32, interface_name: [*:0]const u8, version: u32) callconv(.c) void {
    const wli: *WlInitData = @ptrCast(@alignCast(data));
    const registry = registry_opt.?;

    const eq = struct {
        pub inline fn eq(a: [*:0]const u8, b: anytype) bool {
            return std.mem.eql(u8, std.mem.span(a), std.mem.span(b.interface.name));
        }
    }.eq;

    if (eq(interface_name, wl.Shm)) {
        wli.wl_shm = registry.bind(name, wl.Shm, version);
    } else if (eq(interface_name, wl.Seat)) {
        wli.wl_seat = registry.bind(name, wl.Seat, version);
    } else if (eq(interface_name, wl.Compositor)) {
        wli.wl_compositor = registry.bind(name, wl.Compositor, version);
    } else if (eq(interface_name, xdg_shell.WmBase)) {
        wli.xdg_wm_base = registry.bind(name, xdg_shell.WmBase, version);
    } else if (eq(interface_name, xdg_decoration.DecorationManagerV1)) {
        wli.xdg_decoration_manager = registry.bind(name, xdg_decoration.DecorationManagerV1, version);
    }
}

fn handleWlRemoveGlobal(data: ?*anyopaque, registry: ?*wl.Registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = name;
    // unreachable;
}

fn handleWlShmFormat(data: ?*anyopaque, shm: ?*wl.Shm, format: wl.Shm.Format) callconv(.c) void {
    _ = shm;

    const wli: *WlInitData = @ptrCast(@alignCast(data));
    if (format == .argb8888) wli.argb8888 = true;
}

fn handleXdgPing(data: ?*anyopaque, wm_base: ?*xdg_shell.WmBase, serial: u32) callconv(.c) void {
    _ = data;
    wm_base.?.pong(serial);
}

fn handleXdgSurfaceConfigure(data: ?*anyopaque, surface: ?*xdg_shell.Surface, serial: u32) callconv(.c) void {
    _ = data;
    surface.?.ack_configure(serial);
}

fn handleXdgToplevelConfigure(data: ?*anyopaque, toplevel: ?*xdg_shell.Toplevel, width: i32, height: i32, states: wayland.Array) callconv(.c) void {
    _ = toplevel;
    _ = states;

    const wld: *WlData = @ptrCast(@alignCast(data));

    if (wld.pending_resize) |*r| {
        r.width = width;
        r.height = height;
    } else {
        wld.pending_resize = .{
            .width = width,
            .height = height,
        };
    }
}

fn handleXdgToplevelConfigureBounds(data: ?*anyopaque, toplevel: ?*xdg_shell.Toplevel, width: i32, height: i32) callconv(.c) void {
    _ = toplevel;

    const wld: *WlData = @ptrCast(@alignCast(data));
    wld.bound_width = width;
    wld.bound_height = height;
    log.debug("xdg toplevel configure bounds {},{}", .{ width, height });
}

fn handleXdgToplevelWmCapabilities(data: ?*anyopaque, toplevel: ?*xdg_shell.Toplevel, capabilities: wayland.Array) callconv(.c) void {
    _ = data;
    _ = toplevel;
    log.debug("xdg toplevel capabilities count {}", .{capabilities.size});
}

fn handleXdgToplevelClose(data: ?*anyopaque, toplevel: ?*xdg_shell.Toplevel) callconv(.c) void {
    _ = toplevel;

    const wld: *WlData = @ptrCast(@alignCast(data));
    wld.running = false;
}

fn handleWlCallbackDone(data: ?*anyopaque, callback: ?*wl.Callback, callback_data: u32) callconv(.c) void {
    _ = callback_data;
    callback.?.destroy();

    const wld: *WlData = @ptrCast(@alignCast(data));
    wld.should_draw = true;
}

fn handleWlBufferRelease(data: ?*anyopaque, buffer: ?*wl.Buffer) callconv(.c) void {
    _ = buffer;

    const wld: *WlData = @ptrCast(@alignCast(data));
    wld.free_buffers += 1;
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

fn handleLibdecorConfigure(frame: ?*c.libdecor_frame, config: ?*c.libdecor_configuration, data: ?*anyopaque) callconv(.c) void {
    const wld: *WlData = @ptrCast(@alignCast(data));

    var width: c_int = undefined;
    var height: c_int = undefined;
    if (!c.libdecor_configuration_get_content_size(config, frame, &width, &height)) {
        width = initial_window_width;
        height = initial_window_height;
    }

    const state = c.libdecor_state_new(width, height);
    c.libdecor_frame_commit(frame, state, config);
    c.libdecor_state_free(state);

    resize(wld, width, height) catch |e| {
        log.err("Error during resize: {}", .{e});
        log.err("Unable to handle resize error in handleLibdecorConfigure, stopping application", .{});
        wld.running = false;
        return;
    };
}

fn handleLibdecorClose(frame: ?*c.libdecor_frame, data: ?*anyopaque) callconv(.c) void {
    _ = frame;
    const wld: *WlData = @ptrCast(@alignCast(data));
    wld.running = false;
}

fn handleLibdecorDismissPopup(frame: ?*c.libdecor_frame, seat_name: [*c]const u8, data: ?*anyopaque) callconv(.c) void {
    _ = frame;
    _ = data;
    log.debug("handleLibdecorDismissPopup seat: {s}", .{seat_name});
}

fn handleXdgDecorationConfigure(data: ?*anyopaque, toplevel_decoration: ?*xdg_decoration.ToplevelDecorationV1, mode: xdg_decoration.ToplevelDecorationV1.Mode) callconv(.c) void {
    _ = toplevel_decoration;
    log.debug("xdg_decoration configure: {}", .{mode});

    const mode_ptr: *xdg_decoration.ToplevelDecorationV1.Mode = @ptrCast(@alignCast(data));
    mode_ptr.* = mode;
}

var rv: i32 = 5;
var ry: i32 = 0;
fn draw(wld: *WlData) void {
    wld.free_buffers -= 1;

    const buffer_ptr = wld.buffer_data[wld.buffer_index];
    const pixels = @as([*]Pixel, @ptrCast(buffer_ptr))[0..@intCast(wld.width * wld.height)];
    @memset(pixels, .{ .r = 0, .g = 0, .b = 0, .a = 255 });

    // TODO: This should not be in draw!
    ry += rv;
    if (ry < 0) {
        ry = 0;
        rv *= -1;
    }
    if (ry + 100 > wld.height) {
        ry = wld.height - 100;
        rv *= -1;
    }

    drawRect(wld, pixels, 10, ry, 100, 100, .{ .r = 255, .g = 0, .b = 0 });
    drawRect(wld, pixels, wld.width - 110, wld.height - 110, 100, 100, .{ .r = 0, .g = 255, .b = 0 });

    wld.surface.attach(wld.buffers.?[wld.buffer_index], 0, 0);
    wld.surface.damage(0, 0, wld.width, wld.height);
    wld.surface.commit();
    const callback = wld.surface.frame();
    callback.?.add_listener(&wl_callback_listener, wld);
    _ = wl.display_flush(wld.display);
    wld.buffer_index = 1 - wld.buffer_index;
}

fn drawRect(wld: *WlData, pixels: []Pixel, x: i32, y: i32, w: i32, h: i32, color: Pixel) void {
    const ux_min: usize = @max(0, x);
    const ux_max: usize = @intCast(@min(wld.width - 1, x + w));
    const uy_min: usize = @max(0, y);
    const uy_max: usize = @intCast(@abs(@min(wld.height - 1, y + h)));

    for (ux_min..ux_max) |bx| {
        for (uy_min..uy_max) |by| {
            pixels[bx + (by * @as(usize, @intCast(wld.width)))] = color;
        }
    }
}

fn nop() callconv(.c) void {}
