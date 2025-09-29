const std = @import("std");
const log = std.log.scoped(.win32_v10);
const options = @import("options");
const mem = @import("mem");
const win32 = @import("win32/win32.zig");
const xinput = @import("win32/xinput.zig");
const dsound = @import("win32/direct_sound.zig");
const x86_64 = @import("x86_64.zig");
const v10 = @import("v10.zig");

const assert = std.debug.assert;

var global_running = false;
var global_back_buffer: OffscreenBuffer = undefined;
var global_perf_count_frequency: u64 = undefined;

inline fn getWallClock() win32.LARGE_INTEGER {
    var result: win32.LARGE_INTEGER = .{ .quad_part = 0 };
    _ = win32.QueryPerformanceCounter(&result);
    return result;
}

inline fn getSecondsElapsed(start: win32.LARGE_INTEGER, end: win32.LARGE_INTEGER) f32 {
    const diff: f32 = @floatFromInt(end.quad_part - start.quad_part);
    return diff / @as(f32, @floatFromInt(global_perf_count_frequency));
}

pub const OffscreenBuffer = struct {
    info: win32.BITMAPINFO,
    memory: []u8,
    width: i32,
    height: i32,
    pitch: i32,
    bytes_per_pixel: i32,
};

pub const WindowDimensions = struct {
    width: i32,
    height: i32,
};

pub const AudioOutput = struct {
    dsound_buffer: ?*dsound.IDirectSoundBuffer,
    buffer: []Frame = &.{},

    frames_per_second: u32,
    buffer_byte_size: u32,
    running_frame_index: u32,
    latency_frame_count: u32,

    const Sample = v10.AudioBuffer.Sample;
    const Frame = v10.AudioBuffer.Frame;
};

fn clearAudioBuffer(audio_output: *AudioOutput) void {
    var region1_ptr: *anyopaque = undefined;
    var region1_bytes: u32 = undefined;
    var region2_ptr: *anyopaque = undefined;
    var region2_bytes: u32 = undefined;

    if (audio_output.dsound_buffer) |buf| if (buf.Lock(0, audio_output.buffer_byte_size, &region1_ptr, &region1_bytes, &region2_ptr, &region2_bytes, 0) == dsound.OK) {
        const region_1_frame_count = region1_bytes / @sizeOf(AudioOutput.Frame);
        var dest_sample: [*]i16 = @ptrCast(@alignCast(region1_ptr));
        for (0..region_1_frame_count) |_| {
            dest_sample[0] = 0;
            dest_sample += 1;

            dest_sample[0] = 0;
            dest_sample += 1;
        }

        const region_2_frame_count = region2_bytes / @sizeOf(AudioOutput.Frame);
        dest_sample = @ptrCast(@alignCast(region2_ptr));
        for (0..region_2_frame_count) |_| {
            dest_sample[0] = 0;
            dest_sample += 1;

            dest_sample[0] = 0;
            dest_sample += 1;
        }

        _ = buf.Unlock(region1_ptr, region1_bytes, region2_ptr, region2_bytes);
    };
}

fn fillAudioBuffer(audio_output: *AudioOutput, byte_to_lock: u32, bytes_to_write: u32, source_buffer: *v10.AudioBuffer) void {
    var region1_ptr: *anyopaque = undefined;
    var region1_bytes: u32 = undefined;
    var region2_ptr: *anyopaque = undefined;
    var region2_bytes: u32 = undefined;

    if (audio_output.dsound_buffer) |buf| if (buf.Lock(byte_to_lock, bytes_to_write, &region1_ptr, &region1_bytes, &region2_ptr, &region2_bytes, 0) == dsound.OK) {
        const region_1_frame_count = region1_bytes / @sizeOf(AudioOutput.Frame);
        var dest_sample: [*]i16 = @ptrCast(@alignCast(region1_ptr));
        var source_frame = source_buffer.frames;
        for (0..region_1_frame_count) |_| {
            dest_sample[0] = source_frame[0].left;
            dest_sample += 1;

            dest_sample[0] = source_frame[0].right;
            dest_sample += 1;

            source_frame += 1;

            audio_output.running_frame_index +%= 1;
        }

        const region_2_frame_count = region2_bytes / @sizeOf(AudioOutput.Frame);
        dest_sample = @ptrCast(@alignCast(region2_ptr));
        for (0..region_2_frame_count) |_| {
            dest_sample[0] = source_frame[0].left;
            dest_sample += 1;

            dest_sample[0] = source_frame[0].right;
            dest_sample += 1;

            source_frame += 1;

            audio_output.running_frame_index +%= 1;
        }

        _ = buf.Unlock(region1_ptr, region1_bytes, region2_ptr, region2_bytes);
    };
}

fn initDSound(window: win32.HWND, samples_per_second: u32, buffer_size: u32) ?*dsound.IDirectSoundBuffer {
    dsound.load();

    var ds: *dsound.IDirectSound = undefined;
    var sound_buffer_opt: ?*dsound.IDirectSoundBuffer = null;

    if (dsound.DirectSoundCreate(null, &ds, null) == dsound.OK) {
        const num_channels = 2;
        const bits_per_sample = 16;
        const block_align = (num_channels * bits_per_sample) / 8;

        const waveformat = dsound.WaveFormatEx{
            .format = dsound.WAVE_FORMAT_PCM,
            .channels = num_channels,
            .samples_per_second = samples_per_second,
            .avg_bytes_per_second = samples_per_second * block_align,
            .block_align = block_align,
            .bits_per_sample = bits_per_sample,
            .size = 0,
        };

        if (ds.SetCooperativeLevel(window, dsound.SCL_PRIORITY) == dsound.OK) {
            // Create primary buffer
            const buffer_desc = dsound.BufferDesc{
                .flags = dsound.BCAPS_PRIMARYBUFFER,
            };
            var primary_buffer_opt: ?*dsound.IDirectSoundBuffer = null;
            if (ds.CreateSoundBuffer(&buffer_desc, &primary_buffer_opt, null) == dsound.OK) {
                if (primary_buffer_opt.?.SetFormat(&waveformat) == dsound.OK) {
                    log.debug("DSound primary buffer format set", .{});
                } else {
                    log.warn("DSound primary_buffer.SetFormat failed", .{});
                }
            } else {
                log.warn("DSound CreateSoundBuffer failed (primary buffer)", .{});
            }
        } else {
            log.warn("DSound SetCooperativeLevel failed", .{});
        }

        // Create secondary buffer
        const buffer_desc = dsound.BufferDesc{
            .wave_format = &waveformat,
            .buffer_bytes = buffer_size,
        };

        if (ds.CreateSoundBuffer(&buffer_desc, &sound_buffer_opt, null) == dsound.OK and sound_buffer_opt != null) {
            log.debug("DSound secondary buffer created", .{});
        } else {
            log.warn("DSound CreateSoundBuffer failed (secondary buffer)", .{});
        }
    } else {
        log.warn("DirectSoundCreate failed", .{});
    }

    return sound_buffer_opt;
}

const GamepadButton = std.meta.FieldEnum(xinput.GamepadButtonBits);

fn processPendingMessages(keyboard_controller: *v10.ControllerInput) void {
    var msg = win32.MSG{};

    const buttons = &keyboard_controller.buttons.named;

    while (win32.PeekMessageA(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
        switch (msg.message) {
            win32.WM_QUIT => {
                global_running = false;
            },

            win32.WM_SYSKEYDOWN,
            win32.WM_SYSKEYUP,
            win32.WM_KEYDOWN,
            win32.WM_KEYUP,
            => {
                const vk_code = msg.wParam;
                const was_down = (msg.lParam & (1 << 30)) != 0;
                const is_down = (msg.lParam & (1 << 31)) == 0;

                if (is_down != was_down) {
                    if (vk_code == win32.VK_Q) {
                        processKeyboardMessage(&buttons.left_shoulder, is_down);
                    } else if (vk_code == win32.VK_E) {
                        processKeyboardMessage(&buttons.right_shoulder, is_down);
                    } else if (vk_code == win32.VK_W) {
                        processKeyboardMessage(&buttons.move_up, is_down);
                    } else if (vk_code == win32.VK_S) {
                        processKeyboardMessage(&buttons.move_down, is_down);
                    } else if (vk_code == win32.VK_A) {
                        processKeyboardMessage(&buttons.move_left, is_down);
                    } else if (vk_code == win32.VK_D) {
                        processKeyboardMessage(&buttons.move_right, is_down);
                    } else if (vk_code == win32.VK_UP) {
                        processKeyboardMessage(&buttons.action_up, is_down);
                    } else if (vk_code == win32.VK_DOWN) {
                        processKeyboardMessage(&buttons.action_down, is_down);
                    } else if (vk_code == win32.VK_LEFT) {
                        processKeyboardMessage(&buttons.action_left, is_down);
                    } else if (vk_code == win32.VK_RIGHT) {
                        processKeyboardMessage(&buttons.action_right, is_down);
                    } else if (vk_code == win32.VK_ESCAPE) {
                        processKeyboardMessage(&buttons.start, is_down);
                    } else if (vk_code == win32.VK_SPACE) {
                        processKeyboardMessage(&buttons.back, is_down);
                    }

                    const alt_key_was_down = (msg.lParam & (1 << 29)) != 0;
                    if ((vk_code == win32.VK_F4) and alt_key_was_down) {
                        global_running = false;
                    }
                }
            },

            else => {
                _ = win32.TranslateMessage(&msg);
                _ = win32.DispatchMessageA(&msg);
            },
        }
    }
}

fn processKeyboardMessage(new_state: *v10.ButtonState, ended_down: bool) void {
    assert(new_state.ended_down != ended_down);

    new_state.ended_down = ended_down;
    new_state.half_transition_count += 1;
}

fn processXInputDigitalButton(xinput_button_state: xinput.GamepadButtonBits, old_state: *const v10.ButtonState, comptime button: GamepadButton, new_state: *v10.ButtonState) void {
    new_state.ended_down = @field(xinput_button_state, @tagName(button));
    new_state.half_transition_count = if (old_state.ended_down == new_state.ended_down) 1 else 0;
}

fn processXInputStickValue(value: win32.SHORT, deadzone: win32.SHORT) f32 {
    var result: f32 = 0;

    const fvalue: f32 = @floatFromInt(value);
    if (value < -deadzone) {
        result = fvalue / -@as(f32, @floatFromInt(std.math.minInt(win32.SHORT)));
    } else if (value > deadzone) {
        result = fvalue / @as(f32, @floatFromInt(std.math.maxInt(win32.SHORT)));
    }

    return result;
}

fn getWindowDimension(window: win32.HWND) WindowDimensions {
    var client_rect: win32.RECT = undefined;
    _ = win32.GetClientRect(window, &client_rect);
    return .{
        .width = client_rect.right - client_rect.left,
        .height = client_rect.bottom - client_rect.top,
    };
}

pub fn main() u8 {
    if (win32.AttachConsole(win32.ATTACH_PARENT_PROCESS) == 0) {
        // NOTE: this code is from zoverlay, i don't remember why we need createfile/sethandle, attachconsole by itself seems to be sufficient.

        // if (win32.CreateFileA("nul", win32.GENERIC_READ | win32.GENERIC_WRITE, 0, null, win32.OPEN_EXISTING, win32.FILE_ATTRIBUTE_NORMAL, null)) |handle| {
        //     _ = handle;
        // _ = win.SetStdHandle(win.STD_INPUT_HANDLE, handle);
        // _ = win.SetStdHandle(win.STD_OUTPUT_HANDLE, handle);
        // _ = win.SetStdHandle(win.STD_ERROR_HANDLE, handle);
        //     unreachable;
        // } else {
        //     unreachable;
        // }
    }

    const instance: win32.HINSTANCE = @ptrCast(win32.GetModuleHandleA(null));
    const command_line = win32.GetCommandLineA();

    var startup_info: win32.STARTUPINFOA = undefined;
    win32.GetStartupInfoA(&startup_info);

    const ret_code = windowsEntry(instance, null, command_line, startup_info.wShowWindow);
    assert(ret_code >= 0);
    return @intCast(ret_code);
}

pub fn windowsEntry(
    instance: win32.HINSTANCE,
    prev_instance: ?win32.HINSTANCE,
    command_line: win32.LPCSTR,
    cmd_show: c_int,
) c_int {
    _ = prev_instance;
    _ = command_line;
    _ = cmd_show;

    var qpf_result: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceFrequency(&qpf_result);
    global_perf_count_frequency = qpf_result.quad_part;

    const desired_scheduler_ms = 1;
    const sleep_is_granular = win32.timeBeginPeriod(desired_scheduler_ms) == win32.TIMERR_NOERROR;

    const window_class = win32.WNDCLASSA{
        .style = win32.CS_OWNDC | win32.CS_HREDRAW | win32.CS_VREDRAW,
        .lpfnWndProc = windowProcA,
        .hInstance = instance,
        .lpszClassName = "v10_window_class",
    };

    if (win32.RegisterClassA(&window_class) != 0) {
        const window_opt = win32.CreateWindowExA(
            0,
            window_class.lpszClassName,
            "v10",
            win32.WS_OVERLAPPEDWINDOW | win32.WS_VISIBLE,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            null,
            null,
            instance,
            null,
        );

        const monitor_refresh_hz = 60;
        const game_update_hz = monitor_refresh_hz / 2;
        const target_seconds_per_frame: f32 = 1.0 / @as(f32, @floatFromInt(game_update_hz));
        const frames_of_audio_latency = 3;

        if (window_opt) |window| {
            global_running = true;
            const device_context = win32.GetDC(window);
            const dib_allocated = resizeDibSection(&global_back_buffer, 1280, 720);

            const audio_fps = 48000;
            const audio_buffer_byte_size = audio_fps * @sizeOf(v10.AudioBuffer.Frame);

            var audio_output: AudioOutput = .{
                .dsound_buffer = initDSound(window, audio_fps, audio_buffer_byte_size),
                .frames_per_second = audio_fps,
                .buffer_byte_size = audio_buffer_byte_size,
                .running_frame_index = 0,
                .latency_frame_count = frames_of_audio_latency * audio_fps / game_update_hz,
            };

            clearAudioBuffer(&audio_output);

            if (audio_output.dsound_buffer) |b| _ = b.Play(0, 0, dsound.BPLAY_LOOPING);

            const audio_frames = win32.VirtualAlloc(
                null,
                audio_output.buffer_byte_size,
                win32.MEM_RESERVE | win32.MEM_COMMIT,
                win32.PAGE_READWRITE,
            );
            audio_output.buffer = @as([*]AudioOutput.Frame, @ptrCast(@alignCast(audio_frames)))[0 .. audio_output.buffer_byte_size / @sizeOf(AudioOutput.Frame)];

            const base_address: ?[*]u8 = comptime if (options.internal_build)
                @ptrFromInt(mem.TiB * 2)
            else
                null;

            const permanent_storage_size = mem.MiB * 64;
            const transient_storage_size = mem.GiB * 4;
            const total_size = permanent_storage_size + transient_storage_size;

            const perm: ?[*]u8 = @ptrCast(win32.VirtualAlloc(
                base_address,
                total_size,
                win32.MEM_RESERVE | win32.MEM_COMMIT,
                win32.PAGE_READWRITE,
            ));
            const trans: ?[*]u8 = @as([*]u8, @ptrCast(perm)) + permanent_storage_size;

            log.debug("perm:  {*}", .{perm});
            log.debug("trans: {*}", .{trans});

            var game_memory = v10.Memory{
                .initialized = false,
                .permanent = @as([*]u8, @ptrCast(perm))[0..permanent_storage_size],
                .transient = @as([*]u8, @ptrCast(trans))[0..transient_storage_size],
            };

            if (dib_allocated and audio_frames != null and perm != null and trans != null) {
                xinput.load();

                var input = [_]v10.Input{.{}} ** 2;
                var new_input = &input[0];
                var old_input = &input[1];

                var last_counter = getWallClock();
                var last_cycle_count = x86_64.rdtsc();

                var debug_time_marker_index: usize = 0;
                var debug_time_markers = [_]DEBUG.AudioTimeMarker{.{}} ** (game_update_hz / 2);

                var last_play_cursor: win32.DWORD = 0;
                var audio_valid = false;

                while (global_running) {
                    const keyboard_controller = &new_input.controllers[0];
                    const old_keyboard_controller = &old_input.controllers[0];
                    keyboard_controller.* = std.mem.zeroes(v10.ControllerInput);
                    for (&keyboard_controller.buttons.array, old_keyboard_controller.buttons.array) |*new_button, old_button| {
                        new_button.ended_down = old_button.ended_down;
                    }
                    keyboard_controller.is_connected = true;

                    processPendingMessages(keyboard_controller);

                    var max_controller_count: usize = xinput.XUSER_MAX_COUNT;
                    if (max_controller_count > (new_input.controllers.len - 1)) max_controller_count = (new_input.controllers.len - 1);

                    for (0..max_controller_count) |controller_index| {
                        const x_controller_index = controller_index + 1;
                        var old_controller = &old_input.controllers[x_controller_index];
                        var new_controller = &new_input.controllers[x_controller_index];

                        var controller_state: xinput.STATE = undefined;
                        if (xinput.XInputGetState(@intCast(controller_index), &controller_state) == win32.ERROR_SUCCESS) {
                            // Controller present
                            const pad = &controller_state.gamepad;

                            const old_buttons = &old_controller.buttons.named;
                            const new_buttons = &new_controller.buttons.named;

                            new_controller.is_connected = true;

                            new_controller.stick_average_x = processXInputStickValue(pad.thumb_l_x, xinput.GAMEPAD_LEFT_THUMB_DEADZONE);
                            new_controller.stick_average_y = processXInputStickValue(pad.thumb_l_y, xinput.GAMEPAD_LEFT_THUMB_DEADZONE);

                            if (new_controller.stick_average_x != 0 or new_controller.stick_average_y != 0) {
                                new_controller.is_analog = true;
                            }

                            if (pad.buttons.dpad_up) {
                                new_controller.stick_average_y = 1;
                                new_controller.is_analog = false;
                            }
                            if (pad.buttons.dpad_down) {
                                new_controller.stick_average_y = -1;
                                new_controller.is_analog = false;
                            }
                            if (pad.buttons.dpad_left) {
                                new_controller.stick_average_x = -1;
                                new_controller.is_analog = false;
                            }
                            if (pad.buttons.dpad_right) {
                                new_controller.stick_average_x = 1;
                                new_controller.is_analog = false;
                            }

                            const threshold = 0.5;
                            processXInputDigitalButton(
                                @bitCast(@as(win32.WORD, if (new_controller.stick_average_y < -threshold) 1 else 0)),
                                &old_buttons.move_down,
                                @enumFromInt(0),
                                &new_buttons.move_down,
                            );
                            processXInputDigitalButton(
                                @bitCast(@as(win32.WORD, if (new_controller.stick_average_y > threshold) 1 else 0)),
                                &old_buttons.move_up,
                                @enumFromInt(0),
                                &new_buttons.move_up,
                            );
                            processXInputDigitalButton(
                                @bitCast(@as(win32.WORD, if (new_controller.stick_average_x < -threshold) 1 else 0)),
                                &old_buttons.move_left,
                                @enumFromInt(0),
                                &new_buttons.move_left,
                            );
                            processXInputDigitalButton(
                                @bitCast(@as(win32.WORD, if (new_controller.stick_average_x > threshold) 1 else 0)),
                                &old_buttons.move_right,
                                @enumFromInt(0),
                                &new_buttons.move_right,
                            );

                            processXInputDigitalButton(pad.buttons, &old_buttons.action_up, .y, &new_buttons.action_up);
                            processXInputDigitalButton(pad.buttons, &old_buttons.action_down, .a, &new_buttons.action_down);
                            processXInputDigitalButton(pad.buttons, &old_buttons.action_left, .x, &new_buttons.action_left);
                            processXInputDigitalButton(pad.buttons, &old_buttons.action_right, .b, &new_buttons.action_right);
                            processXInputDigitalButton(pad.buttons, &old_buttons.left_shoulder, .left_shoulder, &new_buttons.left_shoulder);
                            processXInputDigitalButton(pad.buttons, &old_buttons.right_shoulder, .right_shoulder, &new_buttons.right_shoulder);
                            processXInputDigitalButton(pad.buttons, &old_buttons.back, .back, &new_buttons.back);
                            processXInputDigitalButton(pad.buttons, &old_buttons.start, .start, &new_buttons.start);
                        } else {
                            // Controller not present
                            new_controller.is_connected = false;
                        }

                        const vibration = xinput.VIBRATION{ .left_motor_speed = 60000, .right_motor_speed = 0 };
                        _ = xinput.XInputSetState(@intCast(x_controller_index), &vibration);
                    }

                    var byte_to_lock: u32 = 0;
                    var bytes_to_write: u32 = 0;
                    var frames_to_write: u32 = 0;
                    var target_cursor: u32 = 0;
                    if (audio_valid) {
                        byte_to_lock = (audio_output.running_frame_index * @sizeOf(AudioOutput.Frame)) % audio_output.buffer_byte_size;
                        target_cursor = ((last_play_cursor + (audio_output.latency_frame_count * @sizeOf(AudioOutput.Frame))) % audio_output.buffer_byte_size);

                        bytes_to_write =
                            if (byte_to_lock > target_cursor)
                                (audio_output.buffer_byte_size - byte_to_lock) + target_cursor
                            else
                                target_cursor - byte_to_lock;

                        frames_to_write = bytes_to_write / @sizeOf(AudioOutput.Frame);
                    }

                    var game_sound_output_buffer: v10.AudioBuffer = .{
                        .frames = @ptrCast(audio_output.buffer.ptr),
                        .frame_count = @intCast(frames_to_write),
                        .frames_per_second = audio_fps,
                    };

                    var game_offscreen_buffer: v10.OffscreenBuffer = .{
                        .memory = global_back_buffer.memory,
                        .width = global_back_buffer.width,
                        .height = global_back_buffer.height,
                        .pitch = global_back_buffer.pitch,
                    };

                    const keep_running = v10.updateAndRender(&game_memory, new_input, &game_offscreen_buffer, &game_sound_output_buffer);
                    if (!keep_running) global_running = false;

                    if (audio_valid) {
                        if (options.internal_build) {
                            var play_cursor: win32.DWORD = 0;
                            var write_cursor: win32.DWORD = 0;
                            _ = audio_output.dsound_buffer.?.GetCurrentPosition(&play_cursor, &write_cursor);

                            log.debug("LPC:{} BTL:{} TC:{} BTW:{} - PC:{} WC:{}", .{ last_play_cursor, byte_to_lock, target_cursor, bytes_to_write, play_cursor, write_cursor });
                        }

                        fillAudioBuffer(&audio_output, byte_to_lock, bytes_to_write, &game_sound_output_buffer);
                    }

                    const work_counter = getWallClock();
                    const work_seconds_elapsed = getSecondsElapsed(last_counter, work_counter);

                    var seconds_elapsed_for_frame = work_seconds_elapsed;
                    if (seconds_elapsed_for_frame < target_seconds_per_frame) {
                        while (seconds_elapsed_for_frame < target_seconds_per_frame) {
                            if (sleep_is_granular) {
                                const sleep_ms: win32.DWORD = @intFromFloat(std.time.ms_per_s * (target_seconds_per_frame - seconds_elapsed_for_frame));
                                if (sleep_ms > 0) win32.Sleep(sleep_ms);
                            }
                            seconds_elapsed_for_frame = getSecondsElapsed(last_counter, getWallClock());
                        }
                    } else {
                        log.debug("Missed frame time!", .{});
                    }

                    const end_counter = getWallClock();
                    const ms_per_frame = std.time.ms_per_s * getSecondsElapsed(last_counter, end_counter);
                    last_counter = end_counter;

                    if (options.internal_build) {
                        DEBUG.syncDisplay(&global_back_buffer, @ptrCast(&debug_time_markers), debug_time_markers.len, &audio_output, target_seconds_per_frame);
                    }

                    const dimension = getWindowDimension(window);
                    displayBufferInWindow(device_context, dimension.width, dimension.height, &global_back_buffer);

                    var play_cursor: win32.DWORD = 0;
                    var write_cursor: win32.DWORD = 0;
                    if (audio_output.dsound_buffer.?.GetCurrentPosition(&play_cursor, &write_cursor) == dsound.OK) {
                        last_play_cursor = play_cursor;
                        if (!audio_valid) {
                            audio_output.running_frame_index = write_cursor / @sizeOf(v10.AudioBuffer.Frame);
                            audio_valid = true;
                        }
                    } else {
                        audio_valid = false;
                    }

                    if (options.internal_build and audio_valid) {
                        const marker = &debug_time_markers[debug_time_marker_index];
                        marker.* = .{ .play_cursor = play_cursor, .write_cursor = write_cursor };

                        debug_time_marker_index += 1;
                        if (debug_time_marker_index >= debug_time_markers.len) {
                            debug_time_marker_index = 0;
                        }
                    }

                    const tmp = new_input;
                    new_input = old_input;
                    old_input = tmp;

                    const end_cycle_count = x86_64.rdtscp();
                    const cycles_elapsed: f32 = @floatFromInt(end_cycle_count - last_cycle_count);
                    last_cycle_count = end_cycle_count;

                    const fps = std.time.ms_per_s / ms_per_frame;
                    const mcps = cycles_elapsed / (1000 * 1000);
                    log.info("{d:.2}ms/f,  {d:.2}f/s,  {d:.2}mc/f,  {d:.2}wms", .{ ms_per_frame, fps, mcps, work_seconds_elapsed * std.time.ms_per_s });
                    _ = .{ ms_per_frame, fps, mcps };
                }
            }
        } else {
            log.err("CreateWindow failed!", .{});
        }
    } else {
        log.err("RegisterClass failed!", .{});
    }

    return 0;
}

pub fn windowProcA(window: win32.HWND, message: c_uint, wparam: win32.WPARAM, lparam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    var result: win32.LRESULT = 0;

    switch (message) {
        win32.WM_SIZE => {},

        win32.WM_CLOSE, win32.WM_DESTROY => {
            global_running = false;
        },
        win32.WM_ACTIVATEAPP => {
            log.debug("WM_ACTIVATEAPP", .{});
        },

        win32.WM_SYSKEYDOWN,
        win32.WM_SYSKEYUP,
        win32.WM_KEYDOWN,
        win32.WM_KEYUP,
        => {
            assert(false); // Assume keys are dispatched/handled in the main loop
            const vk_code = wparam;
            const was_down = (lparam & (1 << 30)) != 0;
            const is_down = (lparam & (1 << 31)) == 0;

            if (is_down != was_down) {
                if (vk_code == win32.VK_W) {
                    //
                } else if (vk_code == win32.VK_A) {
                    //
                } else if (vk_code == win32.VK_S) {
                    //
                } else if (vk_code == win32.VK_D) {
                    //
                } else if (vk_code == win32.VK_Q) {
                    //
                } else if (vk_code == win32.VK_E) {
                    //
                } else if (vk_code == win32.VK_UP) {
                    //
                } else if (vk_code == win32.VK_LEFT) {
                    //
                } else if (vk_code == win32.VK_DOWN) {
                    //
                } else if (vk_code == win32.VK_RIGHT) {
                    //
                } else if (vk_code == win32.VK_ESCAPE) {
                    global_running = false;
                } else if (vk_code == win32.VK_SPACE) {
                    log.debug("space: {s} {s}", .{
                        if (is_down) "is_down" else "",
                        if (was_down) "was_down" else "",
                    });
                }

                const alt_key_was_down = (lparam & (1 << 29)) != 0;
                if ((vk_code == win32.VK_F4) and alt_key_was_down) {
                    global_running = false;
                }
            }
        },

        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            const dc = win32.BeginPaint(window, &paint);
            {
                const dimension = getWindowDimension(window);
                displayBufferInWindow(dc, dimension.width, dimension.height, &global_back_buffer);
            }
            _ = win32.EndPaint(window, &paint);
        },

        else => {
            result = win32.DefWindowProcA(window, message, wparam, lparam);
        },
    }

    return result;
}

fn resizeDibSection(buffer: *OffscreenBuffer, width: c_int, height: c_int) bool {
    if (buffer.memory.len > 0) {
        _ = win32.VirtualFree(buffer.memory.ptr, 0, win32.MEM_RELEASE);
    }

    const bytes_per_pixel = 4;
    buffer.width = width;
    buffer.height = height;
    buffer.pitch = buffer.width * bytes_per_pixel;
    buffer.bytes_per_pixel = bytes_per_pixel;

    buffer.info = win32.BITMAPINFO{ .bmiHeader = .{
        .biWidth = buffer.width,
        .biHeight = -buffer.height,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = win32.BI_RGB,
    } };

    const bitmap_memory_size: usize = @intCast(width * height * bytes_per_pixel);
    const memory = win32.VirtualAlloc(
        null,
        bitmap_memory_size,
        win32.MEM_RESERVE | win32.MEM_COMMIT,
        win32.PAGE_READWRITE,
    );
    buffer.memory = @as([*]u8, @ptrCast(memory))[0..bitmap_memory_size];
    return memory != null;
}

fn displayBufferInWindow(dc: win32.HDC, window_width: i32, window_height: i32, buffer: *OffscreenBuffer) void {

    // TODO: Only set this after resize?
    if (window_width < buffer.width or window_height < buffer.height) {
        _ = win32.SetStretchBltMode(dc, win32.STRETCH_DELETESCANS);
    } else {
        _ = win32.SetStretchBltMode(dc, 0);
    }

    win32.StretchDIBits(dc, 0, 0, window_width, window_height, 0, 0, buffer.width, buffer.height, buffer.memory.ptr, &buffer.info, win32.DIB_RGB_COLORS, win32.SRCCOPY);
}

pub const DEBUG = struct {
    pub fn readEntireFile(path: [*:0]const u8) callconv(.c) v10.DEBUG.ReadFileResult {
        var result = v10.DEBUG.ReadFileResult{};

        const handle = win32.CreateFileA(path, win32.GENERIC_READ, win32.FILE_SHARE_READ, null, win32.OPEN_EXISTING, 0, null);

        if (handle != win32.INVALID_HANDLE_VALUE) {
            var file_size: win32.LARGE_INTEGER = undefined;
            if (win32.GetFileSizeEx(handle, &file_size) != 0) {
                if (win32.VirtualAlloc(null, file_size.quad_part, win32.MEM_RESERVE | win32.MEM_COMMIT, win32.PAGE_READWRITE)) |alloc_res| {
                    const file_size_32 = v10.safeTruncateU64(file_size.quad_part);

                    var bytes_read: win32.DWORD = undefined;
                    if (win32.ReadFile(handle, alloc_res, file_size_32, &bytes_read, null) != 0 and
                        file_size_32 == bytes_read)
                    {
                        result.size = file_size_32;
                        result.content = alloc_res;
                    } else {
                        freeFileMemory(alloc_res, file_size_32);
                    }
                }
            } else {
                log.warn("GetFileSizeEx failed", .{});
            }

            _ = win32.CloseHandle(handle);
        } else {
            log.warn("Failed to open file: '{s}'", .{path});
        }

        return result;
    }

    pub fn writeEntireFile(path: [*:0]const u8, memory: *anyopaque, size: usize) callconv(.c) bool {
        var result = false;

        const handle = win32.CreateFileA(path, win32.GENERIC_WRITE, 0, null, win32.CREATE_ALWAYS, 0, null);

        if (handle != win32.INVALID_HANDLE_VALUE) {
            var written: win32.DWORD = undefined;

            const memory_size_32 = v10.safeTruncateU64(size);

            if (win32.WriteFile(handle, memory, memory_size_32, &written, null) != 0) {
                result = true;
            } else {
                log.warn("Failed to write file: '{s}'", .{path});
            }

            _ = win32.CloseHandle(handle);
        } else {
            log.warn("Failed to open file: '{s}'", .{path});
        }

        return result;
    }

    pub fn freeFileMemory(memory: ?*anyopaque, size: usize) callconv(.c) void {
        if (memory) |m| {
            assert(size > 0);
            _ = win32.VirtualFree(m, 0, win32.MEM_DECOMMIT);
        }
    }

    pub fn drawVertical(buffer: *OffscreenBuffer, x: i32, top: i32, bottom: i32, color: u32) callconv(.c) void {
        var cursor: [*]u8 = buffer.memory.ptr + @as(usize, @intCast((x * buffer.bytes_per_pixel) + (top * buffer.pitch)));

        for (@intCast(top)..@intCast(bottom + 1)) |_| {
            const pixel: *u32 = @ptrCast(@alignCast(cursor));
            pixel.* = color;
            cursor += @intCast(buffer.pitch);
        }
    }

    pub fn drawAudioBufferMarker(buffer: *OffscreenBuffer, marker: *const AudioTimeMarker, c: f32, pad_x: i32, top: i32, bottom: i32) callconv(.c) void {
        const play_x: i32 = pad_x + @as(i32, @intFromFloat(c * @as(f32, @floatFromInt(marker.play_cursor))));
        const write_x: i32 = pad_x + @as(i32, @intFromFloat(c * @as(f32, @floatFromInt(marker.write_cursor))));

        DEBUG.drawVertical(buffer, play_x, top, bottom, 0xffffff);
        DEBUG.drawVertical(buffer, write_x, top, bottom, 0xffff0000);
    }

    pub fn syncDisplay(buffer: *OffscreenBuffer, markers: [*]AudioTimeMarker, markers_len: usize, audio_output: *AudioOutput, seconds_per_frame: f32) callconv(.c) void {
        _ = seconds_per_frame;

        const pad_x = 16;
        const pad_y = 16;
        const top = pad_y;
        const bottom = global_back_buffer.height - pad_y;

        const c = @as(f32, @floatFromInt(buffer.width - (2 * pad_x))) / @as(f32, @floatFromInt(audio_output.buffer_byte_size));

        for (markers[0..markers_len]) |marker| {
            drawAudioBufferMarker(buffer, &marker, c, pad_x, top, bottom);
        }
    }

    pub const AudioTimeMarker = struct {
        play_cursor: win32.DWORD = 0,
        write_cursor: win32.DWORD = 0,
    };
};

comptime {
    if (options.internal_build)
        for (@typeInfo(DEBUG).@"struct".decls) |decl| {
            const decl_type = @TypeOf(@field(DEBUG, decl.name));
            const decl_type_info = @typeInfo(decl_type);
            if (decl_type_info == .@"fn") {
                @export(&@field(DEBUG, decl.name), .{ .name = decl.name, .linkage = .strong });
            }
        };
}
