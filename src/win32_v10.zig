const std = @import("std");
const log = std.log.scoped(.win32_v10);
const win32 = @import("win32/win32.zig");
const xinput = @import("win32/xinput.zig");
const dsound = @import("win32/direct_sound.zig");
const x86_64 = @import("x86_64.zig");
const v10 = @import("v10.zig");

const assert = std.debug.assert;

var global_running = false;
var global_back_buffer: OffscreenBuffer = undefined;
var global_sound_buffer_opt: ?*dsound.IDirectSoundBuffer = undefined;

pub const OffscreenBuffer = struct {
    info: win32.BITMAPINFO,
    memory: []u8,
    width: i32,
    height: i32,
    pitch: i32,
};

pub const WindowDimensions = struct {
    width: i32,
    height: i32,
};

pub const Win32SoundOutput = struct {
    frames_per_second: u32 = 0,
    bytes_per_sample: u32 = 0,
    bytes_per_frame: u32 = 0,
    buffer_byte_size: u32 = 0,
    tone_hz: u32 = 0,
    tone_volume: u32 = 0,
    running_frame_index: u32 = 0,
    wave_period: u32 = 0,
    t_sine: f32 = 0,
    latency_frame_count: u32 = 0,
};

fn win32FillSoundBuffer(buffer: *dsound.IDirectSoundBuffer, sound_output: *Win32SoundOutput, byte_to_lock: u32, bytes_to_write: u32) void {
    var region1_ptr: *anyopaque = undefined;
    var region1_bytes: u32 = undefined;
    var region2_ptr: *anyopaque = undefined;
    var region2_bytes: u32 = undefined;

    if (buffer.Lock(byte_to_lock, bytes_to_write, &region1_ptr, &region1_bytes, &region2_ptr, &region2_bytes, 0) == dsound.OK) {
        const region_1_frame_count = region1_bytes / sound_output.bytes_per_frame;
        var sample_out: [*]i16 = @ptrCast(@alignCast(region1_ptr));
        for (0..region_1_frame_count) |_| {
            const sine_value: f32 = @sin(sound_output.t_sine);
            const sample_value: i16 = @intFromFloat(@as(f32, @floatFromInt(sound_output.tone_volume)) * sine_value);
            sample_out[0] = sample_value;
            sample_out += 1;

            sample_out[0] = sample_value;
            sample_out += 1;

            sound_output.t_sine += std.math.tau / @as(f32, @floatFromInt(sound_output.wave_period));
            if (sound_output.t_sine > std.math.tau) sound_output.t_sine -= std.math.tau;
            sound_output.running_frame_index +%= 1;
        }

        const region_2_frame_count = region2_bytes / sound_output.bytes_per_frame;
        sample_out = @ptrCast(@alignCast(region2_ptr));
        for (0..region_2_frame_count) |_| {
            const sine_value: f32 = @sin(sound_output.t_sine);
            const sample_value: i16 = @intFromFloat(@as(f32, @floatFromInt(sound_output.tone_volume)) * sine_value);
            sample_out[0] = sample_value;
            sample_out += 1;

            sample_out[0] = sample_value;
            sample_out += 1;

            sound_output.t_sine += std.math.tau / @as(f32, @floatFromInt(sound_output.wave_period));
            if (sound_output.t_sine > std.math.tau) sound_output.t_sine -= std.math.tau;
            sound_output.running_frame_index +%= 1;
        }

        _ = buffer.Unlock(region1_ptr, region1_bytes, region2_ptr, region2_bytes);
    }
}

fn win32InitDSound(window: win32.HWND, samples_per_second: u32, buffer_size: u32) void {
    dsound.load();

    var ds: *dsound.IDirectSound = undefined;
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
        if (ds.CreateSoundBuffer(&buffer_desc, &global_sound_buffer_opt, null) == dsound.OK) {
            log.debug("DSound secondary buffer created", .{});
        } else {
            log.warn("DSound CreateSoundBuffer failed (secondary buffer)", .{});
        }
    } else {
        log.warn("DirectSoundCreate failed", .{});
    }
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

    win32ResizeDibSection(&global_back_buffer, 1280, 720);

    var qpf_result: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceFrequency(&qpf_result);
    const perf_count_frequency = qpf_result.quad_part;

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

        if (window_opt) |window| {
            global_running = true;
            const device_context = win32.GetDC(window);

            var x_offset: i32 = 0;
            var y_offset: i32 = 0;

            xinput.load();

            var sound_output: Win32SoundOutput = .{};
            sound_output.frames_per_second = 48000;
            sound_output.bytes_per_sample = @sizeOf(i16);
            sound_output.bytes_per_frame = sound_output.bytes_per_sample * 2;
            sound_output.buffer_byte_size = sound_output.frames_per_second * sound_output.bytes_per_frame;
            sound_output.tone_hz = 256;
            sound_output.tone_volume = 3000;
            sound_output.running_frame_index = 0;
            sound_output.wave_period = sound_output.frames_per_second / sound_output.tone_hz;
            sound_output.t_sine = 0;
            sound_output.latency_frame_count = sound_output.frames_per_second / 15;

            win32InitDSound(window, sound_output.frames_per_second, sound_output.buffer_byte_size);
            if (global_sound_buffer_opt) |gsb| {
                win32FillSoundBuffer(gsb, &sound_output, 0, sound_output.latency_frame_count * sound_output.bytes_per_frame);
                _ = gsb.Play(0, 0, dsound.BPLAY_LOOPING);
            }

            var last_counter: win32.LARGE_INTEGER = undefined;
            _ = win32.QueryPerformanceFrequency(&last_counter);

            var last_cycle_count = x86_64.rdtsc();

            while (global_running) {
                var msg = win32.MSG{};
                while (win32.PeekMessageA(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
                    if (msg.message == win32.WM_QUIT) {
                        global_running = false;
                    }
                    _ = win32.TranslateMessage(&msg);
                    _ = win32.DispatchMessageA(&msg);
                }

                for (0..xinput.XUSER_MAX_COUNT) |controller_index| {
                    var controller_state: xinput.STATE = undefined;
                    if (xinput.XInputGetState(@intCast(controller_index), &controller_state) == win32.ERROR_SUCCESS) {
                        // Controller present
                        const pad = &controller_state.gamepad;

                        x_offset +%= @divTrunc(pad.thumb_l_x, 4096);
                        y_offset +%= @divTrunc(pad.thumb_l_y, 4096);

                        sound_output.tone_hz = @intFromFloat(512 + (256 * (@as(f32, @floatFromInt(pad.thumb_l_y)) / 30000)));
                        sound_output.wave_period = sound_output.frames_per_second / sound_output.tone_hz;
                    } else {
                        // Controller not present
                    }
                }

                x_offset += 1;

                // const vibration = xinput.VIBRATION{ .left_motor_speed = 60000, .right_motor_speed = 0 };
                // _ = xinput.XInputSetState(0, &vibration);

                var game_offscreen_buffer = v10.game.OffscreenBuffer{
                    .memory = global_back_buffer.memory,
                    .width = global_back_buffer.width,
                    .height = global_back_buffer.height,
                    .pitch = global_back_buffer.pitch,
                };
                v10.game.updateAndRender(&game_offscreen_buffer, x_offset, y_offset);

                var play_cursor: u32 = undefined;
                var write_cursor: u32 = undefined;
                if (global_sound_buffer_opt) |gsb| if (gsb.GetCurrentPosition(&play_cursor, &write_cursor) == dsound.OK) {
                    const byte_to_lock: u32 = (sound_output.running_frame_index * sound_output.bytes_per_frame) % sound_output.buffer_byte_size;
                    const target_cursor: u32 = ((play_cursor + (sound_output.latency_frame_count * sound_output.bytes_per_frame)) % sound_output.buffer_byte_size);
                    const bytes_to_write: u32 =
                        if (byte_to_lock > target_cursor)
                            (sound_output.buffer_byte_size - byte_to_lock) + target_cursor
                        else
                            target_cursor - byte_to_lock;

                    win32FillSoundBuffer(gsb, &sound_output, byte_to_lock, bytes_to_write);
                };

                const dimension = getWindowDimension(window);
                win32DisplayBufferInWindow(device_context, dimension.width, dimension.height, &global_back_buffer);

                const end_cycle_count = x86_64.rdtscp();

                var end_counter: win32.LARGE_INTEGER = undefined;
                _ = win32.QueryPerformanceCounter(&end_counter);

                const cycles_elapsed: f32 = @floatFromInt(end_cycle_count - last_cycle_count);
                const counter_elapsed: f32 = @floatFromInt(end_counter.quad_part - last_counter.quad_part);
                const ms_per_frame = (1000 * counter_elapsed) / @as(f32, @floatFromInt(perf_count_frequency));
                const fps = @as(f32, @floatFromInt(perf_count_frequency)) / counter_elapsed;
                const mcps = cycles_elapsed / (1000 * 1000);
                // log.info("{d:.2}ms/f,  {d:.2}f/s,  {d:.2}kc/f", .{ ms_per_frame, fps, mcps });
                _ = .{ ms_per_frame, fps, mcps };

                last_counter = end_counter;
                last_cycle_count = end_cycle_count;
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
                win32DisplayBufferInWindow(dc, dimension.width, dimension.height, &global_back_buffer);
            }
            _ = win32.EndPaint(window, &paint);
        },

        else => {
            result = win32.DefWindowProcA(window, message, wparam, lparam);
        },
    }

    return result;
}

fn win32ResizeDibSection(buffer: *OffscreenBuffer, width: c_int, height: c_int) void {
    if (buffer.memory.len > 0) {
        _ = win32.VirtualFree(buffer.memory.ptr, 0, win32.MEM_RELEASE);
    }

    const bytes_per_pixel = 4;
    buffer.width = width;
    buffer.height = height;
    buffer.pitch = buffer.width * bytes_per_pixel;

    buffer.info = win32.BITMAPINFO{ .bmiHeader = .{
        .biWidth = buffer.width,
        .biHeight = -buffer.height,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = win32.BI_RGB,
    } };

    const bitmap_memory_size: usize = @intCast(width * height * bytes_per_pixel);
    buffer.memory = @as([*]u8, @ptrCast(win32.VirtualAlloc(
        null,
        bitmap_memory_size,
        win32.MEM_RESERVE | win32.MEM_COMMIT,
        win32.PAGE_READWRITE,
    )))[0..bitmap_memory_size];
}

fn win32DisplayBufferInWindow(dc: win32.HDC, window_width: i32, window_height: i32, buffer: *OffscreenBuffer) void {

    // TODO: Only set this after resize?
    if (window_width < buffer.width or window_height < buffer.height) {
        _ = win32.SetStretchBltMode(dc, win32.STRETCH_DELETESCANS);
    } else {
        _ = win32.SetStretchBltMode(dc, 0);
    }

    win32.StretchDIBits(dc, 0, 0, window_width, window_height, 0, 0, buffer.width, buffer.height, buffer.memory.ptr, &buffer.info, win32.DIB_RGB_COLORS, win32.SRCCOPY);
}
