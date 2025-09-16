const std = @import("std");
const log = std.log.scoped(.linux_v10);
const wayland = @import("wayland");
const wl = wayland.wl;
const xdg_shell = wayland.xdg_shell;
const xdg_decoration = wayland.xdg_decoration_unstable_v1;
const viewporter = wayland.viewporter;
const libdecor = @import("libdecor.zig");
const udev = @import("libudev.zig");
const posix = std.posix.system;

const c = @cImport({
    @cInclude("linux/input.h");
});

// TODO: Check if preferred_buffer_scale is relevant

const assert = std.debug.assert;

const initial_window_width: i32 = 1280;
const initial_window_height: i32 = 720;
const bytes_per_pixel = 4;

const WlInitData = struct {
    wld: *WlData,
    wl_shm: ?*wl.Shm = null,
    wl_compositor: ?*wl.Compositor = null,
    wl_seat: ?*wl.Seat = null,
    xdg_wm_base: ?*xdg_shell.WmBase = null,
    xdg_decoration_manager: ?*xdg_decoration.DecorationManagerV1 = null,
    viewporter: ?*viewporter.Viewporter = null,

    xrgb8888: bool = false,
    seat_capabilities: wl.Seat.Capability = .{},
};

const WlData = struct {
    running: bool = true,
    should_draw: bool = false,

    pool: ?*wl.ShmPool = undefined,
    buffers: [3]Buffer = undefined,

    display: *wl.Display = undefined,
    shm: *wl.Shm = undefined,
    compositor: *wl.Compositor = undefined,
    seat: *wl.Seat = undefined,
    surface: *wl.Surface = undefined,
    viewporter: *viewporter.Viewporter = undefined,
    viewport: *viewporter.Viewport = undefined,
    wm_base: *xdg_shell.WmBase = undefined,
    keyboard: *wl.Keyboard = undefined,

    toplevel: Toplevel = undefined,

    /// Back buffer width
    width: i32 = -1,
    /// Back buffer height
    height: i32 = -1,
    /// Window width
    window_width: i32,
    /// Window height
    window_height: i32,

    /// Max width of (non fullscreen) surface
    bound_width: i32 = undefined,
    /// Max height of (non fullscreen) surface
    bound_height: i32 = undefined,
    /// Max width of all outputs
    max_width: i32 = undefined,
    /// Max height of all outputs
    max_height: i32 = undefined,

    should_resize_shm: bool = undefined,
    shm_size: usize = undefined,
    shm_ptr: [*]u8 = undefined,

    pending_resize: ?PendingResize = null,
};

const Buffer = struct {
    wld: *WlData,
    handle: ?*wl.Buffer,
    offset: i32,
    free: bool,
    width: i32,
    height: i32,
};

const Toplevel = union(enum) {
    no_decoration: struct {
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
        decor: *libdecor.Context,
        frame: *libdecor.Frame,
    },

    fn set_app_id(this: Toplevel, id: [*:0]const u8) void {
        switch (this) {
            .no_decoration => |d| d.xdg_toplevel.set_app_id(id),
            .xdg_decoration => |d| d.xdg_toplevel.set_app_id(id),
            .libdecor => |d| libdecor.frame_set_app_id(d.frame, id),
        }
    }

    fn set_title(this: Toplevel, id: [*:0]const u8) void {
        switch (this) {
            .no_decoration => |n| n.xdg_toplevel.set_title(id),
            .xdg_decoration => |n| n.xdg_toplevel.set_title(id),
            .libdecor => |d| libdecor.frame_set_title(d.frame, id),
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

const libdecor_listener = libdecor.FrameInterface{
    .configure = handleLibdecorConfigure,
    .commit = @ptrCast(&nop), // This should be safe to ignore, since we continuously redraw
    .close = handleLibdecorClose,
    .dismiss_popup = handleLibdecorDismissPopup,
};

const xdg_decoration_listener = xdg_decoration.ToplevelDecorationV1.Listener{
    .configure = handleXdgDecorationConfigure,
};

const wl_output_listener = wl.Output.Listener{
    .geometry = @ptrCast(&nop),
    .mode = handleWlOutputMode,
    .done = handleWlOutputDone,
    .scale = handleWlOutputScale,
    .name = @ptrCast(&nop),
    .description = @ptrCast(&nop),
};

const PollFdSlot = enum(usize) {
    udev,

    // NOTE: !!! Update first/last when changing this!
    joystick_0,
    joystick_1,
    joystick_2,
    joystick_3,
    // NOTE: !!! Update first/last when changing this!

    pub const first_joystick: usize = @intFromEnum(PollFdSlot.joystick_0);
    pub const last_joystick: usize = @intFromEnum(PollFdSlot.joystick_3);
    pub const joystick_count: usize = last_joystick - first_joystick + 1;
};

const poll_fd_count = @typeInfo(PollFdSlot).@"enum".fields.len;
var poll_fds: [poll_fd_count]std.posix.pollfd = [1]std.posix.pollfd{.{
    .fd = -1,
    .events = undefined,
    .revents = undefined,
}} ** poll_fd_count;

pub fn main() !void {
    udev.load();

    var udev_monitor: *udev.Monitor = undefined;

    const udev_ctx_opt = udev.new();
    if (udev_ctx_opt) |udev_ctx| {
        const udev_enumerator = udev.enumerate_new(udev_ctx) orelse {
            log.err("udev_enumerate_new failed", .{});
            return error.Unexpected;
        };
        _ = udev.enumerate_add_match_subsystem(udev_enumerator, "input");
        _ = udev.enumerate_scan_devices(udev_enumerator);

        var udev_list_entry = udev.enumerate_get_list_entry(udev_enumerator);
        while (udev_list_entry) |e| {
            const syspath = udev.list_entry_get_name(e);
            const device = udev.device_new_from_syspath(udev_ctx, syspath).?;
            defer _ = udev.device_unref(device);

            if (udevDeviceIsJoystick(udev_ctx, device)) |devnode_path| {
                try addJoystick(device, devnode_path);
            }

            udev_list_entry = udev.list_entry_get_next(e);
        }

        _ = udev.enumerate_unref(udev_enumerator);

        if (udev.monitor_new_from_netlink(udev_ctx, "udev")) |m| {
            udev_monitor = m;
        } else {
            log.err("udev_monitor_new_from_netlink failed", .{});
            return error.Unexpected;
        }

        const udev_monitor_fd = udev.monitor_get_fd(udev_monitor);
        if (udev_monitor_fd < 0) {
            log.err("udev_monitor_get_Fd failed", .{});
            return error.Unexpected;
        }
        poll_fds[@intFromEnum(PollFdSlot.udev)] = .{ .fd = udev_monitor_fd, .events = std.posix.POLL.IN, .revents = undefined };

        if (udev.monitor_filter_add_match_subsystem_devtype(udev_monitor, "input", null) < 0) {
            log.err("udev_monitor_filter_add_match_subsystem_devtype failed", .{});
            return error.Unexpected;
        }

        if (udev.monitor_enable_receiving(udev_monitor) < 0) {
            log.err("udev_monitor_enable_receiving failed", .{});
            return error.Unexpected;
        }
    }

    // TODO: Move this into the generator
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

    var wld: WlData = .{
        .running = true,
        .display = display,
        .window_width = initial_window_width,
        .window_height = initial_window_height,
    };

    var wli = WlInitData{ .wld = &wld };
    wl_registry.add_listener(&wl_registry_listener, &wli);
    if (wl.display_roundtrip(display) == -1) {
        log.err("wl_display_roundtrip failed", .{});
        return error.UnexpectedWayland;
    }
    defer wl_registry.destroy();

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
    if (wli.viewporter) |vp| wld.viewporter = vp else {
        log.err("wl_viewporter not available", .{});
        return error.UnexpectedWayland;
    }

    // for format events, seat, outputs
    wld.shm.add_listener(&wl_shm_listener, &wli);
    wld.seat.add_listener(&wl_seat_listener, &wli);
    _ = wl.display_roundtrip(display);
    log.debug("Format available", .{});
    log.debug("Seat capabilities: {}", .{wli.seat_capabilities});
    log.debug("Max size: {},{}", .{ wld.max_width, wld.max_height });

    try resize_shm(&wld);

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

    if (wli.xrgb8888 == false) {
        log.err("xrgb8888 format not avaliable", .{});
        return error.UnexpectedWayland;
    }

    wld.wm_base.add_listener(&xdg_wm_base_listener, null);

    wld.surface = wld.compositor.create_surface() orelse {
        log.err("wl_compositor_create_surface failed", .{});
        return error.UnexpectedWayland;
    };
    wld.surface.add_listener(&wl_surface_listener, null);

    wld.viewport = wld.viewporter.get_viewport(wld.surface) orelse {
        log.err("wl_viewporter_get_viewport failed", .{});
        return error.UnexpectedWayland;
    };

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
            const buffer = aquireFreeBufferIndex(&wld).?;
            draw(&wld, buffer);
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
        log.debug("xdg_decoration not supported, falling back to libdecor", .{});

        var no_decoration = false;
        libdecor.load() catch |e| switch (e) {
            error.LibDecorNotFound => no_decoration = true,
            error.LookupFailed => return e,
        };

        if (no_decoration) {
            log.debug("libdecor not supported, falling back to no decorations", .{});

            var xdg_surface: *xdg_shell.Surface = undefined;
            var xdg_toplevel: *xdg_shell.Toplevel = undefined;

            if (wli.xdg_decoration_manager != null) {
                xdg_decor_toplevel.xdg_decoration.xdg_toplevel_decoration.destroy();
                xdg_surface = xdg_decor_toplevel.xdg_decoration.xdg_surface;
                xdg_toplevel = xdg_decor_toplevel.xdg_decoration.xdg_toplevel;
            } else {
                xdg_surface = wld.wm_base.get_xdg_surface(wld.surface) orelse {
                    log.err("xdg_wm_base_get_xdg_surface failed", .{});
                    return error.UnexpectedWayland;
                };
                xdg_surface.add_listener(&xdg_surface_listener, &wld);

                xdg_toplevel = xdg_surface.get_toplevel() orelse {
                    log.err("xdg_surface_get_top_level failed", .{});
                    return error.UnexpectedWayland;
                };
                xdg_toplevel.add_listener(&xdg_toplevel_listener, &wld);
            }

            wld.surface.commit();
            _ = wl.display_roundtrip(display);
            if (wld.pending_resize) |r| {
                try resize(&wld, r.width, r.height);
            }
            const buffer = aquireFreeBufferIndex(&wld).?;
            draw(&wld, buffer);

            break :blk .{ .no_decoration = .{ .xdg_surface = xdg_surface, .xdg_toplevel = xdg_toplevel } };
        } else {
            if (wli.xdg_decoration_manager != null) {
                xdg_decor_toplevel.xdg_decoration.xdg_toplevel_decoration.destroy();
                xdg_decor_toplevel.xdg_decoration.xdg_toplevel.destroy();
                xdg_decor_toplevel.xdg_decoration.xdg_surface.destroy();
            }

            const context = libdecor.new(display, null) orelse {
                log.err("libdecor_new failed", .{});
                return error.UnexpectedLibDecor;
            };

            const frame = libdecor.decorate(context, @ptrCast(wld.surface), @ptrCast(@constCast(&libdecor_listener)), &wld) orelse {
                log.err("libdecor decorate failed", .{});
                return error.UnexpectedLibDecor;
            };

            wld.surface.commit();
            break :blk .{ .libdecor = .{ .decor = @ptrCast(context), .frame = @ptrCast(frame) } };
        }
    };

    wld.toplevel.set_app_id("v10");
    wld.toplevel.set_title("v10");

    var x_offset: i32 = 0;
    var y_offset: i32 = 0;
    var jx: i32 = 0;
    var jy: i32 = 0;

    while (wl.display_dispatch(display) != -1 and wld.running) {
        if (try std.posix.poll(&poll_fds, 0) > 0) {
            for (poll_fds, 0..) |pollfd, slot_index| {
                if (pollfd.revents & std.posix.POLL.IN != 0) {
                    const slot: PollFdSlot = @enumFromInt(slot_index);
                    switch (slot) {
                        .udev => {
                            const device = udev.monitor_receive_device(udev_monitor).?;
                            defer _ = udev.device_unref(device);

                            const action = std.mem.span(udev.device_get_action(device).?);

                            if (udevDeviceIsJoystick(udev_ctx_opt.?, device)) |path| {
                                if (std.mem.eql(u8, action, "add")) {
                                    try addJoystick(device, path);
                                } else if (std.mem.eql(u8, action, "remove")) {
                                    removeJoystick(device, path);
                                } else {
                                    log.err("Unhandled joystick action: '{s}'", .{action});
                                }
                            }
                        },

                        .joystick_0,
                        .joystick_1,
                        .joystick_2,
                        .joystick_3,
                        => {
                            var events: [16]c.input_event = undefined;
                            const read_len = try std.posix.read(pollfd.fd, std.mem.sliceAsBytes(&events));
                            if (read_len > 0) {
                                const num_events = read_len / @sizeOf(c.input_event);
                                for (events[0..num_events]) |event| {
                                    switch (event.type) {
                                        c.EV_SYN => {},
                                        c.EV_ABS => switch (event.code) {
                                            c.ABS_X => {
                                                jx = event.value;
                                                // log.debug("X: {}", .{event.value});
                                            },
                                            c.ABS_Y => {
                                                jy = event.value;
                                                // log.debug("Y: {}", .{event.value});
                                            },
                                            // c.ABS_Z => log.debug("Z: {}", .{event.value}),
                                            // c.ABS_RX => log.debug("RX: {}", .{event.value}),
                                            // c.ABS_RY => log.debug("RY: {}", .{event.value}),
                                            // c.ABS_RZ => log.debug("RZ: {}", .{event.value}),
                                            //
                                            // // dpad
                                            // c.ABS_HAT0X => log.debug("HAT0X: {}", .{event.value}),
                                            // c.ABS_HAT0Y => log.debug("HAT0Y: {}", .{event.value}),

                                            // else => log.debug("{} unhandled axis {}", .{ slot, event.code }),
                                            else => {},
                                        },
                                        c.EV_KEY => switch (event.code) {
                                            // c.BTN_A => log.debug("A: {}", .{event.value}),
                                            // c.BTN_B => log.debug("B: {}", .{event.value}),
                                            // c.BTN_X => log.debug("X: {}", .{event.value}),
                                            // c.BTN_Y => log.debug("Y: {}", .{event.value}),
                                            //
                                            // c.BTN_THUMBL => log.debug("THUMBL: {}", .{event.value}),
                                            // c.BTN_THUMBR => log.debug("THUMBR: {}", .{event.value}),
                                            //
                                            // c.BTN_TL => log.debug("TL: {}", .{event.value}),
                                            // c.BTN_TR => log.debug("TR: {}", .{event.value}),
                                            //
                                            // c.BTN_SELECT => log.debug("SELECT: {}", .{event.value}),
                                            // c.BTN_START => log.debug("START: {}", .{event.value}),
                                            // c.BTN_MODE => log.debug("MODE: {}", .{event.value}),

                                            // else => log.debug("{} unhandled key {}", .{ slot, event.code }),
                                            else => {},
                                        },
                                        else => {},
                                    }
                                }
                            } else {
                                unreachable;
                            }
                        },

                        // else => {
                        //     log.warn("Unhandled pollfd slot {}", .{slot});
                        // },
                    }
                }
            }
        }

        // log.debug("{},{}", .{ jx, jy });
        // log.debug("{},{}", .{ @divTrunc(gx, 4096), @divTrunc(gy, 4096) });
        x_offset +%= @divTrunc(jx, 4096);
        y_offset +%= @divTrunc(jy, 4096);
        // log.debug("{},{}", .{ x_offset, y_offset });

        if (wld.pending_resize) |r| {
            try resize(&wld, r.width, r.height);
        }
        if (wld.should_draw) {
            if (aquireFreeBufferIndex(&wld)) |buffer| {
                renderWeirdGradient(buffer, x_offset, y_offset);
                draw(&wld, buffer);
            } else {
                _ = wl.display_roundtrip(display);
                continue;
            }
        }

        _ = wl.display_flush(display);
    }
}

const PosixShmError = error{
    ShmOpenFailed,
    ShmUnlinkFailed,
    FtruncateFailed,
    MmapFailed,
    WlShmCreatePoolFailed,
    WlPoolCreateBufferFailed,
};

fn resize_shm(wld: *WlData) PosixShmError!void {
    log.debug("resize_shm", .{});
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
    const fd = std.c.shm_open(name, @bitCast(open_flags), mode);
    if (fd < 0) {
        log.err("shm_open failed, errno: {}", .{std.posix.errno(fd)});
        return error.ShmOpenFailed;
    }
    defer _ = std.c.close(fd);

    if (std.c.shm_unlink(name) != 0) {
        log.err("shm_unlink failed, errno: {}", .{std.posix.errno(-1)});
        return error.ShmUnlinkFailed;
    }

    const pixel_count: usize = @intCast(wld.max_width * wld.max_height);
    const buffer_size: usize = pixel_count * bytes_per_pixel;
    log.debug("Buffer size: {}", .{buffer_size});
    wld.shm_size = buffer_size * wld.buffers.len;
    log.debug("Allocating shm: {}", .{wld.shm_size});

    if (std.c.ftruncate(fd, @intCast(wld.shm_size)) != 0) {
        log.err("ftruncate failed, errno: {}", .{std.posix.errno(-1)});
        return error.FtruncateFailed;
    }

    const prot = std.c.PROT.READ | std.c.PROT.WRITE;
    const map = std.c.MAP{ .TYPE = .SHARED };

    const mapped = std.c.mmap(null, @intCast(wld.shm_size), prot, map, fd, 0);
    if (mapped == std.c.MAP_FAILED) {
        log.err("mmap call failed during buffer resize", .{});
        return error.MmapFailed;
    }
    wld.shm_ptr = @ptrCast(mapped);

    if (wld.pool) |p| p.destroy();

    const pool = wld.shm.create_pool(fd, @intCast(wld.shm_size)) orelse {
        log.err("wl_shm_create_pool failed", .{});
        return error.WlShmCreatePoolFailed;
    };
    wld.pool = pool;

    var width = wld.width;
    var height = wld.height;
    if (width == -1 and height == -1) {
        width = initial_window_width;
        height = initial_window_height;
    }
    const stride = width * bytes_per_pixel;

    var offset: i32 = 0;
    for (&wld.buffers) |*buffer| {
        const handle = pool.create_buffer(offset, width, height, stride, .xrgb8888) orelse {
            log.err("wl_pool_create_buffer failed", .{});
            return error.WlPoolCreateBufferFailed;
        };

        buffer.* = .{
            .wld = wld,
            .handle = handle,
            .offset = offset,
            .free = true,
            .width = width,
            .height = height,
        };
        handle.add_listener(&wl_buffer_listener, buffer);

        offset += @intCast(buffer_size);
    }

    wld.should_resize_shm = false;
    // TODO: Signal a buffer resize is required!
    // TODO: Test by plugging in external monitor
}

fn resize(wld: *WlData, width: i32, height: i32) error{WlPoolCreateBufferFailed}!void {
    // if (width == 0 and height == 0) {
    //     wld.width = initial_window_width;
    //     wld.height = initial_window_height;
    // } else {
    //     wld.width = width;
    //     wld.height = height;
    // }

    // This is the size of the backbuffers
    wld.width = initial_window_width;
    wld.height = initial_window_height;

    var window_width = width;
    var window_height = height;
    if (window_width == 0) window_width = wld.width;
    if (window_height == 0) window_height = wld.height;
    wld.window_width = window_width;
    wld.window_height = window_height;
    wld.viewport.set_destination(window_width, window_height);

    wld.should_draw = true;
    wld.pending_resize = null;
}

fn aquireFreeBufferIndex(wld: *WlData) ?*Buffer {
    for (&wld.buffers) |*buffer| {
        if (buffer.free) {
            if (buffer.handle == null or buffer.width != wld.width or buffer.height != wld.height) {
                if (buffer.handle) |h| h.destroy();

                const new_buf = wld.pool.?.create_buffer(buffer.offset, wld.width, wld.height, wld.width * bytes_per_pixel, .xrgb8888) orelse @panic("Buffer recreation failed");
                new_buf.add_listener(&wl_buffer_listener, buffer);
                buffer.handle = new_buf;
                buffer.width = wld.width;
                buffer.height = wld.height;
            }

            buffer.free = false;
            return buffer;
        }
    }

    return null;
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
    } else if (eq(interface_name, wl.Output)) {
        const output = registry.bind(name, wl.Output, version).?;
        output.add_listener(&wl_output_listener, wli.wld);
    } else if (eq(interface_name, viewporter.Viewporter)) {
        wli.viewporter = registry.bind(name, viewporter.Viewporter, version);
    }
}

fn handleWlRemoveGlobal(data: ?*anyopaque, registry: ?*wl.Registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;

    log.debug("Remove global: {}", .{name});
}

fn handleWlShmFormat(data: ?*anyopaque, shm: ?*wl.Shm, format: wl.Shm.Format) callconv(.c) void {
    _ = shm;

    const wli: *WlInitData = @ptrCast(@alignCast(data));
    if (format == .xrgb8888) wli.xrgb8888 = true;
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

fn handleWlBufferRelease(data: ?*anyopaque, wl_buffer: ?*wl.Buffer) callconv(.c) void {
    _ = wl_buffer;
    const buffer: *Buffer = @ptrCast(@alignCast(data));
    const wld = buffer.wld;

    if (buffer.width != wld.width or buffer.height != wld.height) {
        buffer.handle.?.destroy();
        buffer.handle = null;
    }

    buffer.free = true;
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

fn handleLibdecorConfigure(frame: *libdecor.Frame, config: *libdecor.Configuration, data: ?*anyopaque) callconv(.c) void {
    const wld: *WlData = @ptrCast(@alignCast(data));

    var width: c_int = undefined;
    var height: c_int = undefined;
    if (!libdecor.configuration_get_content_size(config, frame, &width, &height)) {
        width = initial_window_width;
        height = initial_window_height;
    }

    const state = libdecor.state_new(width, height) orelse @panic("libdecor_state_new failed");
    libdecor.frame_commit(frame, state, config);
    libdecor.state_free(state);

    resize(wld, width, height) catch |e| {
        log.err("Error during resize: {}", .{e});
        log.err("Unable to handle resize error in handleLibdecorConfigure, stopping application", .{});
        wld.running = false;
        return;
    };
}

fn handleLibdecorClose(frame: *libdecor.Frame, data: ?*anyopaque) callconv(.c) void {
    _ = frame;
    const wld: *WlData = @ptrCast(@alignCast(data));
    wld.running = false;
}

fn handleLibdecorDismissPopup(frame: *libdecor.Frame, seat_name: [*c]const u8, data: ?*anyopaque) callconv(.c) void {
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

fn handleWlOutputMode(data: ?*anyopaque, output: ?*wl.Output, flags: wl.Output.Mode, width: i32, height: i32, refresh: i32) callconv(.c) void {
    _ = output;
    _ = flags;
    _ = refresh;
    const wld: *WlData = @ptrCast(@alignCast(data));
    const new_pixel_count = width * height;
    const max_pixel_count = wld.max_width * wld.max_height;
    if (new_pixel_count > max_pixel_count) {
        wld.max_width = width;
        wld.max_height = height;
        wld.should_resize_shm = true;
    }
}

fn handleWlOutputDone(data: ?*anyopaque, output: ?*wl.Output) callconv(.c) void {
    _ = data;
    _ = output;
    // log.debug("Output done: {}:\n", .{output.?});
}

fn handleWlOutputScale(data: ?*anyopaque, output: ?*wl.Output, factor: i32) callconv(.c) void {
    _ = data;
    _ = output;
    _ = factor;
    // log.debug("Output scale: {}: {}", .{ output.?, factor });
}

fn addJoystick(device: *udev.Device, devnode_path: []const u8) !void {
    _ = device;
    log.debug("Adding joystick: '{s}'", .{devnode_path});

    var joystick_index_opt: ?usize = null;
    for (0..PollFdSlot.joystick_count) |ji| {
        const pollfd = &poll_fds[PollFdSlot.first_joystick + ji];
        if (pollfd.fd == -1) {
            joystick_index_opt = ji;
            break;
        }
    }

    if (joystick_index_opt) |ji| {
        const fd = try std.posix.open(devnode_path, std.posix.O{ .ACCMODE = .RDONLY, .NONBLOCK = true }, 0);
        poll_fds[PollFdSlot.first_joystick + ji] = .{ .fd = fd, .events = std.posix.POLL.IN, .revents = undefined };
    } else {
        log.warn("A joystick was added, but there are no free slots!", .{});
    }
}

fn removeJoystick(device: *udev.Device, devnode_path: []const u8) void {
    _ = device;
    log.debug("Removing joystick: '{s}'", .{devnode_path});
    // TODO: Store path (and state) in joystick data, match with devnode_path
    unreachable;
}

/// Returns the devnode path if the device is a joystick, otherwise returns null.
fn udevDeviceIsJoystick(ctx: *udev.Context, device: *udev.Device) ?[]const u8 {
    var is_joystick = false;
    var is_keyboard = false;
    var is_mouse = false;
    if (udev.device_get_devnode(device)) |n| {
        const devnode_path = std.mem.span(n);

        if (std.mem.indexOf(u8, devnode_path, "event") != null) {
            is_joystick = udev.device_get_property_value(device, "ID_INPUT_JOYSTICK") != null;
            if (is_joystick) {
                if (udev.device_get_parent_with_subsystem_devtype(device, "usb", null)) |parent| {
                    const sibling_enumerator = udev.enumerate_new(ctx).?;
                    defer _ = udev.enumerate_unref(sibling_enumerator);

                    _ = udev.enumerate_add_match_subsystem(sibling_enumerator, "input");
                    _ = udev.enumerate_add_match_parent(sibling_enumerator, parent);
                    _ = udev.enumerate_scan_devices(sibling_enumerator);

                    var sibling = udev.enumerate_get_list_entry(sibling_enumerator);
                    while (sibling) |s| {
                        const sib_syspath = udev.list_entry_get_name(s);
                        const sib_dev = udev.device_new_from_syspath(ctx, sib_syspath).?;
                        defer _ = udev.device_unref(sib_dev);

                        if (udev.device_get_property_value(sib_dev, "ID_INPUT_KEYBOARD")) |_| {
                            is_keyboard = true;
                            break;
                        }

                        if (udev.device_get_property_value(sib_dev, "ID_INPUT_MOUSE")) |_| {
                            is_mouse = true;
                            break;
                        }

                        sibling = udev.list_entry_get_next(s);
                    }
                }
            }
        }

        if (is_joystick and !is_keyboard and !is_mouse) {
            return devnode_path;
        }
    }

    return null;
}

fn renderWeirdGradient(buffer: *Buffer, xoffset: i32, yoffset: i32) void {
    const uwidth: usize = @intCast(buffer.width);
    const uheight: usize = @intCast(buffer.height);

    const pitch = uwidth * bytes_per_pixel;
    var row: [*]u8 = buffer.wld.shm_ptr + @as(usize, @intCast(buffer.offset));
    for (0..uheight) |uy| {
        const y: i32 = @intCast(uy);
        var pixel: [*]u32 = @ptrCast(@alignCast(row));

        for (0..uwidth) |ux| {
            const x: i32 = @intCast(ux);

            const b: u8 = @truncate(@as(u32, @bitCast(x +% xoffset)));
            const g: u8 = @truncate(@as(u32, @bitCast(y +% yoffset)));
            pixel[0] = (@as(u16, g) << 8) | b;
            pixel += 1;
        }

        row += pitch;
    }
}

fn draw(wld: *WlData, buffer: *Buffer) void {
    wld.surface.attach(buffer.handle, 0, 0);
    wld.surface.damage(0, 0, wld.window_width, wld.window_height);
    wld.surface.commit();
    const callback = wld.surface.frame();
    callback.?.add_listener(&wl_callback_listener, wld);
    _ = wl.display_flush(wld.display);

    wld.should_draw = false;
}

fn nop() callconv(.c) void {}
