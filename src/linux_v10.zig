const std = @import("std");
const log = std.log.scoped(.linux_v10);
const mem = @import("mem");
const options = @import("options");
const linux_options = @import("linux_options");
const builtin = @import("builtin");
const DynLib = @import("dynlib");
const asset_compiler = @import("asset_compiler");

const platform = @import("v10_platform.zig");

const arch = @import("arch").arch;

const wayland = @import("wayland");
const wlc = wayland.client;
const wl = wayland.wayland;
const xdg_shell = wayland.xdg_shell;
const xdg_decoration = wayland.xdg_decoration_unstable_v1;

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
// TODO: Debug repeated controller plug in/out cycles, the disconnect seems to be missed sometimes

const assert = std.debug.assert;

var prng: std.Random = undefined;

const back_buffer_width: i32 = 960;
const back_buffer_height: i32 = 540;
const bytes_per_pixel = 4;

var global_back_buffer: LinuxOffscreenBuffer = .{};
var running: bool = false;
var pause: bool = false;
var wld: WlData = .{};

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

var stderr_buf: [2048]u8 = undefined;
var stderr: *std.Io.Writer = undefined;
var stdout_buf: [2048]u8 = undefined;
var stdout: *std.Io.Writer = undefined;

pub const std_options = platform.std_options;

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
        .environ = init.environ,
    });
    defer threaded.deinit();

    const io = threaded.io();

    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buf);
    stderr = &stderr_writer.interface;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    stdout = &stdout_writer.interface;
    defer {
        stderr.flush() catch {};
        stdout.flush() catch {};
    }

    defer {
        if (use_debug_allocator) {
            _ = debug_allocator.detectLeaks();
            _ = debug_allocator.deinit();
        }
    }

    var thread_context: ThreadContext = .{
        .io = &io,
    };

    try platform.runAssetCompiler(io, gpa, stderr, stdout);

    const prng_seed = std.Io.Timestamp.now(io, .real).toNanoseconds();
    var prng_impl = std.Random.DefaultPrng.init(@intCast(prng_seed));
    prng = prng_impl.random();

    var shared_state: platform.SharedState = .{};

    const cwd_len = try std.process.currentPath(io, &shared_state.cwd_buf);
    shared_state.cwd = shared_state.cwd_buf[0..cwd_len];
    log.debug("cwd: '{s}'", .{shared_state.cwd});

    const exe_dir_path_len = try std.process.executableDirPath(io, &shared_state.exe_dir_path_buf);
    shared_state.exe_dir_path = shared_state.exe_dir_path_buf[0..exe_dir_path_len];
    log.debug("exe_dir_path: {s}", .{shared_state.exe_dir_path});

    var game_lib_name_buf: [std.Io.Dir.max_path_bytes]u8 = @splat(0);
    const game_lib_name = try shared_state.buildExePathFilename(&game_lib_name_buf, "libv10_game.so");
    log.debug("game_lib_name: {s}", .{game_lib_name});

    const display = wlc.displayConnect(null, &init.environ) orelse {
        log.err("wl_display_connect failed", .{});
        return error.UnexpectedWayland;
    };
    defer wlc.displayDisconnect(display);
    log.debug("Display connected", .{});

    const wl_registry = display.getRegistry();

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
        linux.mprotect(mapped, .{ .READ = true, .WRITE = true }) catch |e| {
            log.err("mprotect call failed during back buffer resize", .{});
            return e;
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
    wl_registry.addListener(&wl_registry_listener, &wli);
    if (wlc.displayRoundtrip(display) == -1) {
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
    if (wli.wl_data_device_manager) |ddm| wld.data_device_manager = ddm else {
        log.err("wl_data_device_manager not available", .{});
        return error.UnexpectedWayland;
    }
    defer wld.data_device_manager.destroy();

    wld.data_device = wld.data_device_manager.getDataDevice(wld.seat);
    defer wld.data_device.release();
    wld.data_device.addListener(&wl_data_device_listener, null);

    _ = wlc.displayRoundtrip(wld.display); // Wait for max_width/height to be set

    log.debug("Format available", .{});
    log.debug("Seat capabilities: {}", .{wli.seat_capabilities});
    log.debug("Max size: {},{}", .{ wld.max_width, wld.max_height });

    wld.window_width = @as(f32, @floatFromInt(back_buffer_width)) * 1.5;
    wld.window_height = @as(f32, @floatFromInt(back_buffer_height)) * 1.5;

    try alloc_shm();

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

    wld.surface = wld.compositor.createSurface();
    wld.surface.addListener(&wl_surface_listener, null);

    const app_id = "v10";
    const title = "v10";

    wld.toplevel = blk: {
        const xdg_surface = wld.wm_base.getXdgSurface(wld.surface);
        xdg_surface.addListener(&xdg_surface_listener, &wld);

        const xdg_toplevel = xdg_surface.getToplevel();
        xdg_toplevel.addListener(&xdg_toplevel_listener, &wld);

        log.debug("xdg_toplevel: {}", .{xdg_toplevel});
        xdg_toplevel.setAppId(app_id);
        xdg_toplevel.setTitle(title);
        wld.surface.commit();

        if (wli.xdg_decoration_manager) |manager| {
            const toplevel_decoration = manager.getToplevelDecoration(xdg_toplevel);
            toplevel_decoration.setMode(.serverSide);

            var xdg_decoration_mode: ?xdg_decoration.ToplevelDecorationV1.Mode = null;
            toplevel_decoration.addListener(&xdg_decoration_listener, &xdg_decoration_mode);

            _ = wlc.displayRoundtrip(wld.display);
            xdg_surface.ackConfigure(wld.pending_configure_serial.?);
            wld.pending_configure_serial = null;

            if (xdg_decoration_mode == .serverSide) {
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

        log.debug("xdg_decoration not supported, falling back to no decorations", .{});

        _ = wlc.displayRoundtrip(wld.display);
        wld.pending_configure_serial = null;

        break :blk .{ .no_decoration = .{ .xdg_surface = xdg_surface, .xdg_toplevel = xdg_toplevel } };
    };

    const buffer = aquireFreeBuffer().?;
    displayWaylandBufferInWindow(buffer);

    var monitor_hz: f32 = 60;

    for (wld.outputs, 0..) |output_opt, i| if (output_opt) |output| {
        log.debug("outputs[{}]: {}", .{ i, output });
        if (output.active) monitor_hz = @min(monitor_hz, @as(f32, @floatFromInt(output.refresh_mhz)) / 1000);
    };

    log.debug("monitor hz: {}", .{monitor_hz});

    const game_update_hz: f32 = monitor_hz / 2;
    // const game_update_hz: f32 = 20;
    log.debug("game update hz: {}", .{game_update_hz});
    const target_seconds_per_frame: f32 = 1.0 / game_update_hz;

    wld.keyboard = wld.seat.getKeyboard();
    wld.keyboard.addListener(&wl_keyboard_listener, &wld);

    wld.pointer = wld.seat.getPointer();
    wld.pointer.addListener(&wl_mouse_listener, &wld);

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
        linux.mprotect(all_memory, .{ .READ = true, .WRITE = true }) catch |e| {
            log.err("mprotect call for game memory storage failed", .{});
            return e;
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

    var game_code = GameCode.load(io, game_lib_name);

    const audio_fps = 48000;
    const audio_buffer_byte_size = audio_fps * @sizeOf(AudioBuffer.Frame);

    const audio_buffer = switch (linux_options.linux_audio_impl) {
        .pulseEmulateDSound => blk: {
            const buf = linux.mmap(null, audio_buffer_byte_size, .{}, .{
                .TYPE = .PRIVATE,
                .ANONYMOUS = true,
            }, -1, 0) catch |e| {
                log.err("mmap for audio buffer failed: {}", .{e});
                return e;
            };
            linux.mprotect(buf, .{ .READ = true, .WRITE = true }) catch |e| {
                log.err("mprotect for audio buffer failed: {}", .{e});
                return e;
            };
            break :blk buf;
        },

        .pulsePull => void,
    };

    var audio_output: AudioOutput = blk: {
        const frames_per_video_frame: u32 = @intFromFloat(audio_fps / game_update_hz);
        break :blk .{
            .frames_per_second = audio_fps,
            .frames_per_video_frame = frames_per_video_frame,
            .bytes_per_video_frame = frames_per_video_frame * @sizeOf(AudioOutput.Frame),

            .pulse = .{ .impl = switch (linux_options.linux_audio_impl) {
                .pulseEmulateDSound => .{
                    .safety_frame_bytes = @max(1024, @as(u32, @intFromFloat((audio_fps / game_update_hz) / 3)) * @sizeOf(AudioOutput.Frame)),
                    .running_frame_index = 0,
                    .read_cursor = 0,
                    .buffer = audio_buffer,
                },
                .pulsePull => .{
                    .thread_context = &thread_context,
                    .game_code = &game_code,
                    .game_memory = &game_memory,
                },
            } },
        };
    };
    const pulse = &audio_output.pulse.impl;

    try pulse.init(audio_output.frames_per_second, "v10");

    wld.new_input = &wld.game_input[0];
    wld.old_input = &wld.game_input[1];

    pulse.start();

    var last_counter = getWallClock(io);
    var flip_wall_clock = getWallClock(io);

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

        if (wlc.displayDispatch(display) == -1) {
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

            if (game_code.updateAndRender) |updateAndRender| updateAndRender(&thread_context, &game_memory, wld.new_input, &game_offscreen_buffer);

            if (linux_options.linux_audio_impl == .pulseEmulateDSound) {
                const audio_wall_clock = getWallClock(io);
                const from_begin_to_audio_seconds = getSecondsElapsed(flip_wall_clock, audio_wall_clock);

                const cursor = pulse.getCurrentPosition(audio_output.frames_per_second);

                if (!pulse.audio_valid) {
                    pulse.running_frame_index = cursor.write / @sizeOf(AudioOutput.Frame);
                    pulse.audio_valid = true;
                }

                var byte_to_lock = (pulse.running_frame_index *% @sizeOf(AudioOutput.Frame)) % pulse.buffer.len;

                const valid_bytes = (byte_to_lock + pulse.buffer.len - cursor.write) % pulse.buffer.len;

                if (valid_bytes > pulse.buffer.len / 2) {
                    log.warn("Audio ringbuffer underflow! (btl:{} - wc: {})", .{ byte_to_lock, cursor.write });

                    pulse.running_frame_index = (cursor.write + pulse.safety_frame_bytes) / @sizeOf(AudioOutput.Frame);

                    byte_to_lock = (pulse.running_frame_index *% @sizeOf(AudioOutput.Frame)) % pulse.buffer.len;
                }

                const seconds_left_until_flip = target_seconds_per_frame - from_begin_to_audio_seconds;
                const expected_frames_until_flip: usize = @intFromFloat(@max(0, seconds_left_until_flip * @as(f32, @floatFromInt(audio_output.frames_per_second))));
                const expected_bytes_until_flip = expected_frames_until_flip * @sizeOf(AudioOutput.Frame);
                const expected_frame_boundary_byte = cursor.play + expected_bytes_until_flip;

                var safe_write_cursor: usize = cursor.write;
                if (safe_write_cursor < cursor.play) {
                    safe_write_cursor += pulse.buffer.len;
                }
                safe_write_cursor += pulse.safety_frame_bytes;

                const audio_card_is_low_latency = safe_write_cursor < expected_frame_boundary_byte;

                var target_cursor: usize = 0;
                if (audio_card_is_low_latency) {
                    target_cursor = expected_frame_boundary_byte + audio_output.bytes_per_video_frame;
                } else {
                    target_cursor = safe_write_cursor + audio_output.bytes_per_video_frame;
                }

                target_cursor = target_cursor % pulse.buffer.len;

                const bytes_to_write =
                    if (byte_to_lock > target_cursor)
                        (pulse.buffer.len - byte_to_lock) + target_cursor
                    else
                        target_cursor - byte_to_lock;

                if (bytes_to_write > 0) {
                    if (game_code.getAudioFrames) |getAudioFrames| {
                        const bytes_to_end = pulse.buffer.len - byte_to_lock;

                        if (bytes_to_write <= bytes_to_end) {
                            const frames: []AudioOutput.Frame = @ptrCast(@alignCast(pulse.buffer[byte_to_lock .. byte_to_lock + bytes_to_write]));

                            var game_sound_output_buffer: AudioBuffer = .{
                                .frames = frames.ptr,
                                .frames_len = frames.len,
                                .frames_per_second = @intCast(audio_output.frames_per_second),
                            };

                            getAudioFrames(&thread_context, &game_memory, &game_sound_output_buffer);
                        } else {
                            var frames: []AudioOutput.Frame = @ptrCast(@alignCast(pulse.buffer[byte_to_lock..]));

                            var game_sound_output_buffer: AudioBuffer = .{
                                .frames = frames.ptr,
                                .frames_len = frames.len,
                                .frames_per_second = @intCast(audio_output.frames_per_second),
                            };

                            getAudioFrames(&thread_context, &game_memory, &game_sound_output_buffer);

                            frames = @ptrCast(@alignCast(pulse.buffer[0 .. bytes_to_write - bytes_to_end]));
                            game_sound_output_buffer.frames = frames.ptr;
                            game_sound_output_buffer.frames_len = frames.len;

                            getAudioFrames(&thread_context, &game_memory, &game_sound_output_buffer);
                        }
                    }

                    pulse.running_frame_index +%= bytes_to_write / @sizeOf(AudioBuffer.Frame);
                }

                if (options.internal_build) {
                    var unwraped_write_cursor: usize = cursor.write;
                    if (unwraped_write_cursor < cursor.play) {
                        unwraped_write_cursor += pulse.buffer.len;
                    }
                    const audio_latency_bytes = unwraped_write_cursor - cursor.play;
                    const audio_latency_seconds = @as(f32, @floatFromInt(audio_latency_bytes / @sizeOf(AudioBuffer.Frame))) / @as(f32, @floatFromInt(audio_output.frames_per_second));

                    // log.debug("BTL:{} TC:{} BTW:{} - PC:{} WC:{} SWC:{} EFBB:{} -  DELTA:{} ({d:.3}) LL:{}", .{
                    //     byte_to_lock,
                    //     target_cursor,
                    //     bytes_to_write,
                    //     cursor.play,
                    //     cursor.write,
                    //     safe_write_cursor,
                    //     expected_frame_boundary_byte,
                    //     audio_latency_bytes,
                    //     audio_latency_seconds,
                    //     audio_card_is_low_latency,
                    // });

                    _ = .{audio_latency_seconds};
                }
            } else {
                assert(linux_options.linux_audio_impl == .pulsePull);

                if (options.internal_build) {
                    var pa_latency_usec: pa.USec = undefined;

                    pa.threaded_mainloop_lock(audio_output.pulse.main_loop);
                    _ = pa.stream_get_latency(audio_output.pulse.stream, &pa_latency_usec, null);
                    pa.threaded_mainloop_unlock(audio_output.pulse.main_loop);

                    const pa_latency_frames: u32 = @intCast((pa_latency_usec * audio_output.frames_per_second) / std.time.us_per_s);
                    const pa_latency_bytes: u32 = pa_latency_frames * @sizeOf(AudioOutput.Frame);

                    log.debug("audio latency: {} - {:.3}s", .{ pa_latency_bytes, @as(f32, @floatFromInt(pa_latency_usec)) / std.time.us_per_s });
                }
            }

            const wayland_blit = displayBufferInWindow(global_back_buffer);

            const work_counter = getWallClock(io);
            const work_seconds_elapsed = getSecondsElapsed(last_counter, work_counter);

            var seconds_elapsed_for_frame = getSecondsElapsed(last_counter, getWallClock(io));
            if (seconds_elapsed_for_frame <= target_seconds_per_frame) {
                while (seconds_elapsed_for_frame < target_seconds_per_frame) {
                    const sleep_ms: u64 = @intFromFloat(std.time.ms_per_s * (target_seconds_per_frame - seconds_elapsed_for_frame));

                    if (sleep_ms > 1) {
                        const s = (sleep_ms * std.time.ns_per_ms) - (std.time.ns_per_ms / 2);
                        try std.Io.sleep(io, std.Io.Duration.fromNanoseconds(s), .real);
                        // _ = wlc.displayDispatchTimeout(display, @intCast(sleep_ms));
                    } else {
                        std.atomic.spinLoopHint();
                    }

                    seconds_elapsed_for_frame = getSecondsElapsed(last_counter, getWallClock(io));
                }
            } else {
                log.warn("Missed frame time! ({})", .{seconds_elapsed_for_frame * std.time.ms_per_s});
            }

            const end_counter = getWallClock(io);
            const ms_per_frame = std.time.ms_per_s * getSecondsElapsed(last_counter, end_counter);
            last_counter = end_counter;

            const tmp = wld.new_input;
            wld.new_input = wld.old_input;
            wld.old_input = tmp;

            const end_cycle_count = arch.rdtsc();
            const cycles_elapsed: f32 = @floatFromInt(end_cycle_count - last_cycle_count);
            last_cycle_count = end_cycle_count;

            flip_wall_clock = getWallClock(io);

            const fps = std.time.ms_per_s / ms_per_frame;
            const mcpf = cycles_elapsed / (1000 * 1000);
            // log.info("{d:.2}ms/f,  {d:.2}f/s,  {d:.2}mc/f,  {d:.2}wms, wl_blit:{}", .{
            //     ms_per_frame,
            //     fps,
            //     mcpf,
            //     work_seconds_elapsed * std.time.ms_per_s,
            //     wayland_blit,
            // });
            _ = .{ ms_per_frame, fps, mcpf, wayland_blit, work_seconds_elapsed };

            // var title_buf: [32]u8 = undefined;
            // const t = try std.fmt.bufPrintSentinel(&title_buf, "{}", .{ms_per_frame}, 0);
            // wld.toplevel.setTitle(t);
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

    wl_data_device_manager: ?*wl.DataDeviceManager = null,
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

    data_device_manager: *wl.DataDeviceManager = undefined,
    data_device: *wl.DataDevice = undefined,

    pending_data_offer: ?*wl.DataOffer = null,
    active_selection_offer: ?*wl.DataOffer = null,
    active_dnd_offer: ?*wl.DataOffer = null,
    active_dnd_source_actions: wl.DataDeviceManager.DndAction = .{},
    active_dnd_action: wl.DataDeviceManager.DndAction = .{},

    pending_offer_mime_weight: u8 = 0,
    pending_offer_mime: ?[]const u8 = null,
    selection_mime: ?[]const u8 = null,
    dnd_mime: ?[]const u8 = null,

    pending_offer_mime_buffer: [256]u8 = @splat(0),
    selection_mime_buffer: [256]u8 = @splat(0),
    dnd_mime_buffer: [256]u8 = @splat(0),

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
    pitch: i32,
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

    pub fn setTitle(this: *WlToplevel, title: [:0]const u8) void {
        switch (this.*) {
            .no_decoration => |t| t.xdg_toplevel.setTitle(title),
            .xdg_decoration => |t| t.xdg_toplevel.setTitle(title),
        }
    }

    pub fn set_fullscreen(this: *WlToplevel, output: ?*wl.Output) void {
        switch (this.*) {
            .no_decoration => |t| t.xdg_toplevel.setFullscreen(output),
            .xdg_decoration => |t| t.xdg_toplevel.setFullscreen(output),
        }
    }

    pub fn unset_fullscreen(this: *WlToplevel) void {
        switch (this.*) {
            .no_decoration => |t| t.xdg_toplevel.unsetFullscreen(),
            .xdg_decoration => |t| t.xdg_toplevel.unsetFullscreen(),
        }
    }

    pub fn ack_configure(this: *WlToplevel, serial: u32) void {
        switch (this.*) {
            .no_decoration => |t| t.xdg_surface.ackConfigure(serial),
            .xdg_decoration => |t| t.xdg_surface.ackConfigure(serial),
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

fn alloc_shm() ShmError!void {
    const S = linux.S;

    assert(wld.shm_data.len == 0);

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

    assert(shm_size > 0);
    if (linux.mmap(null, shm_size, prot, map, fd, 0)) |mapped| {
        wld.shm_data = mapped;

        assert(wld.pool == null);

        const pool = wld.shm.createPool(fd, @intCast(wld.shm_data.len));
        wld.pool = pool;

        var width = wld.window_width;
        var height = wld.window_height;
        if (width == -1 and height == -1) {
            width = back_buffer_width;
            height = back_buffer_height;
        }
        const pitch = width * bytes_per_pixel;

        var offset: i32 = 0;
        for (&wld.buffers) |*buffer| {
            const handle = pool.createBuffer(offset, width, height, pitch, .xrgb8888);

            buffer.* = .{
                .handle = handle,
                .offset = offset,
                .free = true,
                .width = width,
                .height = height,
                .pitch = pitch,
            };
            handle.addListener(&wl_buffer_listener, buffer);

            offset += @intCast(buffer_size);
        }
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
    const pool = wld.pool.?;

    for (&wld.buffers) |*buffer| {
        if (buffer.free) {
            if (buffer.handle == null or buffer.width != wld.window_width or buffer.height != wld.window_height) {
                if (buffer.handle) |h| h.destroy();

                const pitch = wld.window_width * bytes_per_pixel;

                const new_buf = pool.createBuffer(buffer.offset, wld.window_width, wld.window_height, pitch, .xrgb8888);

                buffer.* = .{
                    .handle = new_buf,
                    .offset = buffer.offset,
                    .width = wld.window_width,
                    .height = wld.window_height,
                    .pitch = pitch,
                    .free = false,
                };

                new_buf.addListener(&wl_buffer_listener, buffer);
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
                    if (linux.mprotect(mapped, .{ .READ = true, .WRITE = true })) {
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

    // TODO: Streaming, cancel-able version
    // - If this needs to support pasting (like ctrl-v), this result needs to be
    //    kept around, and associated with the data offer.
    pub fn readClipboard() callconv(.c) void {
        if (wld.active_selection_offer) |offer| {
            assert(wld.selection_mime != null);

            var fds: [2]linux.fd_t = undefined;
            // TODO: Add NONBLOCK when making this streaming
            linux.pipe2(&fds, .{ .CLOEXEC = true }) catch @panic("Pipe creation failed!");

            const read_fd = fds[0];
            const write_fd = fds[1];
            defer linux.close(read_fd) catch unreachable;

            offer.receive(wld.selection_mime.?, write_fd);
            linux.close(write_fd) catch unreachable;

            var buf: [4096]u8 = undefined;
            if (linux.read(read_fd, &buf)) |clip_str| {
                assert(clip_str.len < buf.len); // Buffer too small ()
                log.debug("Clipboard: \"{s}\"", .{clip_str});
            } else |e| switch (e) {
                error.EndOfFile => log.debug("Clipboard empty...", .{}),
                else => {
                    log.err("Clipboard read error: {}", .{e});
                    @panic("Clipboard read error");
                },
            }
        }
    }

    pub fn readDnd() callconv(.c) void {
        if (wld.active_dnd_offer) |offer| {
            assert(wld.dnd_mime != null);

            var fds: [2]linux.fd_t = undefined;
            linux.pipe2(&fds, .{ .CLOEXEC = true }) catch @panic("Pipe creation failed!");

            const read_fd = fds[0];
            const write_fd = fds[1];
            defer linux.close(read_fd) catch unreachable;

            offer.receive(wld.dnd_mime.?, write_fd);
            linux.close(write_fd) catch unreachable;
            defer offer.finish();

            var buf: [4096]u8 = undefined;
            if (linux.read(read_fd, &buf)) |clip_str| {
                assert(clip_str.len < buf.len - 1);
                log.debug("DND: \"{s}\"", .{clip_str});
            } else |e| switch (e) {
                error.EndOfFile => log.debug("DND empty...", .{}),
                else => {
                    log.err("DND read error: {}", .{e});
                    @panic("DND read error");
                },
            }
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

fn handleWlRegisterGlobal(data: ?*anyopaque, registry: *wl.Registry, name: u32, interface_name: []const u8, version: u32) void {
    const wli: *WlInitData = @ptrCast(@alignCast(data));

    const Mapping = struct {
        []const u8,
        type,
        ?*const anyopaque,
    };

    const mappings = [_]Mapping{
        .{ "wl_shm", wl.Shm, &wl_shm_listener },
        .{ "wl_seat", wl.Seat, &wl_seat_listener },
        .{ "wl_compositor", wl.Compositor, null },
        .{ "xdg_wm_base", xdg_shell.WmBase, &xdg_wm_base_listener },
        .{ "xdg_decoration_manager", xdg_decoration.DecorationManagerV1, null },

        .{ "wl_data_device_manager", wl.DataDeviceManager, null },
    };

    var found = false;
    inline for (mappings) |map| {
        const target_field_name: []const u8 = map[0];
        const Interface: type = map[1];

        if (std.mem.eql(u8, interface_name, Interface.interface.name)) {
            log.debug("handleWlRegisterGlobal: {s}", .{interface_name});
            const proxy = registry.bindTyped(Interface, name, version);
            @field(wli, target_field_name) = proxy;
            found = true;

            if (map[2]) |listener| {
                proxy.addListener(@ptrCast(@alignCast(listener)), wli);
            }
            break;
        }
    }

    if (!found) {
        if (std.mem.eql(u8, "wl_output", interface_name)) {
            log.debug("handleWlRegisterGlobal: {s}", .{interface_name});
            var free_slot_found = false;
            for (&wld.outputs) |*output| {
                if (output.* == null) {
                    const wl_output = registry.bindTyped(wl.Output, name, version);
                    output.* = .{
                        .handle = wl_output,
                    };
                    free_slot_found = true;

                    wl_output.addListener(&wl_output_listener, output);
                    break;
                }
            }

            if (!free_slot_found) {
                log.warn("Monitor capacity reached (8)! Ignoring monitor.", .{});
            }
        }
    }
}

fn handleWlRemoveGlobal(data: ?*anyopaque, registry: *wl.Registry, name: u32) void {
    _ = data;
    _ = registry;

    // TODO: Handle monitor hotplug?
    log.debug("Remove global: {}", .{name});
}

fn handleWlSurfaceEnter(data: ?*anyopaque, surface: *wl.Surface, current_output: *wl.Output) void {
    _ = data;
    _ = surface;

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
        log.warn("Failed to find matching output: {*}", .{current_output});
    }
}

fn handleWlSurfaceLeave(data: ?*anyopaque, surface: *wl.Surface, current_output: *wl.Output) void {
    _ = data;
    _ = surface;

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
        log.warn("Failed to find matching output: {*}", .{current_output});
    }
}

fn handleWlShmFormat(data: ?*anyopaque, shm: *wl.Shm, format: wl.Shm.Format) void {
    _ = shm;

    const wli: *WlInitData = @ptrCast(@alignCast(data));
    if (format == .xrgb8888) wli.xrgb8888 = true;
}

fn handleXdgPing(data: ?*anyopaque, wm_base: *xdg_shell.WmBase, serial: u32) void {
    _ = data;
    wm_base.pong(serial);
}

fn handleXdgSurfaceConfigure(data: ?*anyopaque, surface: *xdg_shell.Surface, serial: u32) void {
    _ = data;
    _ = surface;

    log.debug("xdg surface configure: {}", .{serial});
    wld.pending_configure_serial = serial;
}

fn handleXdgToplevelConfigure(data: ?*anyopaque, toplevel: *xdg_shell.Toplevel, width: i32, height: i32, states_: []const u32) void {
    _ = data;
    _ = toplevel;

    log.debug("xdg toplevel configure: {},{}", .{ width, height });

    const E = xdg_shell.Toplevel.State;
    const states: []const E = @ptrCast(states_);
    log.debug("states: {any}", .{states});

    wld.pending_resize = .{ .width = width, .height = height };
}

fn handleXdgToplevelConfigureBounds(data: ?*anyopaque, toplevel: *xdg_shell.Toplevel, width: i32, height: i32) void {
    _ = data;
    _ = toplevel;

    wld.bound_width = width;
    wld.bound_height = height;
    log.debug("xdg toplevel configure bounds {},{}", .{ width, height });
}

fn handleXdgToplevelWmCapabilities(data: ?*anyopaque, toplevel: *xdg_shell.Toplevel, capabilities: []const u32) void {
    _ = data;
    _ = toplevel;
    log.debug("xdg toplevel capabilities count {}", .{capabilities.len});

    const E = xdg_shell.Toplevel.WmCapabilities;
    const caps: []const E = @ptrCast(capabilities);
    log.debug("toplevel caps: {any}", .{caps});
}

fn handleXdgToplevelClose(data: ?*anyopaque, toplevel: *xdg_shell.Toplevel) void {
    _ = data;
    _ = toplevel;

    running = false;
}

fn handleWlCallbackFrameDone(data: ?*anyopaque, _: *wl.Callback, _: u32) void {
    _ = data;
    wld.should_draw = true;
}

fn handleWlBufferRelease(data: ?*anyopaque, wl_buffer: *wl.Buffer) void {
    _ = wl_buffer;
    const buffer: *WlBuffer = @ptrCast(@alignCast(data));

    if (buffer.width != wld.window_width or buffer.height != wld.window_height) {
        buffer.handle.?.destroy();
        buffer.handle = null;
    }

    buffer.free = true;
}

fn handleWlSeatCapabilities(data: ?*anyopaque, seat: *wl.Seat, capabilities: wl.Seat.Capability) void {
    _ = seat;

    const wli: *WlInitData = @ptrCast(@alignCast(data));
    wli.seat_capabilities = capabilities;
}

fn handleWlKey(data: ?*anyopaque, keyboard: *wl.Keyboard, serial: u32, time: u32, rawkey: u32, state: wl.Keyboard.KeyState) void {
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
            processKeyEvent(&buttons.back, is_down);
        } else if (key == .SPACE) {
            processKeyEvent(&buttons.start, is_down);
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

fn handleWlKeyModifiers(data: ?*anyopaque, keyboard: *wl.Keyboard, serial: u32, mods_depressed: u32, mods_latched: u32, mods_locked: u32, group: u32) void {
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

fn handleWlPointerEnter(data: ?*anyopaque, pointer: *wl.Pointer, serial: u32, surface: *wl.Surface, surface_x: wl.Fixed, surface_y: wl.Fixed) void {
    _ = data;
    _ = pointer;
    _ = surface;

    wld.new_input.debug_mouse.x = surface_x.toInt();
    wld.new_input.debug_mouse.y = surface_y.toInt();

    // Hide cursor, if custom cursors are required use libwayland-cursor or cursor-shape protocol
    if (options.internal_build) {
        //
    } else {
        wld.pointer.setCursor(serial, null, 0, 0);
    }
}

fn handleWlMouseMotion(data: ?*anyopaque, pointer: *wl.Pointer, time: u32, surface_x: wl.Fixed, surface_y: wl.Fixed) void {
    _ = .{ data, pointer, time };

    wld.new_input.debug_mouse.x = surface_x.toInt();
    wld.new_input.debug_mouse.y = surface_y.toInt();
}

fn handleWlMouseButton(data: ?*anyopaque, pointer: *wl.Pointer, serial: u32, time: u32, raw_button: u32, state: wl.Pointer.ButtonState) void {
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

fn handleWlMouseAxis(data: ?*anyopaque, pointer: *wl.Pointer, time: u32, axis: wl.Pointer.Axis, value: wl.Fixed) void {
    _ = .{ data, pointer, time, axis, value };
    // log.debug("mouse axis: {}:{}", .{ axis, value.toDouble() });
}

fn handleXdgDecorationConfigure(data: ?*anyopaque, toplevel_decoration: *xdg_decoration.ToplevelDecorationV1, mode: xdg_decoration.ToplevelDecorationV1.Mode) void {
    _ = toplevel_decoration;
    log.debug("xdg_decoration configure: {}", .{mode});

    const mode_ptr: *?xdg_decoration.ToplevelDecorationV1.Mode = @ptrCast(@alignCast(data));
    mode_ptr.* = mode;
}
fn handleWlOutputGeometry(data: ?*anyopaque, output: *wl.Output, x: i32, y: i32, physical_width: i32, physical_height: i32, subpixel: wl.Output.Subpixel, make: []const u8, model: []const u8, transform: wl.Output.Transform) void {
    _ = .{ data, output };
    log.debug("handleWlOutputGeometry: {},{},{},{},{},{s},{s},{}", .{ x, y, physical_width, physical_height, subpixel, make, model, transform });
}

fn handleWlOutputMode(data: ?*anyopaque, output: *wl.Output, flags: wl.Output.Mode, width: i32, height: i32, refresh: i32) void {
    const output_data: *WlOutput = @ptrCast(@alignCast(data));
    assert(output_data.handle == output);
    output_data.refresh_mhz = refresh;

    log.debug("handleWlOutputMode: {},{},{},{}", .{ flags, width, height, refresh });

    const new_pixel_count = width * height;
    const max_pixel_count = wld.max_width * wld.max_height;
    if (new_pixel_count > max_pixel_count) {
        wld.max_width = width;
        wld.max_height = height;

        // TODO: Create new shm pool, delete old when all buffers are released
        // wld.should_resize_shm = true;
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
    frames_per_second: u32,
    frames_per_video_frame: u32,
    bytes_per_video_frame: u32,

    pulse: PulseContext,

    const Sample = AudioBuffer.Sample;
    const Frame = AudioBuffer.Frame;
};

const PulseContext = struct {
    context: *pa.Context = undefined,
    main_loop: *pa.ThreadedMainLoop = undefined,
    stream: *pa.Stream = undefined,
    context_state: pa.ContextState = .unconnected,
    stream_state: pa.StreamState = .unconnected,
    callbacks_started: bool = false,

    impl: Implementation,

    pub const PulseEmulateDSound = struct {
        safety_frame_bytes: u32,

        running_frame_index: usize,
        read_cursor: usize,
        buffer: []u8,

        audio_valid: bool = false,

        pub fn init(this: *@This(), sample_rate: u32, application_name: [:0]const u8) error{PulseInitFailed}!void {
            const ctx: *PulseContext = @fieldParentPtr("impl", this);
            try ctx.init(sample_rate, application_name);
        }

        pub inline fn start(this: *@This()) void {
            const ctx: *PulseContext = @fieldParentPtr("impl", this);
            ctx.start();
        }

        pub const StreamPosition = struct {
            play: u32,
            write: u32,
        };

        pub inline fn getCurrentPosition(this: *@This(), rate: u32) StreamPosition {
            const ctx: *const PulseContext = @fieldParentPtr("impl", this);

            var pa_latency_usec: pa.USec = undefined;
            pa.threaded_mainloop_lock(ctx.main_loop);
            _ = pa.stream_get_latency(ctx.stream, &pa_latency_usec, null);
            const callback_cursor: u32 = @intCast(this.read_cursor);
            pa.threaded_mainloop_unlock(ctx.main_loop);

            const pa_latency_frames: u32 = @intCast((pa_latency_usec * rate) / std.time.us_per_s);
            const pa_latency_bytes: u32 = pa_latency_frames * @sizeOf(AudioOutput.Frame);
            const buf_len: u32 = @intCast(this.buffer.len);

            const play_cursor: u32 = (callback_cursor + buf_len - (pa_latency_bytes % buf_len)) % buf_len;
            const write_cursor: u32 = callback_cursor;

            return .{ .play = play_cursor, .write = write_cursor };
        }

        fn writeCallback(stream: ?*pa.Stream, nbytes: usize, userdata: ?*anyopaque) callconv(.c) void {
            const context: *PulseContext = @ptrCast(@alignCast(userdata));
            const impl = &context.impl;

            const bytes_to_end = impl.buffer.len - impl.read_cursor;

            if (nbytes <= bytes_to_end) {
                _ = pa.stream_write(stream, &impl.buffer[impl.read_cursor], nbytes, null, 0, .relative);
            } else {
                _ = pa.stream_write(stream, &impl.buffer[impl.read_cursor], bytes_to_end, null, 0, .relative);
                const rem = nbytes - bytes_to_end;
                _ = pa.stream_write(stream, &impl.buffer[0], rem, null, 0, .relative);
            }

            impl.read_cursor = (impl.read_cursor + nbytes) % impl.buffer.len;
        }
    };

    pub const PulsePull = struct {
        thread_context: *const ThreadContext,
        game_code: *const GameCode,
        game_memory: *Memory,

        pub fn init(this: *@This(), sample_rate: u32, application_name: [:0]const u8) error{PulseInitFailed}!void {
            const ctx: *PulseContext = @alignCast(@fieldParentPtr("impl", this));
            try ctx.init(sample_rate, application_name);
        }

        pub inline fn start(this: *@This()) void {
            const ctx: *PulseContext = @alignCast(@fieldParentPtr("impl", this));
            ctx.start();
        }

        pub fn writeCallback(stream: ?*pa.Stream, nbytes: usize, userdata: ?*anyopaque) callconv(.c) void {
            const context: *PulseContext = @ptrCast(@alignCast(userdata));
            const audio_output: *AudioOutput = @fieldParentPtr("pulse", context);
            const impl = &context.impl;

            if (impl.game_code.getAudioFrames) |getAudioFrames| {
                var buf_ptr_opt: ?*anyopaque = null;
                var buf_length: usize = nbytes;
                const rc = pa.stream_begin_write(context.stream, &buf_ptr_opt, &buf_length);

                if (rc == 0 and buf_ptr_opt != null) {
                    const buf_ptr = buf_ptr_opt.?;

                    const sound_buffer = AudioBuffer{
                        .frames_per_second = audio_output.frames_per_second,
                        .frames = @ptrCast(@alignCast(buf_ptr)),
                        .frames_len = buf_length / @sizeOf(AudioOutput.Frame),
                    };
                    getAudioFrames(impl.thread_context, impl.game_memory, &sound_buffer);

                    _ = pa.stream_write(stream, buf_ptr, buf_length, null, 0, .relative);
                }
            }
        }
    };

    pub const Implementation = switch (linux_options.linux_audio_impl) {
        .pulseEmulateDSound => PulseEmulateDSound,
        .pulsePull => PulsePull,
    };

    const InitCallbacks = struct {
        context: *PulseContext,

        fn contextStateCallback(context: ?*pa.Context, userdata: ?*anyopaque) callconv(.c) void {
            const pulse_context: *PulseContext = @ptrCast(@alignCast(userdata));

            pulse_context.context_state = pa.context_get_state(context);
            pa.log.debug("context state: {}", .{pulse_context.context_state});
            pa.threaded_mainloop_signal(pulse_context.main_loop, 0);
        }

        fn streamStateCallback(stream: ?*pa.Stream, userdata: ?*anyopaque) callconv(.c) void {
            const pulse_context: *PulseContext = @ptrCast(@alignCast(userdata));

            pulse_context.stream_state = pa.stream_get_state(stream);
            pa.log.debug("stream state: {}", .{pulse_context.stream_state});
            pa.threaded_mainloop_signal(pulse_context.main_loop, 0);
        }
    };

    pub fn init(this: *@This(), sample_rate: u32, application_name: [:0]const u8) error{PulseInitFailed}!void {
        pa.load();

        const sample_spec = pa.SampleSpec{
            .format = .s16le,
            .rate = sample_rate,
            .channels = 2,
        };

        this.main_loop = pa.threaded_mainloop_new() orelse {
            pa.log.err("pa_threaded_mainloop_new failed", .{});
            return error.PulseInitFailed;
        };
        errdefer pa.threaded_mainloop_free(this.main_loop);
        pa.log.debug("threaded mainloop created", .{});

        const api = pa.threaded_mainloop_get_api(this.main_loop) orelse {
            pa.log.err("pa_threaded_mainloop_get_api failed", .{});
            return error.PulseInitFailed;
        };
        pa.log.debug("threaded mainloop api retrieved", .{});

        this.context = pa.context_new(api, application_name) orelse {
            pa.log.err("pa_context_new failed", .{});
            return error.PulseInitFailed;
        };
        errdefer pa.context_unref(this.context);
        pa.log.debug("context created", .{});

        if (pa.threaded_mainloop_start(this.main_loop) < 0) {
            pa.log.err("pa_threaded_mainloop_start failed", .{});
            return error.PulseInitFailed;
        }
        pa.log.debug("starting threaded mainloop", .{});

        pa.threaded_mainloop_lock(this.main_loop);
        defer pa.threaded_mainloop_unlock(this.main_loop);

        if (pa.context_connect(this.context, null, .{}, null) < 0) {
            pa.log.err("pa_context_connect failed", .{});
            return error.PulseInitFailed;
        }
        errdefer pa.context_disconnect(this.context);
        pa.log.debug("start context connection", .{});

        pa.context_set_state_callback(this.context, InitCallbacks.contextStateCallback, this);
        while (this.context_state != .ready) {
            switch (this.context_state) {
                else => {},
                .ready, .connecting, .authorizing, .setting_name => {},
                .failed, .terminated => {
                    pa.log.err("invalid context state: {}", .{this.context_state});
                    return error.PulseInitFailed;
                },
            }
            pa.threaded_mainloop_wait(this.main_loop);
        }
        pa.log.debug("context ready", .{});

        this.stream = pa.stream_new(this.context, application_name, &sample_spec, null) orelse {
            pa.log.err("failed to create stream", .{});
            return error.PulseInitFailed;
        };
        errdefer pa.stream_unref(this.stream);
        pa.log.debug("stream created", .{});

        const min_req_frames = 8;
        const min_req_bytes = min_req_frames * @sizeOf(AudioOutput.Frame);
        const aggressive_buffer_attr = pa.BufferAttr{
            .max_length = std.math.maxInt(u32),
            .t_length = (min_req_bytes * 2) + 4,
            .pre_buf = 0,
            .min_req = min_req_bytes,
            .frag_size = std.math.maxInt(u32),
        };
        pa.log.debug("initial buffer attributes: {}", .{aggressive_buffer_attr});

        if (pa.stream_connect_playback(this.stream, null, &aggressive_buffer_attr, .{
            .adjust_latency = true,
            .interpolate_timing = true,
            .auto_timing_update = true,
            .start_corked = true,
        }, null, null) < 0) {
            pa.log.err("pa_stream_connect_playback failed", .{});
            return error.PulseInitFailed;
        }
        pa.stream_set_state_callback(this.stream, InitCallbacks.streamStateCallback, this);
        pa.log.debug("stream connected", .{});

        while (this.stream_state != .ready) {
            switch (this.stream_state) {
                else => {},
                .ready, .creating => {},
                .failed, .terminated => {
                    pa.log.err("Invalid stream state: {}", .{this.stream_state});
                    return error.PulseInitFailed;
                },
            }
            pa.threaded_mainloop_wait(this.main_loop);
        }

        const suggested_buffer_attr = pa.stream_get_buffer_attr(this.stream).?;
        pa.log.debug("suggested buffer attributes: {}", .{suggested_buffer_attr});

        const t_length = (suggested_buffer_attr.min_req * 2) + 4;
        const modified_buffer_attr = pa.BufferAttr{
            .max_length = t_length * 2,
            .t_length = t_length,
            .pre_buf = suggested_buffer_attr.min_req,
            .min_req = suggested_buffer_attr.min_req,
            .frag_size = suggested_buffer_attr.frag_size,
        };

        pa.log.debug("modified buffer attributes: {}", .{modified_buffer_attr});

        const op = pa.stream_set_buffer_attr(this.stream, &modified_buffer_attr, &PulseContext.successCallback, this).?;
        defer pa.operation_unref(op);

        while (pa.operation_get_state(op) == .running) {
            pa.threaded_mainloop_wait(this.main_loop);
        }

        if (pa.operation_get_state(op) == .cancelled) {
            pa.log.err("pa_stream_set_buffer_attr cancelled", .{});
            return error.PulseInitFailed;
        }

        const final_buffer_attr = pa.stream_get_buffer_attr(this.stream).?;
        if (!std.mem.eql(u8, std.mem.asBytes(&modified_buffer_attr), std.mem.asBytes(final_buffer_attr))) {
            pa.log.warn("modified buffer attributes not accepted", .{});
        }
        pa.log.debug("final buffer attributes applied: {}", .{final_buffer_attr});

        pa.context_set_state_callback(this.context, null, null); // TODO: Set to runtime version
        pa.stream_set_state_callback(this.stream, null, null); // TODO: Set to runtime version
    }

    /// Blocks until the first write callback is fired
    pub fn start(this: *@This()) void {
        pa.threaded_mainloop_lock(this.main_loop);

        _ = pa.stream_set_write_callback(this.stream, firstWriteCallback, this);
        _ = pa.stream_cork(this.stream, 0, null, null);

        var buf: [4096]AudioOutput.Frame = @splat(.{});

        const writable = pa.stream_writable_size(this.stream);
        assert(buf.len >= writable);
        _ = pa.stream_write(this.stream, @ptrCast(&buf[0]), writable, null, 0, .relative);

        while (!this.callbacks_started) {
            pa.threaded_mainloop_wait(this.main_loop);
        }

        pa.threaded_mainloop_unlock(this.main_loop);
    }

    pub fn firstWriteCallback(stream: ?*pa.Stream, nbytes: usize, userdata: ?*anyopaque) callconv(.c) void {
        const context: *PulseContext = @ptrCast(@alignCast(userdata));

        var buf: [4096]AudioOutput.Frame = @splat(.{});

        assert(!context.callbacks_started);
        assert(nbytes < buf.len);

        const cb = switch (linux_options.linux_audio_impl) {
            .pulseEmulateDSound => PulseEmulateDSound.writeCallback,
            .pulsePull => PulsePull.writeCallback,
        };

        _ = pa.stream_write(stream, &buf[0], nbytes, null, 0, .relative);

        _ = pa.stream_set_write_callback(stream, cb, context);

        context.callbacks_started = true;

        pa.threaded_mainloop_signal(context.main_loop, 0);
    }

    pub fn successCallback(stream: ?*pa.Stream, success: c_int, userdata: ?*anyopaque) callconv(.c) void {
        _ = stream;
        _ = success;

        const context: *@This() = @ptrCast(@alignCast(userdata));

        pa.threaded_mainloop_signal(context.main_loop, 0);
    }
};

/// Return value indicates if a wl_buffer was available, and thus if the offscreenbuffer was actually displayed
fn displayBufferInWindow(buffer: LinuxOffscreenBuffer) bool {
    if (!wld.should_draw) return false;

    if (aquireFreeBuffer()) |wl_buffer| {
        const wl_buffer_ptr: [*]u8 = wld.shm_data.ptr + @as(usize, @intCast(wl_buffer.offset));
        const wl_buffer_mem: []u8 = wl_buffer_ptr[0..@intCast(wl_buffer.pitch * wl_buffer.height)];

        // TODO: Clear gutters in release?
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
                const dest_offset1 = dst_y * @as(usize, @intCast(wl_buffer.pitch));
                const dest_line1: []u32 = @ptrCast(@alignCast(wl_buffer_mem[dest_offset1 .. dest_offset1 + dest_line_length]));
                const dest_offset2 = dest_offset1 + @as(usize, @intCast(wl_buffer.pitch));
                const dest_line2: []u32 = @ptrCast(@alignCast(wl_buffer_mem[dest_offset2 .. dest_offset2 + dest_line_length]));

                for (0..source_line.len) |src_x| {
                    const dst_x = src_x * 2;

                    dest_line1[dst_x] = source_line[src_x];
                    dest_line1[dst_x + 1] = source_line[src_x];
                }

                @memcpy(dest_line2, dest_line1);
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
                const dest_offset = (dst_y * @as(usize, @intCast(wl_buffer.pitch))) + (x_off * bytes_per_pixel);
                const dest_line = wl_buffer_mem[dest_offset .. dest_offset + line_length];

                const source_offset = src_y * @as(usize, @intCast(buffer.pitch));
                const source_line = buffer.memory[source_offset .. source_offset + line_length];

                @memcpy(dest_line, source_line);
            }
        }

        displayWaylandBufferInWindow(wl_buffer);
        return true;
    } else {
        _ = wlc.displayRoundtrip(wld.display);
        log.warn("Failed to aquire wayland buffer!", .{});
        // unreachable; // might want to loop util a buffer is aquired
        // continue;
        return false;
    }
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

    const callback = wld.surface.frame();
    wld.should_draw = false;
    callback.addListener(&wl_frame_callback_listener, &wld);

    wld.surface.commit();
    _ = wlc.displayFlush(wld.display);
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

pub fn handleWlDataOffer(data: ?*anyopaque, data_device: *wl.DataDevice, offer: *wl.DataOffer) void {
    _ = data;
    _ = data_device;

    assert(wld.pending_data_offer == null);
    wld.pending_data_offer = offer;

    offer.addListener(&wl_data_offer_listener, null);
    assert(wld.pending_offer_mime == null);
    assert(wld.pending_offer_mime_weight == 0);
}

pub fn handleWlDataDeviceEnter(data: ?*anyopaque, data_device: *wl.DataDevice, serial: u32, surface: *wl.Surface, x: wl.Fixed, y: wl.Fixed, offer_opt: ?*wl.DataOffer) void {
    _ = data;
    _ = data_device;
    _ = surface;
    _ = x;
    _ = y;

    if (offer_opt) |offer| {
        assert(wld.pending_data_offer != null);
        if (offer.object.id == wld.pending_data_offer.?.object.id) {
            assert(wld.active_dnd_offer == null);

            wld.active_dnd_offer = offer;
            wld.pending_data_offer = null;

            assert(wld.pending_offer_mime != null);
            assert(wld.dnd_mime == null);
            wld.dnd_mime = std.fmt.bufPrintSentinel(&wld.dnd_mime_buffer, "{s}", .{wld.pending_offer_mime.?}, 0) catch unreachable;
            log.debug("dnd mime: {s}", .{wld.dnd_mime.?});
            wld.pending_offer_mime = null;
            wld.pending_offer_mime_weight = 0;

            offer.accept(serial, wld.dnd_mime);
            offer.setActions(wld.active_dnd_source_actions, .{ .copy = true });
        }
    }
}

pub fn handleWlDataDeviceLeave(data: ?*anyopaque, data_device: *wl.DataDevice) void {
    _ = data;
    _ = data_device;

    if (wld.active_dnd_offer) |dnd_offer| {
        dnd_offer.destroy();
        wld.active_dnd_offer = null;
        wld.dnd_mime = null;
    }
}

pub fn handleWlDataDeviceDrop(data: ?*anyopaque, data_device: *wl.DataDevice) void {
    _ = data;
    _ = data_device;

    if (wld.active_dnd_offer) |_| {
        DEBUG.readDnd();
    }
}

pub fn handleWlDataDeviceSelection(data: ?*anyopaque, data_device: *wl.DataDevice, offer_opt: ?*wl.DataOffer) void {
    _ = data;
    _ = data_device;

    if (wld.active_selection_offer) |old| old.destroy();

    if (offer_opt) |offer| {
        assert(wld.pending_data_offer != null);
        assert(wld.pending_offer_mime != null);

        if (offer.object.id == wld.pending_data_offer.?.object.id) {
            wld.active_selection_offer = wld.pending_data_offer;
            wld.pending_data_offer = null;

            log.debug("selection mime: {s}", .{wld.pending_offer_mime.?});

            wld.selection_mime = std.fmt.bufPrintSentinel(&wld.selection_mime_buffer, "{s}", .{wld.pending_offer_mime.?}, 0) catch unreachable;
            wld.pending_offer_mime = null;
            wld.pending_offer_mime_weight = 0;

            DEBUG.readClipboard();
        }
    } else {
        wld.active_selection_offer = null;
    }
}

pub fn handleWlDataOfferOffer(data: ?*anyopaque, data_offer: *wl.DataOffer, mime_type: []const u8) void {
    _ = data;

    assert(wld.pending_data_offer != null);
    assert(data_offer.object.id == wld.pending_data_offer.?.object.id);

    const mimes = [_][]const u8{
        "STRING",
        "TEXT",
        "UTF8_STRING",
        "text/plain",
        "text/plain;charset=utf-8",

        "text/uri-list",

        "image/gif",
        "image/png",
        "image/jpeg",
        "image/jpg",
    };

    var new_weight: u8 = 0;
    var match = false;

    inline for (mimes, 1..) |mime, weight| {
        if (std.mem.eql(u8, mime_type, mime)) {
            new_weight = weight;
            match = true;
            break;
        }
    }

    if ((match and new_weight > wld.pending_offer_mime_weight) or (!match and wld.pending_offer_mime == null)) {
        wld.pending_offer_mime = std.fmt.bufPrintSentinel(&wld.pending_offer_mime_buffer, "{s}", .{mime_type}, 0) catch unreachable;
        wld.pending_offer_mime_weight = new_weight;
    }
}

pub fn handleWlDataOfferSourceActions(data: ?*anyopaque, data_offer: *wl.DataOffer, source_actions: wl.DataDeviceManager.DndAction) void {
    _ = data;

    if (wld.active_dnd_offer) |offer| {
        if (data_offer.object.id == offer.object.id) {
            wld.active_dnd_source_actions = source_actions;
        }
    }
}

pub fn handleWlDataOfferAction(data: ?*anyopaque, data_offer: *wl.DataOffer, dnd_action: wl.DataDeviceManager.DndAction) void {
    _ = data;

    if (wld.active_dnd_offer) |offer| {
        if (data_offer.object.id == offer.object.id) {
            wld.active_dnd_action = dnd_action;
        }
    }
}

fn nop() void {}

const wl_registry_listener = wl.Registry.Listener{
    .global = handleWlRegisterGlobal,
    .globalRemove = handleWlRemoveGlobal,
};

const wl_shm_listener = wl.Shm.Listener{
    .format = handleWlShmFormat,
};

const wl_surface_listener = wl.Surface.Listener{
    .enter = handleWlSurfaceEnter,
    .leave = handleWlSurfaceLeave,
    .preferredBufferScale = @ptrCast(&nop),
    .preferredBufferTransform = @ptrCast(&nop),
};

const xdg_wm_base_listener = xdg_shell.WmBase.Listener{
    .ping = handleXdgPing,
};

const xdg_surface_listener = xdg_shell.Surface.Listener{
    .configure = handleXdgSurfaceConfigure,
};

const xdg_toplevel_listener = xdg_shell.Toplevel.Listener{
    .configure = handleXdgToplevelConfigure,
    .configureBounds = handleXdgToplevelConfigureBounds,
    .wmCapabilities = handleXdgToplevelWmCapabilities,
    .close = handleXdgToplevelClose,
};

const wl_frame_callback_listener = wl.Callback.Listener{
    .done = handleWlCallbackFrameDone,
};

const wl_buffer_listener = wl.Buffer.Listener{
    .release = handleWlBufferRelease,
};

const wl_seat_listener = wl.Seat.Listener{
    .capabilities = handleWlSeatCapabilities,
    .name = @ptrCast(&nop),
};

const wl_data_device_listener = wl.DataDevice.Listener{
    .dataOffer = handleWlDataOffer,
    .enter = handleWlDataDeviceEnter,
    .leave = handleWlDataDeviceLeave,
    .motion = @ptrCast(&nop),
    .drop = handleWlDataDeviceDrop,
    .selection = handleWlDataDeviceSelection,
};

const wl_data_offer_listener = wl.DataOffer.Listener{
    .offer = handleWlDataOfferOffer,
    .sourceActions = handleWlDataOfferSourceActions,
    .action = handleWlDataOfferAction,
};

const wl_keyboard_listener = wl.Keyboard.Listener{
    .key = handleWlKey,
    .enter = @ptrCast(&nop),
    .leave = @ptrCast(&nop),
    .modifiers = handleWlKeyModifiers,
    .repeatInfo = @ptrCast(&nop),
    .keymap = @ptrCast(&nop),
};

const wl_mouse_listener = wl.Pointer.Listener{
    .enter = handleWlPointerEnter,
    .leave = @ptrCast(&nop),
    .motion = handleWlMouseMotion,
    .button = handleWlMouseButton,
    .axis = handleWlMouseAxis,
    .frame = @ptrCast(&nop), // TODO: Use this to handle incoming data correctly in relation to frame boundaries
    .axisDiscrete = @ptrCast(&nop),
    .axisSource = @ptrCast(&nop),
    .axisStop = @ptrCast(&nop),
    .axisValue120 = @ptrCast(&nop),
    .axisRelativeDirection = @ptrCast(&nop),
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
