const std = @import("std");
const log = std.log.scoped(.linux_v10);

const builtin = @import("builtin");

const core = @import("core");
const TimeStamp = core.time.TimeStamp;
const arch = core.arch;
const assert = core.assert;
const fs = core.fs;
const linux = core.os.linux;
const math = core.math;
const mem = core.mem;
const pa = core.lib.pulse;

const lib_loader = @import("lib_loader.zig");

const options = @import("options");
const linux_options = @import("linux_options");

const Window = @import("linux_wayland.zig");

const joysticks = @import("linux_joysticks.zig");
const Joystick = joysticks.Joystick;
const JS = joysticks.System(4);

const common = @import("v10_common");
const AudioBuffer = common.AudioBuffer;
const ButtonState = common.ButtonState;
const ControllerInput = common.ControllerInput;
const GameCode = common.GameCode;
const Input = common.Input;
const Memory = common.Memory;
const OffscreenBuffer = common.OffscreenBuffer;
const ThreadContext = common.ThreadContext;

pub const std_options: std.Options = blk: {
    var o = core.default_std_options;

    o.log_scope_levels =
        o.log_scope_levels ++
        [_]std.log.ScopeLevel{
            .{ .scope = .linux_v10, .level = .debug },
            .{ .scope = .linux_joystick, .level = .info },
            .{ .scope = .pulse, .level = .info },
        };

    break :blk o;
};

// TODO: Check if (wayland) preferred_buffer_scale is relevant

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

var global_running = false;
var global_pause = false;
const global_back_buffer_width: i32 = 960;
const global_back_buffer_height: i32 = 540;

pub const bytes_per_pixel = 4;

pub fn main(init: std.process.Init.Minimal) !u8 {
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
        .io = io,
    };

    common.runAssetCompiler(io, gpa, stderr, stdout) catch |e| {
        log.err("Asset compiler error: '{s}'", .{@errorName(e)});
        return 1;
    };

    var shared_state: common.SharedState = .{};

    const cwd_len = try std.process.currentPath(io, &shared_state.cwd_buf);
    shared_state.cwd = shared_state.cwd_buf[0..cwd_len];
    log.info("cwd: '{s}'", .{shared_state.cwd});

    const exe_dir_path_len = try std.process.executableDirPath(io, &shared_state.exe_dir_path_buf);
    shared_state.exe_dir_path = shared_state.exe_dir_path_buf[0..exe_dir_path_len];
    log.info("exe_dir_path: {s}", .{shared_state.exe_dir_path});

    var game_lib_name_buf: [fs.max_path_bytes]u8 = @splat(0);
    const game_lib_name = try shared_state.buildExePathFilename(&game_lib_name_buf, "libv10_game.so");
    log.info("game_lib_name: {s}", .{game_lib_name});

    var back_buffer: LinuxOffscreenBuffer = .{
        .memory = undefined,
        .width = global_back_buffer_width,
        .height = global_back_buffer_height,
        .pitch = global_back_buffer_width * bytes_per_pixel,
    };

    const back_buffer_memory_size: usize = @intCast(back_buffer.width * back_buffer.height * bytes_per_pixel);
    if (linux.mmap(
        null,
        back_buffer_memory_size,
        .{},
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    )) |mapped| {
        back_buffer.memory = mapped.ptr;
        linux.mprotect(mapped, .{ .READ = true, .WRITE = true }) catch |e| {
            log.err("mprotect call failed during back buffer resize", .{});
            return e;
        };
    } else |_| {
        log.err("mmap call failed during back buffer resize", .{});
        return error.MmapFailed;
    }

    var _new_input: Input = .{};
    var _old_input: Input = .{};
    var input: InputState = .{ .new = &_new_input, .old = &_old_input };

    var window: Window = undefined;
    try Window.init(
        &window,
        &init.environ,
        &shared_state,
        // The backbuffer is currently being drawn with a 10 pixel gutter
        global_back_buffer_width + 20,
        global_back_buffer_height + 20,
        global_back_buffer_width,
        global_back_buffer_height,
        "v10",
        &input,
    );
    defer window.deinit();

    const monitor_hz: f32 = @min(60, window.minOutputHz());

    log.info("monitor hz: {}", .{monitor_hz});

    const game_update_hz: f32 = monitor_hz / 2;
    // const game_update_hz: f32 = 20;
    log.info("game update hz: {}", .{game_update_hz});
    const target_seconds_per_frame: f32 = 1.0 / game_update_hz;

    const base_address: ?[*]align(std.heap.page_size_min) u8, const fixed = if (options.internal_build)
        .{ @ptrFromInt(mem.TiB * 2), true }
    else
        .{ null, false };

    const permanent_storage_size = mem.MiB * 256;
    const transient_storage_size = mem.GiB * 1;
    const total_size = permanent_storage_size + transient_storage_size;

    var game_memory = Memory{
        .initialized = false,
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
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .FIXED_NOREPLACE = fixed },
        -1,
        0,
    )) |all_memory| {
        linux.mprotect(all_memory, .{ .READ = true, .WRITE = true }) catch |e| {
            log.err("mprotect call for game memory storage failed", .{});
            return e;
        };

        game_memory.permanent = all_memory[0..permanent_storage_size];
        game_memory.transient = all_memory[permanent_storage_size..];
        assert(game_memory.transient.len == transient_storage_size);

        shared_state.game_memory_block = all_memory;
    } else |_| {
        log.err("mmap call for game memory failed", .{});
        return error.MMapFailed;
    }

    log.info("perm: {*}", .{game_memory.permanent});
    log.info("trans: {*}", .{game_memory.transient});

    if (options.internal_build) {
        for (&shared_state.replay_buffers, 0..) |*replay_buffer, i| {
            const file_name = shared_state.getInputRecordingPath(&replay_buffer.filname_buf, false, i);

            const permissions = linux.S.IWUSR | linux.S.IRUSR | linux.S.IRGRP | linux.S.IROTH;
            if (linux.open(file_name, .{ .ACCMODE = .RDWR, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, permissions)) |fd| {
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

    var joystick_context_opt_: ?JS = JS.init() catch null;
    const joystick_context_opt: ?*JS = if (joystick_context_opt_) |_| &(joystick_context_opt_.?) else null;
    defer if (joystick_context_opt) |jc| jc.deinit();

    var game_code = GameCode.load(game_lib_name);

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

            .pulse = .{
                .max_latency_usec = audio_buffer_byte_size / @sizeOf(AudioOutput.Frame) * std.time.us_per_s / audio_fps,
                .impl = switch (linux_options.linux_audio_impl) {
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
                },
            },
        };
    };
    const pulse = &audio_output.pulse.impl;

    if (pulse.init(audio_output.frames_per_second, "v10")) {
        pulse.start();
    } else |e| {
        log.err("Pulse init failed, error: '{}'", .{e});
    }
    defer if (audio_output.pulse.lib) |_| audio_output.pulse.lib.?.close();

    var last_counter = getWallClock();
    var flip_wall_clock = getWallClock();

    var last_cycle_count = arch.rdtsc();

    global_running = true;

    log.info("starting main loop", .{});
    while (global_running and !window.closed) {
        input.new.dt = target_seconds_per_frame;

        input.new.executable_reloaded = false;
        const new_lib_write_time = common.getLastWriteTime(game_lib_name);

        if (new_lib_write_time > game_code.last_write_time) {
            game_code.unload();
            game_code = GameCode.load(game_lib_name);
            input.new.executable_reloaded = true;
        }

        const keyboard_controller = &input.new.controllers[0];
        const old_keyboard_controller = &input.old.controllers[0];
        keyboard_controller.* = std.mem.zeroes(ControllerInput);
        for (&keyboard_controller.buttons.array, old_keyboard_controller.buttons.array) |*new_button, old_button| {
            new_button.ended_down = old_button.ended_down;
        }
        keyboard_controller.is_connected = true;

        if (options.internal_build) {
            const mouse = &input.new.debug_mouse;
            const old_mouse = &input.old.debug_mouse;
            mouse.* = std.mem.zeroes(common.DebugMouseInput);
            mouse.x = old_mouse.x;
            mouse.y = old_mouse.y;
            mouse.z = old_mouse.z;
            for (&mouse.buttons.array, old_mouse.buttons.array) |*new_button, old_button| {
                new_button.ended_down = old_button.ended_down;
            }

            const mods = &input.new.debug_mod_keys;
            const old_mods = &input.old.debug_mod_keys;
            mods.* = std.mem.zeroes(common.DebugModKeys);
            inline for (std.meta.fields(common.DebugModKeys)) |field| {
                @field(mods, field.name).ended_down = @field(old_mods, field.name).ended_down;
            }
        }

        if (!window.poll()) {
            global_running = false;
        }
        window.handlePendingResize();

        if (joystick_context_opt) |jc| jc.update();

        if (!global_pause) {
            if (joystick_context_opt) |joystick_context| {
                var max_controller_count: usize = joystick_context.joysticks.len;
                if (max_controller_count > (input.new.controllers.len - 1)) max_controller_count = (input.new.controllers.len - 1);

                for (joystick_context.joysticks[0..max_controller_count], 1..) |*js, i| {
                    const old_controller = &input.old.controllers[i];
                    var new_controller = &input.new.controllers[i];

                    const old_buttons = &old_controller.buttons.named;
                    const new_buttons = &new_controller.buttons.named;

                    if (js.state == .active) {
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

                        const strong = js.axis[@intFromEnum(Joystick.Axis.right_z)];
                        const weak = js.axis[@intFromEnum(Joystick.Axis.left_z)];
                        js.setRumble(strong, weak) catch |e| log.warn("Failed to set joystick rumble, error: '{}'", .{e});
                    } else if (js.state == .inactive) {
                        new_controller.is_connected = false;
                    }
                }
            }

            assert(OffscreenBuffer.bytes_per_pixel == bytes_per_pixel);
            var game_offscreen_buffer = OffscreenBuffer{
                .memory = back_buffer.memory,
                .width = back_buffer.width,
                .height = back_buffer.height,
                .pitch = back_buffer.pitch,
            };

            if (shared_state.input_recording_index > 0) {
                recordInput(&shared_state, input.new);
            }

            if (shared_state.input_playing_index > 0) {
                playbackInput(&shared_state, input.new);
            }

            if (game_code.updateAndRender) |updateAndRender|
                updateAndRender(&thread_context, &game_memory, input.new, &game_offscreen_buffer);

            if (audio_output.pulse.lib != null and linux_options.linux_audio_impl == .pulseEmulateDSound) {
                const audio_wall_clock = getWallClock();
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
                                .frames = frames,
                                .frames_per_second = @intCast(audio_output.frames_per_second),
                            };

                            getAudioFrames(&thread_context, &game_memory, &game_sound_output_buffer);
                        } else {
                            var frames: []AudioOutput.Frame = @ptrCast(@alignCast(pulse.buffer[byte_to_lock..]));

                            var game_sound_output_buffer: AudioBuffer = .{
                                .frames = frames,
                                .frames_per_second = @intCast(audio_output.frames_per_second),
                            };

                            getAudioFrames(&thread_context, &game_memory, &game_sound_output_buffer);

                            frames = @ptrCast(@alignCast(pulse.buffer[0 .. bytes_to_write - bytes_to_end]));
                            game_sound_output_buffer.frames = frames;

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
            } else if (audio_output.pulse.lib != null) {
                assert(linux_options.linux_audio_impl == .pulsePull);

                if (options.internal_build) {
                    var pa_latency_usec: pa.USec = undefined;

                    pa.threaded_mainloop_lock(audio_output.pulse.main_loop);
                    _ = pa.stream_get_latency(audio_output.pulse.stream, &pa_latency_usec, null);
                    pa.threaded_mainloop_unlock(audio_output.pulse.main_loop);

                    const latency_usec: u64 = @min(pa_latency_usec, audio_output.pulse.max_latency_usec);
                    const latency_frames: u32 = @intCast(math.divCeil(latency_usec * audio_output.frames_per_second, std.time.us_per_s));
                    const latency_bytes = latency_frames * @sizeOf(AudioOutput.Frame);

                    // log.debug("audio latency: {} - {:.3}s", .{ latency_bytes, @as(f32, @floatFromInt(pa_latency_usec)) / std.time.us_per_s });
                    _ = .{latency_bytes};
                }
            }

            const work_counter = getWallClock();
            const work_seconds_elapsed = getSecondsElapsed(last_counter, work_counter);

            var seconds_elapsed_for_frame = work_seconds_elapsed;
            if (seconds_elapsed_for_frame <= target_seconds_per_frame) {
                sleep_loop: while (seconds_elapsed_for_frame < target_seconds_per_frame) {
                    const sleep_ms: u64 = @intFromFloat(std.time.ms_per_s * (target_seconds_per_frame - seconds_elapsed_for_frame));

                    if (sleep_ms > 1) {
                        const s = (sleep_ms * std.time.ns_per_ms) - (std.time.ns_per_ms / 2);

                        if (!window.pollTimeout(s)) {
                            global_running = false;
                            break :sleep_loop;
                        }
                    } else {
                        std.atomic.spinLoopHint();
                    }

                    seconds_elapsed_for_frame = getSecondsElapsed(last_counter, getWallClock());
                }
            } else {
                log.warn("Missed frame time! ({})", .{seconds_elapsed_for_frame * std.time.ms_per_s});
                if (!window.poll()) {
                    global_running = false;
                }
            }

            const end_counter = getWallClock();
            const ms_per_frame = std.time.ms_per_s * getSecondsElapsed(last_counter, end_counter);
            last_counter = end_counter;

            const wayland_blit = window.blitBuffer(&back_buffer);

            flip_wall_clock = getWallClock();

            const tmp = input.new;
            input.new = input.old;
            input.old = tmp;

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
            _ = .{ ms_per_frame, fps, mcpf, wayland_blit, work_seconds_elapsed };
        }
    }

    return 0;
}

pub const LinuxOffscreenBuffer = struct {
    memory: [*]u8,
    width: i32,
    height: i32,
    pitch: i32,
};

pub const InputState = struct {
    new: *Input,
    old: *Input,
};

pub fn handleMouseEnter(window: *Window, input: *Input, x: i32, y: i32) void {
    input.debug_mouse.x = x;
    input.debug_mouse.y = y;

    // Hide cursor, if custom cursors are required use libwayland-cursor or cursor-shape protocol
    if (options.internal_build) {
        //
    } else {
        window.hideCursor();
    }
}

pub fn handleMouseMotion(window: *Window, input: *Input, x: i32, y: i32) void {
    _ = window;
    input.debug_mouse.x = x;
    input.debug_mouse.y = y;
}

pub fn handleMouseButton(window: *Window, button: linux.KEY, was_down: bool, is_down: bool) void {
    const mouse = &window.input.new.debug_mouse;
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

pub fn handleKey(window: *Window, input: *Input, key: linux.KEY, was_down: bool, is_down: bool) void {
    const keyboard_controller = &input.controllers[0];
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

        if (options.internal_build) {
            if (key == .LEFTSHIFT) {
                processKeyEvent(&input.debug_mod_keys.left_shift, is_down);
            } else if (key == .RIGHTSHIFT) {
                processKeyEvent(&input.debug_mod_keys.right_shift, is_down);
            } else if (key == .LEFTCTRL) {
                processKeyEvent(&input.debug_mod_keys.left_ctrl, is_down);
            } else if (key == .RIGHTCTRL) {
                processKeyEvent(&input.debug_mod_keys.right_ctrl, is_down);
            } else if (key == .LEFTALT) {
                processKeyEvent(&input.debug_mod_keys.left_alt, is_down);
            } else if (key == .RIGHTALT) {
                processKeyEvent(&input.debug_mod_keys.right_alt, is_down);
            } else if (key == .NUMLOCK) {
                processKeyEvent(&input.debug_mod_keys.numlock, is_down);
            }

            const shift_down = input.debug_mod_keys.left_shift.ended_down or input.debug_mod_keys.right_shift.ended_down;
            if (shift_down != input.debug_mod_keys.shift.ended_down) {
                processKeyEvent(&input.debug_mod_keys.shift, shift_down);
            }

            const ctrl_down = input.debug_mod_keys.left_ctrl.ended_down or input.debug_mod_keys.right_ctrl.ended_down;
            if (ctrl_down != input.debug_mod_keys.ctrl.ended_down) {
                processKeyEvent(&input.debug_mod_keys.ctrl, ctrl_down);
            }

            const alt_down = input.debug_mod_keys.left_alt.ended_down or input.debug_mod_keys.right_alt.ended_down;
            if (alt_down != input.debug_mod_keys.alt.ended_down) {
                processKeyEvent(&input.debug_mod_keys.alt, alt_down);
            }

            if (is_down) {
                if (key == .P) {
                    global_pause = !global_pause;
                } else if (key == .L) {
                    if (window.shared_state.input_recording_index == 0 and
                        window.shared_state.input_playing_index == 0)
                    {
                        beginRecordingInput(window.shared_state, 1);
                    } else if (window.shared_state.input_recording_index == 1) {
                        endRecordingInput(window.shared_state);
                        beginInputPlayback(window.shared_state, 1);
                    } else {
                        endInputPlayback(window.shared_state);
                        // TODO: Reset input, keys may be stuck in down state
                    }
                } else if ((key == .ENTER and input.debug_mod_keys.alt.ended_down) or
                    key == .F11)
                {
                    toggleFullscreen(window);
                }
            }
        }
    }
}

inline fn processDigitalButton(buttons: Joystick.Buttons, old_state: *const ButtonState, btn: Joystick.Button, new_state: *ButtonState) void {
    new_state.ended_down = buttons.isSet(@intFromEnum(btn));
    new_state.half_transition_count = if (old_state.ended_down == new_state.ended_down) 0 else 1;
}

inline fn processKeyEvent(new_state: *ButtonState, is_down: bool) void {
    new_state.ended_down = is_down;
    new_state.half_transition_count += 1;
}

pub inline fn getWallClock() TimeStamp {
    return TimeStamp.now(.monotonic);
}

inline fn getSecondsElapsed(start: TimeStamp, end: TimeStamp) f32 {
    const d_ns_f: f32 = @floatFromInt(start.durationTo(end).ns());
    const d_s_f: f32 = d_ns_f / std.time.ns_per_s;
    return d_s_f;
}

pub const DEBUG = struct {
    pub fn readEntireFile(thread_context: *ThreadContext, path: [:0]const u8) common.DEBUG.ReadFileResult {
        var result: []u8 = &.{};

        if (linux.open(path, .{ .CLOEXEC = true }, 0)) |fd| {
            var stat: linux.Stat = undefined;

            // TODO: Use statx here! statx needs absolute paths or a dir fd...
            if (linux.stat(path, &stat)) {
                const file_size: usize = @intCast(stat.st_size);

                if (linux.mmap(null, file_size, .{}, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0)) |mapped| {
                    if (linux.mprotect(mapped, .{ .READ = true, .WRITE = true })) {
                        if (linux.read(fd, mapped)) |read| {
                            assert(read.len == file_size);
                            result = read;
                        } else |e| {
                            freeFileMemory(thread_context, mapped);
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

            linux.close(fd);
        } else |e| {
            log.warn("Failed to open file: '{s}', error: {}", .{ path, e });
        }

        return result;
    }

    pub fn writeEntireFile(thread_context: *ThreadContext, path: [:0]const u8, data: []const u8) bool {
        _ = thread_context;
        var result = false;

        const permissions = linux.S.IWUSR | linux.S.IRUSR | linux.S.IRGRP | linux.S.IROTH;

        if (linux.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, permissions)) |fd| {
            if (linux.write(fd, data)) |written| {
                result = written == data.len;
            } else |e| {
                log.err("Failed to write to file: '{s}', error: {}", .{ path, e });
            }

            linux.close(fd);
        } else |e| {
            log.err("Failed to open file: '{s}', error: {}", .{ path, e });
        }
        return result;
    }

    pub fn freeFileMemory(thread_context: *ThreadContext, memory: []const u8) void {
        _ = thread_context;

        if (memory.len > 0) {
            const memory_aligned: []align(linux.page_size) const u8 = @alignCast(memory);
            linux.munmap(memory_aligned) catch |e| {
                log.err("Failed to free file memory, error: {}", .{e});
            };
        }
    }
};

fn toggleFullscreen(window: *Window) void {
    if (window.fullscreen) {
        window.xdg_toplevel.unsetFullscreen();
        window.fullscreen = false;
    } else {
        // TODO: Preferred fullscreen monitor
        window.xdg_toplevel.setFullscreen(null);
        window.fullscreen = true;
    }
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

    max_latency_usec: u64,

    impl: Implementation,
    lib: ?core.DynLib = null,

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

            const latency_usec: u64 = @min(pa_latency_usec, ctx.max_latency_usec);
            const latency_frames: u32 = @intCast(math.divCeil(latency_usec * rate, std.time.us_per_s));

            const latency_bytes: u32 = latency_frames * @sizeOf(AudioOutput.Frame);
            const buf_len: u32 = @intCast(this.buffer.len);

            const play_cursor: u32 = (callback_cursor + buf_len - (latency_bytes % buf_len)) % buf_len;
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

                    const frame_count = buf_length / @sizeOf(AudioOutput.Frame);
                    const frames = @as([*]AudioOutput.Frame, @ptrCast(@alignCast(buf_ptr)))[0..frame_count];

                    const sound_buffer = AudioBuffer{
                        .frames = frames,
                        .frames_per_second = audio_output.frames_per_second,
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
        this.lib = lib_loader.load(core.lib.pulse, &.{"libpulse.so.0"}, .{
            .name_for_debugging = "libpulse",
            .search_prefix_opt = "pa_",
            .stub_suffix_opt = "_stub",
        });

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
            .max_length = math.maxInt(u32),
            .t_length = (min_req_bytes * 2) + 4,
            .pre_buf = 0,
            .min_req = min_req_bytes,
            .frag_size = math.maxInt(u32),
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

        pa.log.info("stream started", .{});
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

        pa.log.info("stream callbacks started", .{});
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

pub fn beginRecordingInput(shared_state: *common.SharedState, input_recording_index: usize) void {
    const replay_buffer = shared_state.getReplayBuffer(input_recording_index);

    if (replay_buffer.memory.len == shared_state.game_memory_block.len) {
        shared_state.input_recording_index = input_recording_index;

        var file_name_buf: [fs.max_path_bytes]u8 = undefined;
        const file_name = shared_state.getInputRecordingPath(&file_name_buf, true, input_recording_index);

        shared_state.recording_handle = linux.open(file_name, .{ .ACCMODE = .RDWR, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, 0) catch @panic("Input recording file creation failed");

        @memcpy(replay_buffer.memory, shared_state.game_memory_block);
    } else log.warn("Invalid recording buffer: {}", .{input_recording_index});
}

pub fn endRecordingInput(shared_state: *common.SharedState) void {
    if (shared_state.input_recording_index != 0) {
        linux.close(shared_state.recording_handle);
        shared_state.input_recording_index = 0;
    }
}

pub fn beginInputPlayback(shared_state: *common.SharedState, input_playing_index: usize) void {
    const replay_buffer = shared_state.getReplayBuffer(input_playing_index);

    if (replay_buffer.memory.len == shared_state.game_memory_block.len) {
        shared_state.input_playing_index = input_playing_index;

        var file_name_buf: [fs.max_path_bytes]u8 = undefined;
        const file_name = shared_state.getInputRecordingPath(&file_name_buf, true, input_playing_index);

        shared_state.playback_handle = linux.open(file_name, .{ .CLOEXEC = true }, 0) catch @panic("Input playback file open failed");

        @memcpy(shared_state.game_memory_block, replay_buffer.memory);
    } else log.warn("Invalid replay buffer: {}", .{input_playing_index});
}

pub fn endInputPlayback(shared_state: *common.SharedState) void {
    if (shared_state.input_playing_index != 0) {
        linux.close(shared_state.playback_handle);
        shared_state.input_playing_index = 0;
    }
}

pub fn recordInput(shared_state: *common.SharedState, new_input: *Input) void {
    const written = linux.write(shared_state.recording_handle, @ptrCast(new_input)) catch @panic("Input recording write failed");
    assert(written == @sizeOf(Input));
}

pub fn playbackInput(shared_state: *common.SharedState, new_input: *Input) void {
    if (linux.read(shared_state.playback_handle, @ptrCast(new_input))) |bytes_read| {
        if (bytes_read.len == 0) {
            const index = shared_state.input_playing_index;

            endInputPlayback(shared_state);
            beginInputPlayback(shared_state, index);

            const bytes_read_2 = linux.read(shared_state.playback_handle, @ptrCast(new_input)) catch @panic("Input playback read failed");
            assert(bytes_read_2.len == @sizeOf(Input));
        } else {
            assert(bytes_read.len == @sizeOf(Input));
        }
    } else |_| @panic("Input playback read failed");
}
