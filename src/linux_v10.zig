const std = @import("std");
const log = std.log.scoped(.linux_v10);
const mem = @import("mem");
const options = @import("options");
const builtin = @import("builtin");
const DynLib = @import("dynlib");

const platform = @import("v10_platform.zig");

const arch = @import("arch").arch;

const wayland = @import("wayland");
const wl = wayland.wl;
const wlc = @import("wayland-client.zig");
const xdg_shell = wayland.xdg_shell;
const xdg_decoration = wayland.xdg_decoration_unstable_v1;

const libdecor = @import("libdecor.zig");

const linux = @import("linux");
const input = linux.input;
const pa = linux.pulse;
const ioctl = linux.ioctl;
const udev = linux.libudev;
const errno = linux.errno;

const GameCode = platform.GameCode;
const Memory = platform.Memory;
const OffscreenBuffer = platform.OffscreenBuffer;
const Input = platform.Input;
const ControllerInput = platform.ControllerInput;
const ButtonState = platform.ButtonState;
const ThreadContext = platform.ThreadContext;
const AudioBuffer = platform.AudioBuffer;

const InputEvent = input.InputEvent;
const Key = input.Key;
const Abs = input.Abs;

// TODO: Check if (wayland) preferred_buffer_scale is relevant
// TODO: Query initial state of controller

const assert = std.debug.assert;

var prng: std.Random = undefined;

const back_buffer_width: i32 = 960;
const back_buffer_height: i32 = 540;
const bytes_per_pixel = 4;

var global_back_buffer: LinuxOffscreenBuffer = .{};
var running: bool = false;
var pause: bool = false;
var wld: WlData = .{};

var pa_ctx: ?*pa.Context = null;
var pa_ml: ?*pa.ThreadedMainLoop = null;
var pa_stream: ?*pa.Stream = null;
var pa_sample_spec: pa.SampleSpec = undefined;

var joysticks: [PollFdSlot.joystick_count]Joystick = @splat(.{ .fd = -1, .kind = undefined });

const poll_fd_count = @typeInfo(PollFdSlot).@"enum".fields.len;
var poll_fds: [poll_fd_count]linux.pollfd = @splat(.{
    .fd = -1,
    .events = undefined,
    .revents = undefined,
});

const use_debug_allocator = switch (builtin.mode) {
    .Debug => true,
    .ReleaseSafe => !builtin.link_libc, // Not ideal, but the best we have for now.
    .ReleaseFast, .ReleaseSmall => !builtin.link_libc and builtin.single_threaded, // Also not ideal.
};
var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main(init: std.process.Init.Minimal) !void {
    const gpa = if (use_debug_allocator)
        debug_allocator.allocator()
    else if (builtin.link_libc)
        std.heap.c_allocator
    else if (!builtin.single_threaded)
        std.heap.smp_allocator
    else
        comptime unreachable;

    var threaded: std.Io.Threaded = .init(gpa, .{
        .argv0 = .init(.{ .vector = init.args.vector }),
        .environ = .{ .block = init.environ.block },
    });
    defer threaded.deinit();

    const io = threaded.io();

    defer {
        if (use_debug_allocator) {
            _ = debug_allocator.detectLeaks();
            _ = debug_allocator.deinit();
        }
    }

    const prng_seed = std.Io.Timestamp.now(io, .real).toNanoseconds();
    var prng_impl = std.Random.DefaultPrng.init(@intCast(prng_seed));
    prng = prng_impl.random();

    var shared_state: platform.SharedState = .{};

    const exe_dir_path_len = try std.process.executableDirPath(io, &shared_state.exe_dir_path_buf);
    shared_state.exe_dir_path = shared_state.exe_dir_path_buf[0..exe_dir_path_len];

    var game_lib_name_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const game_lib_name = try shared_state.buildExePathFilename(&game_lib_name_buf, "libv10_game.so");

    // TODO: Move this into the generator
    // var lwl = try DynLib.open("libwayland-client.so");
    // defer lwl.close();

    // try wl.load(&lwl);

    wayland.wlc.proxy_marshal_array_flags = wlc.proxy_marshal_array_flags;

    const display = wlc.display_connect(null) orelse {
        log.err("wl_display_connect failed", .{});
        return error.UnexpectedWayland;
    };
    defer wl.display_disconnect(display);
    log.debug("Display connected", .{});

    const wl_registry = display.get_registry() orelse {
        log.err("wl_display_get_registry failed", .{});
        return error.UnexpectedWayland;
    };

    running = true;

    global_back_buffer.width = back_buffer_width;
    global_back_buffer.height = back_buffer_height;
    global_back_buffer.pitch = global_back_buffer.width * bytes_per_pixel;

    const back_buffer_memory_size: usize = @intCast(global_back_buffer.width * global_back_buffer.height * bytes_per_pixel);
    if (linux.mmap(
        null,
        back_buffer_memory_size,
        .{},
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    )) |mapped| {
        global_back_buffer.memory = mapped;
        linux.mprotect(mapped.ptr, mapped.len, .{ .READ = true, .WRITE = true }) catch {
            log.err("mprotect call failed during back buffer resize", .{});
            return error.MProtectFailed;
        };
    } else |_| {
        log.err("mmap call failed during back buffer resize", .{});
        return error.MmapFailed;
    }

    wld = .{
        .display = display,
        .io = io,
        .shared_state = &shared_state,
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

    for (&wld.outputs) |*output_opt| if (output_opt.*) |output| {
        output.handle.add_listener(&wl_output_listener, output_opt);
    };

    // for format events, seat, outputs
    wld.shm.add_listener(&wl_shm_listener, &wli);
    wld.seat.add_listener(&wl_seat_listener, &wli);
    _ = wl.display_roundtrip(display);
    log.debug("Format available", .{});
    log.debug("Seat capabilities: {}", .{wli.seat_capabilities});
    log.debug("Max size: {},{}", .{ wld.max_width, wld.max_height });

    wld.window_width = @as(f32, @floatFromInt(back_buffer_width)) * 1.5;
    wld.window_height = @as(f32, @floatFromInt(back_buffer_height)) * 1.5;

    try resize_shm();

    if (wli.seat_capabilities.keyboard == false) {
        log.debug("keyboard not available", .{});
        return error.UnexpectedWayland;
    }
    if (wli.seat_capabilities.pointer == false) {
        log.debug("mouse not available", .{});
        return error.UnexpectedWayland;
    }

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

    const app_id = "v10";
    const title = "v10";

    wld.toplevel = blk: {
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

        xdg_toplevel.set_app_id(app_id);
        xdg_toplevel.set_title(title);
        wld.surface.commit();

        if (wli.xdg_decoration_manager) |manager| {
            const toplevel_decoration = manager.get_toplevel_decoration(xdg_toplevel) orelse {
                log.err("zxdg_decoration_manager_v1_get_toplevel_decoration failed", .{});
                return error.UnexpectedWayland;
            };
            toplevel_decoration.set_mode(.server_side);

            var xdg_decoration_mode: ?xdg_decoration.ToplevelDecorationV1.Mode = null;
            toplevel_decoration.add_listener(&xdg_decoration_listener, &xdg_decoration_mode);

            _ = wl.display_roundtrip(wld.display);
            xdg_surface.ack_configure(wld.pending_configure_serial.?);
            wld.pending_configure_serial = null;

            if (xdg_decoration_mode == .server_side) {
                if (wld.pending_resize) |r| {
                    try resize(r.width, r.height);
                }

                break :blk .{
                    .xdg_decoration = .{
                        .xdg_surface = xdg_surface,
                        .xdg_toplevel = xdg_toplevel,
                        .xdg_toplevel_decoration = toplevel_decoration,
                    },
                };
            } else {
                toplevel_decoration.destroy();
            }
        }

        log.debug("xdg_decoration not supported, falling back to libdecor", .{});

        var libdecor_available = true;
        libdecor.load() catch |e| switch (e) {
            error.LibDecorNotFound => libdecor_available = true,
            error.LookupFailed => return e,
        };

        if (libdecor_available) {
            xdg_toplevel.destroy();
            xdg_surface.destroy();

            const context = libdecor.new(display, null) orelse {
                log.err("libdecor_new failed", .{});
                return error.UnexpectedLibDecor;
            };

            const frame = libdecor.decorate(context, @ptrCast(wld.surface), @ptrCast(@constCast(&libdecor_listener)), &wld) orelse {
                log.err("libdecor decorate failed", .{});
                return error.UnexpectedLibDecor;
            };

            libdecor.frame_set_app_id(frame, app_id);
            libdecor.frame_set_title(frame, app_id);

            wld.surface.commit();

            _ = wl.display_roundtrip(wld.display);
            wld.pending_configure_serial = null;

            break :blk .{ .libdecor = .{ .decor = @ptrCast(context), .frame = @ptrCast(frame) } };
        } else {
            log.debug("libdecor not supported, falling back to no decorations", .{});

            _ = wl.display_roundtrip(wld.display);
            wld.pending_configure_serial = null;

            break :blk .{ .no_decoration = .{ .xdg_surface = xdg_surface, .xdg_toplevel = xdg_toplevel } };
        }
    };

    const buffer = aquireFreeBuffer().?;
    displayWaylandBufferInWindow(buffer);

    // Wait for surface enter to set current monitor
    wld.surface.commit();
    _ = wl.display_roundtrip(wld.display);

    var monitor_hz: f32 = 60;

    for (wld.outputs, 0..) |output_opt, i| if (output_opt) |output| {
        log.debug("outputs[{}]: {}", .{ i, output });
        if (output.active) monitor_hz = @min(monitor_hz, @as(f32, @floatFromInt(output.refresh_mhz)) / 1000);
    };

    log.debug("monitor hz: {}", .{monitor_hz});

    const game_update_hz: f32 = monitor_hz / 2;
    log.debug("game update hz: {}", .{game_update_hz});
    const target_seconds_per_frame: f32 = 1.0 / game_update_hz;

    wld.keyboard = wld.seat.get_keyboard() orelse {
        log.debug("wl_seat_get_keyboard failed", .{});
        return error.UnexpectedWayland;
    };
    wld.keyboard.add_listener(&wl_keyboard_listener, &wld);

    wld.pointer = wld.seat.get_pointer() orelse {
        log.debug("wl_set_get_pointer failed", .{});
        return error.UnexpectedWayland;
    };
    wld.pointer.add_listener(&wl_mouse_listener, &wld);

    const base_address: ?[*]align(std.heap.page_size_min) u8, const fixed = if (options.internal_build)
        .{ @ptrFromInt(mem.TiB * 2), true }
    else
        .{ null, false };

    const permanent_storage_size = mem.MiB * 64;
    const transient_storage_size = mem.GiB * 1;
    const total_size = permanent_storage_size + transient_storage_size;

    var game_memory = Memory{
        .initialized = false,
        .permanent_len = permanent_storage_size,
        .transient_len = transient_storage_size,
        .debug = .{
            .readEntireFile = &DEBUG.readEntireFile,
            .freeFileMemory = &DEBUG.freeFileMemory,
            .writeEntireFile = &DEBUG.writeEntireFile,
        },
    };

    if (linux.mmap(
        base_address,
        total_size,
        .{},
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .FIXED = fixed },
        -1,
        0,
    )) |all_memory| {
        linux.mprotect(all_memory.ptr, all_memory.len, .{ .READ = true, .WRITE = true }) catch {
            log.err("mprotect call for game memory storage failed", .{});
            return error.MProtectFailed;
        };

        game_memory.permanent = all_memory.ptr;
        game_memory.transient = all_memory[permanent_storage_size..].ptr;
        assert(game_memory.transient_len == transient_storage_size);

        wld.shared_state.game_memory_block = all_memory;
    } else |_| {
        log.err("mmap call for game memory failed", .{});
        return error.MMapFailed;
    }

    log.debug("perm: {*}", .{game_memory.permanent});
    log.debug("trans: {*}", .{game_memory.transient});

    if (options.internal_build) {
        for (&shared_state.replay_buffers, 0..) |*replay_buffer, i| {
            const file_name = shared_state.getInputRecordingPath(&replay_buffer.filname_buf, false, i);

            const permissions = linux.S.IWUSR | linux.S.IRUSR | linux.S.IRGRP | linux.S.IROTH;
            if (linux.open(file_name, .{ .ACCMODE = .RDWR, .CREAT = true, .TRUNC = true }, permissions)) |fd| {
                if (linux.mmap(null, total_size, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0)) |buf| {
                    if (linux.ftruncate(fd, total_size)) {
                        replay_buffer.memory = buf;
                    } else |e| {
                        log.warn("ftruncate for input recording file failed, error: {}", .{e});
                    }
                } else |_| {
                    log.warn("mmap for input recording file failed", .{});
                }
            } else |_| {
                log.warn("open for input recording file failed", .{});
            }
        }
    }

    var audio_output: AudioOutput = .{};
    audio_output.frames_per_second = 48000;
    audio_output.frames_per_game_frame = @intFromFloat(@as(f32, @floatFromInt(audio_output.frames_per_second)) / game_update_hz);
    audio_output.safety_frames = audio_output.frames_per_game_frame + (audio_output.frames_per_game_frame / 3);
    audio_output.drift_justification_offset = @max(32, audio_output.frames_per_second / @as(u32, @intFromFloat(game_update_hz * 32)));

    try initPulse(&audio_output);

    {
        const prefill_frame_count = audio_output.safety_frames;
        var buffer_ptr: ?*anyopaque = null;
        var buffer_size: usize = prefill_frame_count * @sizeOf(AudioOutput.Frame);
        const begin_write_rc = pa.stream_begin_write(pa_stream, &buffer_ptr, &buffer_size);

        const actual_frame_count = buffer_size / @sizeOf(AudioOutput.Frame);

        if (begin_write_rc == 0 and buffer_ptr != null) {
            const frames = @as([*]AudioOutput.Frame, @ptrCast(@alignCast(buffer_ptr)))[0..actual_frame_count];

            @memset(frames, .{});

            _ = pa.stream_write(
                pa_stream,
                frames.ptr,
                buffer_size,
                null,
                0,
                .relative,
            );
        }
    }

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
                try addJoystick(io, device, devnode_path);
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
        poll_fds[@intFromEnum(PollFdSlot.udev)] = .{ .fd = udev_monitor_fd, .events = linux.POLL.IN, .revents = undefined };

        if (udev.monitor_filter_add_match_subsystem_devtype(udev_monitor, "input", null) < 0) {
            log.err("udev_monitor_filter_add_match_subsystem_devtype failed", .{});
            return error.Unexpected;
        }

        if (udev.monitor_enable_receiving(udev_monitor) < 0) {
            log.err("udev_monitor_enable_receiving failed", .{});
            return error.Unexpected;
        }
    }

    wld.new_input = &wld.game_input[0];
    wld.old_input = &wld.game_input[1];

    var thread_context: ThreadContext = .{
        .io = &io,
    };

    var game_code = GameCode.load(io, game_lib_name);
    if (game_code.init) |gameCodeInit| gameCodeInit(&thread_context, &game_memory);

    _ = pa.stream_cork(pa_stream, 0, null, null);

    var last_counter = getWallClock(io);

    var last_cycle_count = arch.rdtsc();

    log.debug("starting main loop", .{});
    while (running) {
        const new_lib_write_time = platform.getLastWriteTime(io, game_lib_name);
        if (new_lib_write_time > game_code.last_write_time) {
            game_code.unload();
            game_code = GameCode.load(io, game_lib_name);
        }

        wld.new_input.dt = target_seconds_per_frame;

        const keyboard_controller = &wld.new_input.controllers[0];
        const old_keyboard_controller = &wld.old_input.controllers[0];
        keyboard_controller.* = std.mem.zeroes(ControllerInput);
        for (&keyboard_controller.buttons.array, old_keyboard_controller.buttons.array) |*new_button, old_button| {
            new_button.ended_down = old_button.ended_down;
        }
        keyboard_controller.is_connected = true;

        if (options.internal_build) {
            const mouse = &wld.new_input.debug_mouse;
            const old_mouse = &wld.old_input.debug_mouse;
            mouse.* = std.mem.zeroes(platform.DebugMouseInput);
            mouse.x = old_mouse.x;
            mouse.y = old_mouse.y;
            mouse.z = old_mouse.z;
            for (&mouse.buttons.array, old_mouse.buttons.array) |*new_button, old_button| {
                new_button.ended_down = old_button.ended_down;
            }
        }

        if (wl.display_dispatch(display) == -1) {
            running = false;
        }

        if (try linux.poll(&poll_fds, 0) > 0) {
            for (&poll_fds, 0..) |*pollfd, slot_index| {
                const slot: PollFdSlot = @enumFromInt(slot_index);
                const in = pollfd.revents & linux.POLL.IN != 0;

                switch (slot) {
                    .udev => if (in) {
                        const device = udev.monitor_receive_device(udev_monitor).?;
                        defer _ = udev.device_unref(device);

                        const action = std.mem.span(udev.device_get_action(device).?);

                        if (udevDeviceIsJoystick(udev_ctx_opt.?, device)) |path| {
                            if (std.mem.eql(u8, action, "add")) {
                                try addJoystick(io, device, path);
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
                    => if (in) {
                        var events: [16]InputEvent = undefined;
                        if (linux.read(pollfd.fd, std.mem.sliceAsBytes(&events))) |bytes_read| {
                            const num_events = bytes_read.len / @sizeOf(InputEvent);
                            for (events[0..num_events]) |*event| {
                                const jid = slot_index - PollFdSlot.first_joystick;
                                const joystick = &joysticks[jid];
                                joystick.handleEvent(event);
                            }
                        } else |_| {
                            // Read failed somehow, don't throw an error, keep running
                        }
                    },
                }
            }
        }

        if (wld.pending_resize) |r| {
            if (wld.pending_configure_serial) |serial| {
                wld.toplevel.ack_configure(serial);
            }
            try resize(r.width, r.height);
        }

        if (!pause) {
            var max_controller_count: usize = joysticks.len;
            if (max_controller_count > (wld.new_input.controllers.len - 1)) max_controller_count = (wld.new_input.controllers.len - 1);

            for (joysticks[0..max_controller_count], 1..) |*js, i| {
                const old_controller = &wld.old_input.controllers[i];
                var new_controller = &wld.new_input.controllers[i];

                const old_buttons = &old_controller.buttons.named;
                const new_buttons = &new_controller.buttons.named;

                if (js.active) {
                    new_controller.is_connected = true;
                    new_controller.is_analog = old_controller.is_analog;

                    new_controller.stick_average_x = js.axis[@intFromEnum(Joystick.Axis.left_x)];
                    new_controller.stick_average_y = -js.axis[@intFromEnum(Joystick.Axis.left_y)];

                    if (new_controller.stick_average_x != 0 or new_controller.stick_average_y != 0) {
                        new_controller.is_analog = true;
                    }

                    if (js.getButtonState(.dpad_up)) {
                        new_controller.stick_average_y = 1;
                        new_controller.is_analog = false;
                    }
                    if (js.getButtonState(.dpad_down)) {
                        new_controller.stick_average_y = -1;
                        new_controller.is_analog = false;
                    }
                    if (js.getButtonState(.dpad_left)) {
                        new_controller.stick_average_x = -1;
                        new_controller.is_analog = false;
                    }
                    if (js.getButtonState(.dpad_right)) {
                        new_controller.stick_average_x = 1;
                        new_controller.is_analog = false;
                    }

                    const threshold = 0.5;

                    processDigitalButton(
                        .{ .mask = if (new_controller.stick_average_x < -threshold) 1 else 0 },
                        &old_buttons.move_left,
                        @enumFromInt(0),
                        &new_buttons.move_left,
                    );
                    processDigitalButton(
                        .{ .mask = if (new_controller.stick_average_x > threshold) 1 else 0 },
                        &old_buttons.move_right,
                        @enumFromInt(0),
                        &new_buttons.move_right,
                    );
                    processDigitalButton(
                        .{ .mask = if (new_controller.stick_average_y < -threshold) 1 else 0 },
                        &old_buttons.move_down,
                        @enumFromInt(0),
                        &new_buttons.move_down,
                    );
                    processDigitalButton(
                        .{ .mask = if (new_controller.stick_average_y > threshold) 1 else 0 },
                        &old_buttons.move_up,
                        @enumFromInt(0),
                        &new_buttons.move_up,
                    );

                    // TODO: This could(/should?!) be done when we receive the event above, so we can count transitions
                    processDigitalButton(js.buttons, &old_buttons.action_up, .north, &new_buttons.action_up);
                    processDigitalButton(js.buttons, &old_buttons.action_down, .south, &new_buttons.action_down);
                    processDigitalButton(js.buttons, &old_buttons.action_left, .west, &new_buttons.action_left);
                    processDigitalButton(js.buttons, &old_buttons.action_right, .east, &new_buttons.action_right);
                    processDigitalButton(js.buttons, &old_buttons.left_shoulder, .shoulder_left, &new_buttons.left_shoulder);
                    processDigitalButton(js.buttons, &old_buttons.right_shoulder, .shoulder_right, &new_buttons.right_shoulder);
                    processDigitalButton(js.buttons, &old_buttons.back, .select, &new_buttons.back);
                    processDigitalButton(js.buttons, &old_buttons.start, .start, &new_buttons.start);

                    // try js.setRumble(3000, 0);
                } else {
                    new_controller.is_connected = false;
                }
            }

            var game_offscreen_buffer = OffscreenBuffer{
                .memory = global_back_buffer.memory.ptr,
                .memory_len = global_back_buffer.memory.len,
                .width = back_buffer_width,
                .height = back_buffer_height,
                .pitch = global_back_buffer.pitch,
                .bytes_per_pixel = bytes_per_pixel,
            };

            if (wld.shared_state.input_recording_index > 0) {
                recordInput(wld.shared_state, io, wld.new_input);
            }

            if (wld.shared_state.input_playing_index > 0) {
                playbackInput(wld.shared_state, io, wld.new_input);
            }

            const keep_running = if (game_code.updateAndRender) |updateAndRender| updateAndRender(&thread_context, &game_memory, wld.new_input, &game_offscreen_buffer) else true;
            if (!keep_running) running = false;

            pa.threaded_mainloop_lock(pa_ml);
            {
                if (pa.stream_get_state(pa_stream) != .ready) {
                    log.warn("Pulse stream not ready!", .{});
                    @panic("Unexpected pulse stream state");
                }

                const underflow_index = pa.stream_get_underflow_index(pa_stream);
                if (underflow_index != audio_output.last_underflow_index) {
                    audio_output.last_underflow_index = underflow_index;
                    log.debug("Pulse stream underflow!", .{});
                    _ = pa.stream_flush(pa_stream, null, null);
                }

                var usec: pa.USec = undefined;
                _ = pa.stream_get_latency(pa_stream, &usec, null);
                const latency_frames = usec * @as(u64, @intCast(audio_output.frames_per_second / std.time.us_per_s));

                const min_target_frames = latency_frames + audio_output.frames_per_game_frame;
                const base_target_frames = audio_output.frames_per_game_frame + audio_output.safety_frames;
                const target_frames = @max(base_target_frames, min_target_frames);

                const writable_frames = pa.stream_writable_size(pa_stream) / @sizeOf(AudioOutput.Frame);

                var frames_to_write = audio_output.frames_per_game_frame;
                if (latency_frames < target_frames) {
                    frames_to_write += audio_output.drift_justification_offset;
                } else if (latency_frames > target_frames) {
                    frames_to_write -= audio_output.drift_justification_offset;
                }

                frames_to_write = @min(writable_frames, frames_to_write);

                if (frames_to_write > 0) {
                    var buffer_ptr: ?*anyopaque = null;
                    var buffer_size: usize = frames_to_write * @sizeOf(AudioOutput.Frame);
                    const begin_write_rc = pa.stream_begin_write(pa_stream, &buffer_ptr, &buffer_size);

                    const actual_frame_count = buffer_size / @sizeOf(AudioOutput.Frame);

                    // log.debug("FTW: {} - FTWA: {} - LF: {} - WRITABLE: {} - LS: {d:.3}", .{
                    //     frames_to_write,
                    //     actual_frame_count,
                    //     latency_frames,
                    //     writable_frames,
                    //     @as(f64, @floatFromInt(usec)) / std.time.us_per_s,
                    // });

                    if (begin_write_rc == 0 and buffer_ptr != null) {
                        var game_sound_output_buffer: AudioBuffer = .{
                            .frames = @ptrCast(@alignCast(buffer_ptr)),
                            .frames_len = actual_frame_count,
                            .frames_per_second = @intCast(audio_output.frames_per_second),
                        };

                        if (game_code.getAudioFrames) |getAudioFrames| getAudioFrames(&thread_context, &game_memory, &game_sound_output_buffer);

                        _ = pa.stream_write(
                            pa_stream,
                            game_sound_output_buffer.frames,
                            buffer_size,
                            null,
                            0,
                            .relative,
                        );
                    } else {
                        log.warn("pa_stream_begin_write_failed", .{});
                    }
                }
            }
            pa.threaded_mainloop_unlock(pa_ml);

            const work_counter = getWallClock(io);
            const work_seconds_elapsed = getSecondsElapsed(last_counter, work_counter);

            var seconds_elapsed_for_frame = work_seconds_elapsed;
            if (seconds_elapsed_for_frame <= target_seconds_per_frame) {
                while (seconds_elapsed_for_frame < target_seconds_per_frame) {
                    const sleep_ms: u64 = @intFromFloat(std.time.ms_per_s * (target_seconds_per_frame - seconds_elapsed_for_frame));

                    if (sleep_ms > 1) {
                        const s = (sleep_ms * std.time.ns_per_ms) - (std.time.ns_per_ms / 2);
                        // linux.sleep(s);
                        try std.Io.sleep(io, std.Io.Duration.fromNanoseconds(s), .real);
                    }

                    seconds_elapsed_for_frame = getSecondsElapsed(last_counter, getWallClock(io));
                }
            } else {
                log.debug("Missed frame time!", .{});
            }

            const end_counter = getWallClock(io);
            const ms_per_frame = std.time.ms_per_s * getSecondsElapsed(last_counter, end_counter);
            last_counter = end_counter;

            const wayland_blit = displayBufferInWindow(global_back_buffer);

            _ = wl.display_flush(display);

            const tmp = wld.new_input;
            wld.new_input = wld.old_input;
            wld.old_input = tmp;

            const end_cycle_count = arch.rdtsc();
            const cycles_elapsed: f32 = @floatFromInt(end_cycle_count - last_cycle_count);
            last_cycle_count = end_cycle_count;

            const fps = std.time.ms_per_s / ms_per_frame;
            const mcpf = cycles_elapsed / (1000 * 1000);
            // log.info("{d:.2}ms/f,  {d:.2}f/s,  {d:.2}mc/f,  {d:.2}wms, wl_blit:{}", .{
            //     ms_per_frame,
            //     fps,
            //     mcpf,
            //     work_seconds_elapsed * std.time.ms_per_s,
            //     wayland_blit,
            // });
            _ = .{ ms_per_frame, fps, mcpf, wayland_blit };
        }
    }
}

const LinuxOffscreenBuffer = struct {
    memory: []align(std.heap.page_size_min) u8 = &.{},
    width: i32 = 0,
    height: i32 = 0,
    pitch: i32 = 0,
};

const WlInitData = struct {
    wld: *WlData,
    wl_shm: ?*wl.Shm = null,
    wl_compositor: ?*wl.Compositor = null,
    wl_seat: ?*wl.Seat = null,
    xdg_wm_base: ?*xdg_shell.WmBase = null,
    xdg_decoration_manager: ?*xdg_decoration.DecorationManagerV1 = null,
    wl_output: ?*wl.Output = null,

    xrgb8888: bool = false,
    seat_capabilities: wl.Seat.Capability = .{},
};

// TODO: Use xkb!
const KeyMods = packed struct(u32) {
    shift: bool = false,
    __reveved1: u1 = 0,
    control: bool = false,
    alt: bool = false,
    num: bool = false,
    __reserved2: u27 = 0,
};

const WlData = struct {
    should_draw: bool = false,

    outputs: [8]?WlOutput = std.mem.zeroes([8]?WlOutput),

    pool: ?*wl.ShmPool = null,
    buffers: [3]WlBuffer = undefined,

    display: *wl.Display = undefined,
    shm: *wl.Shm = undefined,
    compositor: *wl.Compositor = undefined,
    seat: *wl.Seat = undefined,
    surface: *wl.Surface = undefined,
    wm_base: *xdg_shell.WmBase = undefined,
    keyboard: *wl.Keyboard = undefined,
    pointer: *wl.Pointer = undefined,

    toplevel: WlToplevel = undefined,

    /// Back buffer width
    width: i32 = -1,
    /// Back buffer height
    height: i32 = -1,
    /// Window width
    window_width: i32 = 0,
    /// Window height
    window_height: i32 = 0,

    /// Max width of (non fullscreen) surface
    bound_width: i32 = 0,
    /// Max height of (non fullscreen) surface
    bound_height: i32 = 0,
    /// Max width of all outputs
    max_width: i32 = 0,
    /// Max height of all outputs
    max_height: i32 = 0,

    should_resize_shm: bool = false,
    shm_data: []align(std.heap.page_size_min) u8 = &.{},

    fullscreen: bool = false,
    double_scale: bool = false,

    pending_configure_serial: ?u32 = null,
    pending_resize: ?WlPendingResize = null,

    key_mods_pressed: KeyMods = .{},
    key_mods_latched: KeyMods = .{},
    key_mods_locked: KeyMods = .{},
    game_input: [2]platform.Input = @splat(.{}),
    new_input: *Input = undefined,
    old_input: *Input = undefined,

    shared_state: *platform.SharedState = undefined,

    io: std.Io = undefined,
};

const WlOutput = struct {
    handle: *wl.Output,
    refresh_mhz: i32 = 0,
    active: bool = false,
};

const WlBuffer = struct {
    handle: ?*wl.Buffer,
    offset: i32,
    free: bool,
    width: i32,
    height: i32,
};

const WlToplevel = union(enum) {
    no_decoration: struct {
        xdg_surface: *xdg_shell.Surface,
        xdg_toplevel: *xdg_shell.Toplevel,
    },

    xdg_decoration: struct {
        xdg_surface: *xdg_shell.Surface,
        xdg_toplevel: *xdg_shell.Toplevel,
        xdg_toplevel_decoration: *xdg_decoration.ToplevelDecorationV1,
    },

    libdecor: struct {
        decor: *libdecor.Context,
        frame: *libdecor.Frame,
    },

    pub fn set_fullscreen(this: *WlToplevel, output: ?*wl.Output) void {
        switch (this.*) {
            .no_decoration => |t| t.xdg_toplevel.set_fullscreen(output),
            .xdg_decoration => |t| t.xdg_toplevel.set_fullscreen(output),
            .libdecor => |ld| libdecor.frame_set_fullscreen(ld.frame, output),
        }
    }

    pub fn unset_fullscreen(this: *WlToplevel) void {
        switch (this.*) {
            .no_decoration => |t| t.xdg_toplevel.unset_fullscreen(),
            .xdg_decoration => |t| t.xdg_toplevel.unset_fullscreen(),
            .libdecor => |ld| libdecor.frame_unset_fullscreen(ld.frame),
        }
    }

    pub fn ack_configure(this: *WlToplevel, serial: u32) void {
        switch (this.*) {
            .no_decoration => |t| t.xdg_surface.ack_configure(serial),
            .xdg_decoration => |t| t.xdg_surface.ack_configure(serial),
            .libdecor => unreachable,
        }
    }
};

const WlPendingResize = struct {
    width: i32,
    height: i32,
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

const Joystick = struct {
    fd: linux.fd_t,
    active: bool = false,
    kind: Kind,

    rumble_strong: u16 = 0,
    rumble_weak: u16 = 0,
    rumble_event_id: i16 = -1,

    axis_meta: [axis_count]AxisMeta = @splat(.{}),
    axis: [axis_count]f32 = @splat(0),

    buttons: Buttons = .empty,

    /// Zero terminated devnode path
    path: [32]u8 = @splat(0),

    const Kind = enum {
        default,
        xbox,
    };

    const AxisMeta = struct {
        min: i32 = -1,
        max: i32 = 1,
        deadzone: i32 = 0,
    };

    const axis_count = @typeInfo(Axis).@"enum".fields.len;
    const Axis = enum(usize) {
        left_x = 0,
        left_y = 1,
        left_z = 2,
        right_x = 3,
        right_y = 4,
        right_z = 5,
        hat_x = 6,
        hat_y = 7,
    };

    pub const button_count = @typeInfo(Button).@"enum".fields.len;
    pub const Buttons = std.StaticBitSet(button_count);
    pub const Button = enum {
        north,
        east,
        south,
        west,
        dpad_up,
        dpad_right,
        dpad_down,
        dpad_left,
        thumb_left,
        thumb_right,
        shoulder_left,
        shoulder_right,
        select,
        start,
        mode,
    };

    pub inline fn getButtonState(this: *const Joystick, button: Button) bool {
        return this.buttons.isSet(@intFromEnum(button));
    }

    pub inline fn setButtonState(this: *Joystick, button: Button, state: bool) void {
        this.buttons.setValue(@intFromEnum(button), state);
    }

    fn absEventCodeToAxisIndex(kind: Kind, code: u16) ?usize {
        switch (kind) {
            .default,
            .xbox,
            => {
                const abs: Abs = @enumFromInt(code);
                const axis_opt: ?Axis = switch (abs) {
                    else => {
                        log.warn("Unhandled {s} controller event: {s}", .{ @tagName(kind), @tagName(abs) });
                        return null;
                    },

                    Abs.X => .left_x,
                    Abs.Y => .left_y,
                    Abs.Z => .left_z,
                    Abs.RX => .right_x,
                    Abs.RY => .right_y,
                    Abs.RZ => .right_z,

                    Abs.HAT0X => .hat_x,
                    Abs.HAT0Y => .hat_y,
                };

                if (axis_opt) |axis| {
                    return @intFromEnum(axis);
                } else return null;
            },
        }
    }

    fn keyEventCodeToButtonIndex(kind: Kind, code: u16) ?usize {
        switch (kind) {
            .default,
            .xbox,
            => {
                const key: Key = @enumFromInt(code);
                const btn_opt: ?Button = switch (key) {
                    else => {
                        log.warn("Unhandled {s} controller event: {s}", .{ @tagName(kind), @tagName(key) });
                        return null;
                    },
                    Key.BTN_Y => .north,
                    Key.BTN_B => .east,
                    Key.BTN_A => .south,
                    Key.BTN_X => .west,
                    Key.BTN_THUMBL => .thumb_left,
                    Key.BTN_THUMBR => .thumb_right,
                    Key.BTN_TL => .shoulder_left,
                    Key.BTN_TR => .shoulder_right,
                    Key.BTN_SELECT => .select,
                    Key.BTN_START => .start,
                    Key.BTN_MODE => .mode,

                    // Handled as axis
                    Key.BTN_DPAD_UP, Key.BTN_DPAD_LEFT, Key.BTN_DPAD_RIGHT, Key.BTN_DPAD_DOWN => null,
                };

                if (btn_opt) |btn| {
                    return @intFromEnum(btn);
                } else return null;
            },
        }
    }

    fn handleEvent(this: *Joystick, event: *const InputEvent) void {
        switch (event.type) {
            .SYN => {
                // TODO: Buffer events and handle this
            },
            .ABS => {
                if (absEventCodeToAxisIndex(this.kind, event.code)) |axis_idx| {
                    const meta = this.axis_meta[axis_idx];

                    var value: f32 = 0;
                    if (event.value < -meta.deadzone or event.value > meta.deadzone) {
                        const min: f32 = @floatFromInt(meta.min);
                        const max: f32 = @floatFromInt(meta.max);
                        value = @as(f32, @floatFromInt(event.value)) / if (event.value < 0) -min else max;
                    }
                    this.axis[axis_idx] = value;

                    const axis: Joystick.Axis = @enumFromInt(axis_idx);
                    if (axis == .hat_x) {
                        if (value == 0) {
                            this.setButtonState(.dpad_left, false);
                            this.setButtonState(.dpad_right, false);
                        } else if (value > 0) {
                            this.setButtonState(.dpad_left, false);
                            this.setButtonState(.dpad_right, true);
                        } else {
                            this.setButtonState(.dpad_left, true);
                            this.setButtonState(.dpad_right, false);
                        }
                    } else if (axis == .hat_y) {
                        if (value == 0) {
                            this.setButtonState(.dpad_up, false);
                            this.setButtonState(.dpad_down, false);
                        } else if (value > 0) {
                            this.setButtonState(.dpad_up, false);
                            this.setButtonState(.dpad_down, true);
                        } else {
                            this.setButtonState(.dpad_up, true);
                            this.setButtonState(.dpad_down, false);
                        }
                    }
                }
            },
            .KEY => {
                if (keyEventCodeToButtonIndex(this.kind, event.code)) |btn_idx| {
                    this.buttons.setValue(btn_idx, event.value != 0);
                }
            },
            else => log.warn("Unhandled event: {}", .{event.type}),
        }
    }

    fn setRumble(this: *Joystick, strong: u16, weak: u16) !void {
        assert(this.active);
        assert(this.fd >= 0);

        if (strong != this.rumble_strong or weak != this.rumble_weak) {
            this.rumble_strong = strong;
            this.rumble_weak = weak;

            const rumble_event = input.FfEffect{
                .type = .RUMBLE,
                .id = this.rumble_event_id,
                // NOTE: These magnitudes are treated as i16 values by the xpad driver!
                // TODO: Query the driver with udev, modify magnitude based on driver
                .u = .{ .rumble = .{ .strong_magnitude = this.rumble_strong, .weak_magnitude = this.rumble_weak } },
                .replay = .{ .length = 0xffff },
            };

            const id = ioctl.ioctl(this.fd, input.EVIOCSFF, @intFromPtr(&rumble_event));
            assert(id >= 0);
            this.rumble_event_id = @intCast(id);

            const play = InputEvent{ .type = .FF, .code = @intCast(id), .value = 1 };
            _ = linux.write(this.fd, @ptrCast(&play), @sizeOf(InputEvent));
        }
    }
};

fn processDigitalButton(buttons: Joystick.Buttons, old_state: *const ButtonState, btn: Joystick.Button, new_state: *ButtonState) void {
    new_state.ended_down = buttons.isSet(@intFromEnum(btn));
    new_state.half_transition_count = if (old_state.ended_down == new_state.ended_down) 0 else 1;
}

fn processKeyEvent(new_state: *ButtonState, is_down: bool) void {
    new_state.ended_down = is_down;
    new_state.half_transition_count += 1;
}

inline fn getWallClock(io: std.Io) std.Io.Timestamp {
    return std.Io.Timestamp.now(io, .real);
}

inline fn getSecondsElapsed(start: std.Io.Timestamp, end: std.Io.Timestamp) f32 {
    return @as(f32, @floatFromInt(start.durationTo(end).toNanoseconds())) / std.time.ns_per_s;
}

const ShmError = error{
    ShmOpenFailed,
    ShmCloseFailed,
    ShmUnlinkFailed,
    FtruncateFailed,
    MmapFailed,
    WlShmCreatePoolFailed,
    WlPoolCreateBufferFailed,
};

fn resize_shm() ShmError!void {
    const S = linux.S;

    if (wld.shm_data.len != 0) {
        linux.munmap(wld.shm_data) catch {
            log.warn("shm unmap failed", .{});
        };
    }

    var name_buf: [16]u8 = undefined;
    name_buf[0] = '/';
    name_buf[name_buf.len - 1] = 0;

    for (name_buf[1 .. name_buf.len - 1]) |*char| {
        char.* = prng.intRangeAtMost(u8, 'a', 'z');
    }
    const name = std.mem.span(@as([*:0]u8, @ptrCast(&name_buf)));
    log.debug("shm name: {s}", .{name});

    // TODO: Use mem_fd!
    const open_flags = linux.O{ .ACCMODE = .RDWR, .CREAT = true, .EXCL = true };
    const mode: linux.mode_t = S.IWUSR | S.IRUSR | S.IWOTH | S.IROTH;
    const fd = linux.shm_open(name, open_flags, mode) catch |e| {
        log.err("shm_open failed, error: {}", .{e});
        return error.ShmOpenFailed;
    };
    defer linux.close(fd) catch |e| {
        log.err("close shm fd failed, error: {}", .{e});
    };

    linux.shm_unlink(name) catch |e| {
        log.err("shm_unlink failed, error: {}", .{e});
        return error.ShmUnlinkFailed;
    };

    const pixel_count: usize = @intCast(wld.max_width * wld.max_height);
    const buffer_size: usize = pixel_count * bytes_per_pixel;
    log.debug("Buffer size: {}", .{buffer_size});
    const shm_size = buffer_size * wld.buffers.len;
    log.debug("Allocating shm: {}", .{shm_size});

    linux.ftruncate(fd, @intCast(shm_size)) catch {
        log.err("ftruncate failed", .{});
        return error.FtruncateFailed;
    };

    const prot = linux.PROT{ .READ = true, .WRITE = true };
    const map = linux.MAP{ .TYPE = .SHARED };

    if (linux.mmap(null, shm_size, prot, map, fd, 0)) |mapped| {
        wld.shm_data = mapped;

        if (wld.pool) |p| p.destroy();

        const pool = wld.shm.create_pool(fd, @intCast(wld.shm_data.len)) orelse {
            log.err("wl_shm_create_pool failed", .{});
            return error.WlShmCreatePoolFailed;
        };
        wld.pool = pool;

        var width = wld.width;
        var height = wld.height;
        if (width == -1 and height == -1) {
            width = back_buffer_width;
            height = back_buffer_height;
        }
        const stride = width * bytes_per_pixel;

        var offset: i32 = 0;
        for (&wld.buffers) |*buffer| {
            const handle = pool.create_buffer(offset, width, height, stride, .xrgb8888) orelse {
                log.err("wl_pool_create_buffer failed", .{});
                return error.WlPoolCreateBufferFailed;
            };

            buffer.* = .{
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

    } else |_| {
        log.err("mmap call failed during shm buffer resize", .{});
        return error.MmapFailed;
    }
}

fn resize(width: i32, height: i32) !void {
    log.debug("resize: {},{}", .{ width, height });
    // Back buffer
    wld.width = back_buffer_width;
    wld.height = back_buffer_height;

    if (width != 0) {
        wld.window_width = width;
    }
    if (height != 0) {
        wld.window_height = height;
    }

    wld.double_scale = width >= global_back_buffer.width * 2 and height >= global_back_buffer.height * 2;
    wld.should_draw = true;
    wld.pending_resize = null;
}

fn aquireFreeBuffer() ?*WlBuffer {
    for (&wld.buffers) |*buffer| {
        if (buffer.free) {
            if (buffer.handle == null or buffer.width != wld.window_width or buffer.height != wld.window_height) {
                if (buffer.handle) |h| h.destroy();

                const new_buf = wld.pool.?.create_buffer(buffer.offset, wld.window_width, wld.window_height, wld.window_width * bytes_per_pixel, .xrgb8888) orelse @panic("Buffer recreation failed");
                new_buf.add_listener(&wl_buffer_listener, buffer);
                buffer.handle = new_buf;
                buffer.width = wld.window_width;
                buffer.height = wld.window_height;
            }

            buffer.free = false;
            return buffer;
        }
    }

    return null;
}

pub const DEBUG = struct {
    pub fn readEntireFile(thread_context: *ThreadContext, path: [*:0]const u8, path_len: usize) callconv(.c) platform.DEBUG.ReadFileResult {
        assert(std.mem.span(path).len == path_len);
        var result = platform.DEBUG.ReadFileResult{};

        if (linux.open(path, .{ .ACCMODE = .RDONLY }, 0)) |fd| {
            var stat: linux.Stat = undefined;

            // TODO: Use statx here! statx needs absolute paths or a dir fd...
            if (linux.stat(std.mem.span(path), &stat)) {
                const file_size: usize = @intCast(stat.st_size);

                if (linux.mmap(null, file_size, .{}, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0)) |mapped| {
                    if (linux.mprotect(mapped.ptr, mapped.len, .{ .READ = true, .WRITE = true })) {
                        if (linux.read(fd, mapped)) |read| {
                            assert(read.len == file_size);
                            result.size = read.len;
                            result.content = read.ptr;
                        } else |e| {
                            freeFileMemory(thread_context, mapped.ptr, file_size);
                            log.warn("File read failed: '{s}', error: {}", .{ path, e });
                        }
                    } else |e| {
                        log.warn("mprotect for file read failed, error: {}", .{e});
                    }
                } else |e| {
                    log.warn("mmap for file read failed, error: {}", .{e});
                }
            } else |e| {
                log.warn("Failed to stat file '{s}', error: {}", .{ path, e });
            }

            linux.close(fd) catch |e| {
                log.warn("Failed to close file '{s}', error: {}", .{ path, e });
            };
        } else |e| {
            log.warn("Failed to open file: '{s}', error: {}", .{ path, e });
        }

        return result;
    }

    pub fn writeEntireFile(thread_context: *ThreadContext, path: [*:0]const u8, path_len: usize, ptr: [*]const u8, size: usize) callconv(.c) bool {
        _ = thread_context;
        assert(std.mem.span(path).len == path_len);
        var result = false;

        const permissions = linux.S.IWUSR | linux.S.IRUSR | linux.S.IRGRP | linux.S.IROTH;

        if (linux.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, permissions)) |fd| {
            const buf = ptr[0..size];
            if (linux.write(fd, buf)) |written| {
                result = written == size;
            } else |e| {
                log.err("Failed to write to file: '{s}', error: {}", .{ path, e });
            }

            linux.close(fd) catch |e| {
                log.err("Failed to close file: '{s}', error: {}", .{ path, e });
            };
        } else |e| {
            log.err("Failed to open file: '{s}', error: {}", .{ path, e });
        }
        return result;
    }

    pub fn freeFileMemory(thread_context: *ThreadContext, ptr: ?[*]const u8, size: usize) callconv(.c) void {
        _ = thread_context;

        if (ptr) |m| {
            assert(size > 0);
            const memory: []align(linux.page_size) const u8 = @alignCast(m[0..size]);
            linux.munmap(memory) catch |e| {
                log.err("Failed to free file memory, error: {}", .{e});
            };
        }
    }

    pub fn drawVertical(buffer: *LinuxOffscreenBuffer, x: i32, top: i32, bottom: i32, color: u32) callconv(.c) void {
        var cursor: [*]u8 = buffer.memory.ptr + @as(usize, @intCast((x * bytes_per_pixel) + (top * buffer.pitch)));

        for (@intCast(top)..@intCast(bottom + 1)) |_| {
            const pixel: *u32 = @ptrCast(@alignCast(cursor));
            pixel.* = color;
            cursor += @intCast(buffer.pitch);
        }
    }
};

comptime {
    if (options.internal_build) {
        for (@typeInfo(DEBUG).@"struct".decls) |decl| {
            const decl_type = @TypeOf(@field(DEBUG, decl.name));
            const decl_type_info = @typeInfo(decl_type);
            if (decl_type_info == .@"fn") {
                @export(&@field(DEBUG, decl.name), .{ .name = decl.name, .linkage = .strong });
            }
        }
    }
}

fn handleWlRegisterGlobal(data: ?*anyopaque, registry_opt: ?*wl.Registry, name: u32, interface_name: [*:0]const u8, version: u32) callconv(.c) void {
    const wli: *WlInitData = @ptrCast(@alignCast(data));
    const registry = registry_opt.?;

    const Mapping = struct {
        []const u8,
        type,
    };

    const mappings = [_]Mapping{
        .{ "wl_shm", wl.Shm },
        .{ "wl_seat", wl.Seat },
        .{ "wl_compositor", wl.Compositor },
        .{ "xdg_wm_base", xdg_shell.WmBase },
        .{ "xdg_decoration_manager", xdg_decoration.DecorationManagerV1 },
    };

    var found = false;
    inline for (mappings) |map| {
        const target_field_name: []const u8 = map[0];
        const Interface: type = map[1];

        if (std.mem.eql(u8, std.mem.span(interface_name), std.mem.span(Interface.interface.name))) {
            @field(wli, target_field_name) = registry.bind(name, Interface, @min(version, Interface.interface.version));
            found = true;
            break;
        }
    }

    if (!found) {
        if (std.mem.eql(u8, "wl_output", std.mem.span(interface_name))) {
            var free_slot_found = false;
            for (&wld.outputs) |*output| {
                if (output.* == null) {
                    output.* = .{
                        .handle = registry.bind(name, wl.Output, @min(version, wl.Output.interface.version)).?,
                    };
                    free_slot_found = true;
                    break;
                }
            }

            if (!free_slot_found) {
                log.warn("Monitor capacity reached (8)! Ignoring monitor.", .{});
            }
        }
    }
}

fn handleWlRemoveGlobal(data: ?*anyopaque, registry: ?*wl.Registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;

    // TODO: Handle monitor hotplug?
    log.debug("Remove global: {}", .{name});
}

fn handleWlSurfaceEnter(data: ?*anyopaque, surface: ?*wl.Surface, current_output_object_opt: ?*wl.Object) callconv(.c) void {
    _ = .{ data, surface, current_output_object_opt };

    if (current_output_object_opt) |current_output_object| {
        const current_output: *wl.Output = @ptrCast(current_output_object);
        log.debug("Surface enter: {}", .{current_output});

        var found = false;
        for (&wld.outputs) |*output_opt| {
            if (output_opt.*) |*existing_output| {
                if (existing_output.handle == current_output) {
                    existing_output.active = true;
                    found = true;
                    break;
                }
            }
        }

        if (!found) {
            log.warn("Failed to find matching output: {*}", .{current_output_object_opt});
        }
    }
}

fn handleWlSurfaceLeave(data: ?*anyopaque, surface: ?*wl.Surface, current_output_object_opt: ?*wl.Object) callconv(.c) void {
    _ = .{ data, surface, current_output_object_opt };

    if (current_output_object_opt) |current_output_object| {
        const current_output: *wl.Output = @ptrCast(current_output_object);
        log.debug("Surface leave: {}", .{current_output});

        var found = false;
        for (&wld.outputs) |*output_opt| {
            if (output_opt.*) |*existing_output| {
                if (existing_output.handle == current_output) {
                    existing_output.active = false;
                    found = true;
                    break;
                }
            }
        }

        if (!found) {
            log.warn("Failed to find matching output: {*}", .{current_output_object_opt});
        }
    }
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
    _ = surface;

    log.debug("xdg surface configure: {}", .{serial});
    wld.pending_configure_serial = serial;
}

fn handleXdgToplevelConfigure(data: ?*anyopaque, toplevel: ?*xdg_shell.Toplevel, width: i32, height: i32, states: wayland.Array) callconv(.c) void {
    _ = data;
    _ = toplevel;
    _ = states;

    log.debug("xdg toplevel configure: {},{}", .{ width, height });

    wld.pending_resize = .{ .width = width, .height = height };
}

fn handleXdgToplevelConfigureBounds(data: ?*anyopaque, toplevel: ?*xdg_shell.Toplevel, width: i32, height: i32) callconv(.c) void {
    _ = data;
    _ = toplevel;

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
    _ = data;
    _ = toplevel;

    running = false;
}

fn handleWlCallbackDone(data: ?*anyopaque, callback: ?*wl.Callback, callback_data: u32) callconv(.c) void {
    _ = data;
    _ = callback_data;
    callback.?.destroy();

    wld.should_draw = true;
}

fn handleWlBufferRelease(data: ?*anyopaque, wl_buffer: ?*wl.Buffer) callconv(.c) void {
    _ = wl_buffer;
    const buffer: *WlBuffer = @ptrCast(@alignCast(data));

    if (buffer.width != wld.window_width or buffer.height != wld.window_height) {
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

fn handleWlKey(data: ?*anyopaque, keyboard: ?*wl.Keyboard, serial: u32, time: u32, rawkey: u32, state: wl.Keyboard.KeyState) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = time;
    _ = serial;

    // TODO: Do this via the keymap with xkb!
    const key: input.Key = @enumFromInt(rawkey);
    const was_down = state != .pressed;
    const is_down = state == .pressed or state == .repeated;

    const keyboard_controller = &wld.new_input.controllers[0];
    const buttons = &keyboard_controller.buttons.named;

    if (is_down != was_down) {
        if (key == .Q) {
            processKeyEvent(&buttons.left_shoulder, is_down);
        } else if (key == .E) {
            processKeyEvent(&buttons.right_shoulder, is_down);
        } else if (key == .W) {
            processKeyEvent(&buttons.move_up, is_down);
        } else if (key == .S) {
            processKeyEvent(&buttons.move_down, is_down);
        } else if (key == .A) {
            processKeyEvent(&buttons.move_left, is_down);
        } else if (key == .D) {
            processKeyEvent(&buttons.move_right, is_down);
        } else if (key == .UP) {
            processKeyEvent(&buttons.action_up, is_down);
        } else if (key == .DOWN) {
            processKeyEvent(&buttons.action_down, is_down);
        } else if (key == .LEFT) {
            processKeyEvent(&buttons.action_left, is_down);
        } else if (key == .RIGHT) {
            processKeyEvent(&buttons.action_right, is_down);
        } else if (key == .ESC) {
            processKeyEvent(&buttons.start, is_down);
        } else if (key == .SPACE) {
            processKeyEvent(&buttons.back, is_down);
        }

        if (options.internal_build and is_down) {
            if (key == .P) {
                pause = !pause;
            } else if (key == .L) {
                if (wld.shared_state.input_recording_index == 0 and
                    wld.shared_state.input_playing_index == 0)
                {
                    beginRecordingInput(wld.shared_state, wld.io, 1);
                } else if (wld.shared_state.input_recording_index == 1) {
                    endRecordingInput(wld.shared_state, wld.io);
                    beginInputPlayback(wld.shared_state, wld.io, 1);
                } else {
                    endInputPlayback(wld.shared_state, wld.io);
                    // TODO: Reset input, keys may be stuck in down state
                }
            } else if ((key == .ENTER and wld.key_mods_pressed.alt) or
                key == .F11)
            {
                toggleFullscreen();
            }
        }
    }
}

fn handleWlKeyModifiers(data: ?*anyopaque, keyboard: ?*wl.Keyboard, serial: u32, mods_depressed: u32, mods_latched: u32, mods_locked: u32, group: u32) callconv(.c) void {
    _ = .{ data, keyboard, serial, mods_depressed, mods_latched, mods_locked, group };

    wld.key_mods_pressed = @bitCast(mods_depressed);
    wld.key_mods_latched = @bitCast(mods_latched);
    wld.key_mods_locked = @bitCast(mods_locked);
}

fn toggleFullscreen() void {
    if (wld.fullscreen) {
        wld.toplevel.unset_fullscreen();
        wld.fullscreen = false;
    } else {
        // TODO: Preferred fullscreen monitor
        wld.toplevel.set_fullscreen(null);
        wld.fullscreen = true;
    }
}

fn handleWlPointerEnter(data: ?*anyopaque, pointer: ?*wl.Pointer, serial: u32, surface: ?*wl.Object, surface_x: wayland.Fixed, surface_y: wayland.Fixed) callconv(.c) void {
    _ = .{ data, pointer, serial, surface, surface_x, surface_y };

    wld.new_input.debug_mouse.x = surface_x.toInt();
    wld.new_input.debug_mouse.y = surface_y.toInt();

    // Hide cursor, if custom cursors are required use libwayland-cursor or cursor-shape protocol
    if (options.internal_build) {
        //
    } else {
        wld.pointer.set_cursor(serial, null, 0, 0);
    }
}

fn handleWlMouseMotion(data: ?*anyopaque, pointer: ?*wl.Pointer, time: u32, surface_x: wayland.Fixed, surface_y: wayland.Fixed) callconv(.c) void {
    _ = .{ data, pointer, time };

    wld.new_input.debug_mouse.x = surface_x.toInt();
    wld.new_input.debug_mouse.y = surface_y.toInt();
}

fn handleWlMouseButton(data: ?*anyopaque, pointer: ?*wl.Pointer, serial: u32, time: u32, raw_button: u32, state: wl.Pointer.ButtonState) callconv(.c) void {
    _ = .{ data, pointer, serial, time };

    const button: input.Key = @enumFromInt(raw_button);
    const was_down = state == .released;
    const is_down = state == .pressed;

    const mouse = &wld.new_input.debug_mouse;
    const buttons = &mouse.buttons.array;

    if (is_down != was_down) {
        const key_index_opt: ?usize = switch (button) {
            .BTN_LEFT => 0,
            .BTN_RIGHT => 1,
            .BTN_MIDDLE => 2,
            .BTN_SIDE => 3,
            .BTN_EXTRA => 4,
            else => null,
        };

        if (key_index_opt) |key_index| {
            processKeyEvent(&buttons[key_index], is_down);
        }
    }
}

fn handleWlMouseAxis(data: ?*anyopaque, pointer: ?*wl.Pointer, time: u32, axis: wl.Pointer.Axis, value: wayland.Fixed) callconv(.c) void {
    _ = .{ data, pointer, time, axis, value };
    // log.debug("mouse axis: {}:{}", .{ axis, value.toDouble() });
}

fn handleLibdecorConfigure(frame: *libdecor.Frame, config: *libdecor.Configuration, data: ?*anyopaque) callconv(.c) void {
    _ = data;

    var width: c_int = undefined;
    var height: c_int = undefined;
    if (!libdecor.configuration_get_content_size(config, frame, &width, &height)) {
        width = back_buffer_width;
        height = back_buffer_height;
    }

    const state = libdecor.state_new(width, height) orelse @panic("libdecor_state_new failed");
    libdecor.frame_commit(frame, state, config);
    libdecor.state_free(state);

    resize(width, height) catch |e| {
        log.err("Resize failed during libdecor configure: {}", .{e});
        std.process.exit(1);
    };

    wld.pending_configure_serial = 1;
    log.debug("decor configured {},{}", .{ width, height });
}

fn handleLibdecorClose(frame: *libdecor.Frame, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    _ = frame;
    running = false;
}

fn handleLibdecorDismissPopup(frame: *libdecor.Frame, seat_name: [*c]const u8, data: ?*anyopaque) callconv(.c) void {
    _ = frame;
    _ = data;
    log.debug("handleLibdecorDismissPopup seat: {s}", .{seat_name});
}

fn handleXdgDecorationConfigure(data: ?*anyopaque, toplevel_decoration: ?*xdg_decoration.ToplevelDecorationV1, mode: xdg_decoration.ToplevelDecorationV1.Mode) callconv(.c) void {
    _ = toplevel_decoration;
    log.debug("xdg_decoration configure: {}", .{mode});

    const mode_ptr: *?xdg_decoration.ToplevelDecorationV1.Mode = @ptrCast(@alignCast(data));
    mode_ptr.* = mode;
}
fn handleWlOutputGeometry(data: ?*anyopaque, output: ?*wl.Output, x: i32, y: i32, physical_width: i32, physical_height: i32, subpixel: wl.Output.Subpixel, make: [*:0]const u8, model: [*:0]const u8, transform: wl.Output.Transform) callconv(.c) void {
    _ = .{ data, output };
    log.debug("handleWlOutputGeometry: {},{},{},{},{},{s},{s},{}", .{ x, y, physical_width, physical_height, subpixel, make, model, transform });
}

fn handleWlOutputMode(data: ?*anyopaque, output: ?*wl.Output, flags: wl.Output.Mode, width: i32, height: i32, refresh: i32) callconv(.c) void {
    const output_data: *WlOutput = @ptrCast(@alignCast(data));
    assert(output_data.handle == output.?);
    output_data.refresh_mhz = refresh;

    log.debug("handleWlOutputMode: {},{},{},{}", .{ flags, width, height, refresh });

    const new_pixel_count = width * height;
    const max_pixel_count = wld.max_width * wld.max_height;
    if (new_pixel_count > max_pixel_count) {
        wld.max_width = width;
        wld.max_height = height;
        wld.should_resize_shm = true;
    }
}

fn addJoystick(io: std.Io, device: *udev.Device, devnode_path: [*:0]const u8) !void {
    log.debug("Adding joystick: '{s}'", .{devnode_path});

    const input_dev = udev.device_get_parent_with_subsystem_devtype(device, "input", null).?;
    const parent_syspath = std.mem.span(udev.device_get_syspath(input_dev).?);
    var driver_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const driver_path = try std.fmt.bufPrint(&driver_path_buffer, "{f}", .{std.fs.path.fmtJoin(&.{ parent_syspath, "device/driver" })});
    var driver_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const driver_name_len = try std.Io.Dir.readLinkAbsolute(io, driver_path, &driver_name_buffer);
    const driver_name = std.fs.path.basename(driver_name_buffer[0..driver_name_len]);

    const kind: Joystick.Kind = if (std.mem.eql(u8, driver_name, "xpad") or std.mem.eql(u8, driver_name, "xboxdrv"))
        .xbox
    else
        .default;

    var joystick_index_opt: ?usize = null;
    for (0..PollFdSlot.joystick_count) |ji| {
        const pollfd = &poll_fds[PollFdSlot.first_joystick + ji];
        if (pollfd.fd == -1) {
            joystick_index_opt = ji;
            break;
        }
    }

    if (joystick_index_opt) |ji| {
        const fd = linux.open(devnode_path, .{ .ACCMODE = .RDWR, .NONBLOCK = true }, 0) catch |e| {
            log.err("Opening controller evdev file failed, error: {}", .{e});
            return error.OpenFailed;
        };

        poll_fds[PollFdSlot.first_joystick + ji] = .{
            .fd = @intCast(fd),
            .events = linux.POLL.IN,
            .revents = undefined,
        };

        const joystick = &joysticks[ji];
        joystick.* = .{
            .fd = @intCast(fd),
            .active = true,
            .kind = kind,
        };

        const dnp = std.mem.span(devnode_path);
        assert(joystick.path.len > dnp.len + 1);
        @memcpy(joystick.path[0..dnp.len], dnp);
        joystick.path[dnp.len] = 0;

        switch (kind) {
            .default, .xbox => {
                inline for (std.meta.fields(input.Abs)) |axis| {
                    var abs_info: input.AbsInfo = undefined;
                    if (ioctl.ioctl(fd, input.EVIOCGABS(@enumFromInt(axis.value)), @intFromPtr(&abs_info))) |_| {
                        if (abs_info.maximum > abs_info.minimum) {
                            if (Joystick.absEventCodeToAxisIndex(kind, axis.value)) |axis_idx| {
                                joystick.axis_meta[axis_idx] = .{
                                    .min = abs_info.minimum,
                                    .max = abs_info.maximum,
                                    .deadzone = abs_info.flat,
                                };
                            }
                        }
                    } else |e| {
                        log.warn("ioctl EVIOCGABS failed for asix '{s}', error: {}", .{ axis.name, e });
                    }
                }
            },
        }
    } else {
        log.warn("A joystick was added, but there are no free slots!", .{});
    }
}

fn removeJoystick(device: *udev.Device, devnode_path: [*:0]const u8) void {
    _ = device;
    log.debug("Removing joystick: '{s}'", .{devnode_path});

    const dnp = std.mem.span(devnode_path);

    var joystick_index_opt: ?usize = null;
    for (&joysticks, 0..) |*js, ji| {
        if (std.mem.eql(u8, std.mem.span(@as([*:0]u8, @ptrCast(&js.path))), dnp)) {
            joystick_index_opt = ji;
            js.* = .{ .fd = -1, .active = false, .kind = undefined };
            break;
        } else {}
    }

    if (joystick_index_opt) |ji| {
        const js_pollfd = &poll_fds[PollFdSlot.first_joystick + ji];
        linux.close(js_pollfd.fd) catch |e| {
            log.err("Failed to close joystick file handle, error: {}", .{e});
        };
        js_pollfd.* = .{ .fd = -1, .events = undefined, .revents = undefined };
    } else {
        log.warn("Trying to remove a joystick, but is was never registered!", .{});
    }
}

/// Returns the devnode path if the device is a joystick, otherwise returns null.
fn udevDeviceIsJoystick(ctx: *udev.Context, device: *udev.Device) ?[*:0]const u8 {
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
                        if (udev.device_new_from_syspath(ctx, sib_syspath)) |sib_dev| {
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
        }

        if (is_joystick and !is_keyboard and !is_mouse) {
            return devnode_path;
        }
    }

    return null;
}

const AudioOutput = struct {
    frames_per_second: u32 = 0,
    frames_per_game_frame: u32 = 0,
    safety_frames: u32 = 0,
    drift_justification_offset: u32 = 0,

    last_underflow_index: i64 = -1,

    const Sample = AudioBuffer.Sample;
    const Frame = AudioBuffer.Frame;
};

// TODO: signal invalid pa_* variables on failure
fn initPulse(audio_output: *AudioOutput) error{PulseInitFailed}!void {
    pa.load();

    pa_ml = pa.threaded_mainloop_new() orelse {
        log.err("Pulse failed to create main loop", .{});
        return error.PulseInitFailed;
    };
    errdefer pa.threaded_mainloop_free(pa_ml);

    const ml_api = pa.threaded_mainloop_get_api(pa_ml) orelse {
        log.err("Pulse failed to get mainloop api", .{});
        return error.PulseInitFailed;
    };

    pa_ctx = pa.context_new(ml_api, "v10") orelse {
        log.err("Pulse failed to create context", .{});
        return error.PulseInitFailed;
    };
    errdefer pa.context_unref(pa_ctx);

    if (pa.context_connect(pa_ctx, null, .{}, null) < 0) {
        log.err("Pulse failed to connect context", .{});
        return error.PulseInitFailed;
    }
    errdefer pa.context_disconnect(pa_ctx);

    if (pa.threaded_mainloop_start(pa_ml) < 0) {
        log.err("Pulse failed to start mainloop", .{});
        return error.PulseInitFailed;
    }
    log.debug("Pulse main loop started", .{});

    pa.threaded_mainloop_lock(pa_ml);
    var cstate = pa.context_get_state(pa_ctx);
    pa.threaded_mainloop_unlock(pa_ml);
    while (cstate != .ready) {
        if (cstate == .failed or cstate == .terminated) {
            log.err("Pulse context failed to reach ready state!", .{});
            return error.PulseInitFailed;
        }

        pa.threaded_mainloop_wait(pa_ml);

        pa.threaded_mainloop_lock(pa_ml);
        cstate = pa.context_get_state(pa_ctx);
        pa.threaded_mainloop_unlock(pa_ml);
    }
    // log.debug("Pulse context reached ready state", .{});

    pa_sample_spec = .{
        .format = .s16le,
        .rate = audio_output.frames_per_second,
        .channels = 2,
    };

    pa_stream = pa.stream_new(pa_ctx, "v10", &pa_sample_spec, null) orelse {
        log.err("Pulse failed to create stream!", .{});
        return error.PulseInitFailed;
    };
    errdefer pa.stream_unref(pa_stream);
    // log.debug("Pulse stream created", .{});

    const attr = pa.BufferAttr{
        .max_length = std.math.maxInt(u32),
        .t_length = (audio_output.frames_per_game_frame + audio_output.safety_frames) * @sizeOf(AudioOutput.Frame),
        .pre_buf = 0,
        .min_req = (audio_output.frames_per_game_frame) * @sizeOf(AudioOutput.Frame),
        .frag_size = audio_output.frames_per_game_frame * @sizeOf(AudioOutput.Frame),
    };

    // log.debug("Pulse requested playback attributes: {}", .{attr});

    pa.threaded_mainloop_lock(pa_ml);
    if (pa.stream_connect_playback(pa_stream, null, &attr, .{
        .adjust_latency = false,
        .interpolate_timing = true,
        .auto_timing_update = true,
        .start_corked = true,
    }, null, null) < 0) {
        pa.threaded_mainloop_unlock(pa_ml);
        log.err("Pulse failed connect playback!", .{});
        return error.PulseInitFailed;
    }
    // log.debug("Pulse stream connected", .{});
    // log.debug("Pulse actual playback attributes: {}", .{attr});

    var sstate = pa.stream_get_state(pa_stream);
    pa.threaded_mainloop_unlock(pa_ml);

    while (sstate != .ready) {
        if (sstate == .failed or sstate == .terminated) {
            log.err("Pulse stream failed or terminated", .{});
            return error.PulseInitFailed;
        }

        pa.threaded_mainloop_lock(pa_ml);
        sstate = pa.stream_get_state(pa_stream);
        pa.threaded_mainloop_unlock(pa_ml);
    }
    log.debug("Pulse stream ready", .{});
}

/// Return value indicates if a wl_buffer was available, and thus if the offscreenbuffer was actually displayed
fn displayBufferInWindow(buffer: LinuxOffscreenBuffer) bool {

    // TODO:Don't remember why this is commented out... maybe causes issues on gnome, and waiting for a free buffer signals draw anyway?
    // if (wld.should_draw) {

    if (aquireFreeBuffer()) |wl_buffer| {
        const wl_buffer_ptr: [*]u8 = wld.shm_data.ptr + @as(usize, @intCast(wl_buffer.offset));
        const wl_buffer_pitch: usize = @intCast(wl_buffer.width * bytes_per_pixel);
        const wl_buffer_mem: []u8 = wl_buffer_ptr[0 .. wl_buffer_pitch * @as(usize, @intCast(wl_buffer.height))];

        if (options.internal_build) {
            @memset(@as([]u32, @ptrCast(@alignCast(wl_buffer_mem))), 0);
        }

        if (wld.double_scale) {
            const dest_line_length: usize = @intCast(@min(buffer.width * 2, wl_buffer.width) * bytes_per_pixel);
            const source_line_length: usize = @intCast(@min(buffer.width, @divTrunc(wl_buffer.width, 2)) * bytes_per_pixel);

            const source_row_count: usize = @intCast(@min(buffer.height, @divTrunc(wl_buffer.height, 2)));

            for (0..source_row_count) |src_y| {
                const source_offset = src_y * @as(usize, @intCast(buffer.pitch));
                const source_line: []u32 = @ptrCast(@alignCast(buffer.memory[source_offset .. source_offset + source_line_length]));

                const dst_y = src_y * 2;
                const dest_offset1 = dst_y * wl_buffer_pitch;
                const dest_line1: []u32 = @ptrCast(@alignCast(wl_buffer_mem[dest_offset1 .. dest_offset1 + dest_line_length]));
                const dest_offset2 = dest_offset1 + wl_buffer_pitch;
                const dest_line2: []u32 = @ptrCast(@alignCast(wl_buffer_mem[dest_offset2 .. dest_offset2 + dest_line_length]));

                for (0..source_line.len) |src_x| {
                    const dst_x = src_x * 2;

                    dest_line1[dst_x] = source_line[src_x];
                    dest_line1[dst_x + 1] = source_line[src_x];
                    dest_line2[dst_x] = source_line[src_x];
                    dest_line2[dst_x + 1] = source_line[src_x];
                }
            }
        } else {

            // TODO: Offset mouse position by this
            const x_offset = 10;
            const y_offset = 10;

            const line_length: usize = @intCast(@min(buffer.width, wl_buffer.width - x_offset) * bytes_per_pixel);
            const row_count: usize = @intCast(@min(buffer.height, wl_buffer.height - y_offset));

            // NOTE: This could be a single memcopy if:
            //  - We reallocate the offscreen_buffer in the same way as the wayland buffers (same size).
            //  - UpdateAndRender is passed an offscreen buffer where width and height are static (logical back buffer size).
            //  - UpdateAndRender is passed an offscreen buffer where the pitch matches the size of a line in the actual buffers.
            //  - We enforce the logical back buffer size as the minimum window size (orelse the game will write out of bounds).
            //
            //  I might actually prefer that, but for now this matches hh on win32.
            const y_off: usize = @intCast(y_offset);
            const x_off: usize = @intCast(x_offset);
            for (y_off..y_off + row_count, 0..row_count) |dst_y, src_y| {
                const dest_offset = (dst_y * wl_buffer_pitch) + (x_off * bytes_per_pixel);
                const dest_line = wl_buffer_mem[dest_offset .. dest_offset + line_length];

                const source_offset = src_y * @as(usize, @intCast(buffer.pitch));
                const source_line = buffer.memory[source_offset .. source_offset + line_length];

                @memcpy(dest_line, source_line);
            }
        }

        displayWaylandBufferInWindow(wl_buffer);
        return true;
    } else {
        _ = wl.display_roundtrip(wld.display);
        log.warn("Failed to aquire wayland buffer!", .{});
        // unreachable; // might want to loop util a buffer is aquired
        // continue;
        return false;
    }
    // }
}

fn displayWaylandBufferInWindow(buffer: *WlBuffer) void {
    wld.surface.attach(buffer.handle, 0, 0);

    if (options.internal_build) {
        wld.surface.damage(0, 0, buffer.width, buffer.height);
    } else {
        const width, const height = if (wld.double_scale)
            .{ global_back_buffer.width * 2, global_back_buffer.height * 2 }
        else
            .{ global_back_buffer.width, global_back_buffer.height };

        wld.surface.damage(0, 0, @min(buffer.width, width), @min(buffer.height, height));
    }

    wld.surface.commit();
    const callback = wld.surface.frame();
    callback.?.add_listener(&wl_callback_listener, &wld);
    _ = wl.display_flush(wld.display);

    wld.should_draw = false;
}

pub fn beginRecordingInput(shared_state: *platform.SharedState, io: std.Io, input_recording_index: usize) void {
    const replay_buffer = shared_state.getReplayBuffer(input_recording_index);

    if (replay_buffer.memory.len == shared_state.game_memory_block.len) {
        shared_state.input_recording_index = input_recording_index;

        var file_name_buf: [std.Io.Dir.max_name_bytes]u8 = undefined;
        const file_name = shared_state.getInputRecordingPath(&file_name_buf, true, input_recording_index);

        shared_state.recording_handle = std.Io.Dir.createFileAbsolute(io, file_name, .{}) catch @panic("Input recording file creation failed");

        @memcpy(replay_buffer.memory, shared_state.game_memory_block);
    } else log.warn("Invalid recording buffer: {}", .{input_recording_index});
}

pub fn endRecordingInput(shared_state: *platform.SharedState, io: std.Io) void {
    if (shared_state.input_recording_index != 0) {
        shared_state.recording_handle.close(io);
        shared_state.input_recording_index = 0;
    }
}

pub fn beginInputPlayback(shared_state: *platform.SharedState, io: std.Io, input_playing_index: usize) void {
    const replay_buffer = shared_state.getReplayBuffer(input_playing_index);

    if (replay_buffer.memory.len == shared_state.game_memory_block.len) {
        shared_state.input_playing_index = input_playing_index;

        var file_name_buf: [std.Io.Dir.max_name_bytes]u8 = undefined;
        const file_name = shared_state.getInputRecordingPath(&file_name_buf, true, input_playing_index);

        shared_state.playback_handle = std.Io.Dir.openFileAbsolute(io, file_name, .{ .mode = .read_only }) catch @panic("Input playback file open failed");

        @memcpy(shared_state.game_memory_block, replay_buffer.memory);
    } else log.warn("Invalid replay buffer: {}", .{input_playing_index});
}

pub fn endInputPlayback(shared_state: *platform.SharedState, io: std.Io) void {
    if (shared_state.input_playing_index != 0) {
        shared_state.playback_handle.close(io);
        shared_state.input_playing_index = 0;
    }
}

pub fn recordInput(shared_state: *platform.SharedState, io: std.Io, new_input: *Input) void {
    shared_state.recording_handle.writeStreamingAll(io, @ptrCast(new_input)) catch @panic("Input recording write failed");
}

pub fn playbackInput(shared_state: *platform.SharedState, io: std.Io, new_input: *Input) void {
    const bytes_read = shared_state.playback_handle.readStreaming(io, &.{@as([]u8, @ptrCast(new_input))}) catch |e| switch (e) {
        error.EndOfStream => 0,
        else => @panic("Input playback read failed"),
    };

    if (bytes_read == 0) {
        const index = shared_state.input_playing_index;

        endInputPlayback(shared_state, io);
        beginInputPlayback(shared_state, io, index);

        _ = shared_state.playback_handle.readStreaming(io, &.{@as([]u8, @ptrCast(new_input))}) catch @panic("Input playback read failed");
    }
}

fn nop() callconv(.c) void {}

const wl_registry_listener = wl.Registry.Listener{
    .global = handleWlRegisterGlobal,
    .global_remove = handleWlRemoveGlobal,
};

const wl_shm_listener = wl.Shm.Listener{
    .format = handleWlShmFormat,
};

const wl_surface_listener = wl.Surface.Listener{
    .enter = handleWlSurfaceEnter,
    .leave = handleWlSurfaceLeave,
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
    .modifiers = handleWlKeyModifiers,
    .repeat_info = @ptrCast(&nop),
    .keymap = @ptrCast(&nop),
};

const wl_mouse_listener = wl.Pointer.Listener{
    .enter = handleWlPointerEnter,
    .leave = @ptrCast(&nop),
    .motion = handleWlMouseMotion,
    .button = handleWlMouseButton,
    .axis = handleWlMouseAxis,
    .frame = @ptrCast(&nop), // TODO: Use this to handle incoming data correctly in relation to frame boundaries
    .axis_discrete = @ptrCast(&nop),
    .axis_source = @ptrCast(&nop),
    .axis_stop = @ptrCast(&nop),
    .axis_value120 = @ptrCast(&nop),
    .axis_relative_direction = @ptrCast(&nop),
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
    .geometry = handleWlOutputGeometry,
    .mode = handleWlOutputMode,
    .done = @ptrCast(&nop),
    .scale = @ptrCast(&nop),
    .name = @ptrCast(&nop),
    .description = @ptrCast(&nop),
};
