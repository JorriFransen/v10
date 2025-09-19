const std = @import("std");
const log = std.log.scoped(.win32_v10);
const win32 = @import("win32/win32.zig");
const xinput = @import("win32/xinput.zig");
const dsound = @import("win32/direct_sound.zig");

const assert = std.debug.assert;

var global_running = false;
var global_back_buffer: OffscreenBuffer = undefined;
var global_sound_buffer: *dsound.IDirectSoundBuffer = undefined;

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
            var primary_buffer: *dsound.IDirectSoundBuffer = undefined;
            if (ds.CreateSoundBuffer(&buffer_desc, &primary_buffer, null) == dsound.OK) {
                if (primary_buffer.SetFormat(&waveformat) == dsound.OK) {
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
        if (ds.CreateSoundBuffer(&buffer_desc, &global_sound_buffer, null) == dsound.OK) {
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

            const audio_frames_per_second = 48000;
            const audio_bytes_per_sample = @sizeOf(i16);
            const audio_bytes_per_frame = audio_bytes_per_sample * 2;
            const audio_buffer_byte_size = audio_frames_per_second * audio_bytes_per_frame;
            const tone_hz = 256;
            const tone_volume = 6000;
            var running_frame_index: u32 = 0;
            const wave_period: u32 = audio_frames_per_second / tone_hz;

            xinput.load();
            win32InitDSound(window, audio_frames_per_second, audio_buffer_byte_size);
            var sound_is_playing = false;

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
                        y_offset -%= @divTrunc(pad.thumb_l_y, 4096);
                    } else {
                        // Controller not present
                    }
                }

                // const vibration = xinput.VIBRATION{ .left_motor_speed = 60000, .right_motor_speed = 0 };
                // _ = xinput.XInputSetState(0, &vibration);

                renderWeirdGradient(&global_back_buffer, x_offset, y_offset);

                var play_cursor: u32 = undefined;
                var write_cursor: u32 = undefined;
                if (global_sound_buffer.GetCurrentPosition(&play_cursor, &write_cursor) == dsound.OK) {
                    var region1_ptr: *anyopaque = undefined;
                    var region1_bytes: u32 = undefined;
                    var region2_ptr: *anyopaque = undefined;
                    var region2_bytes: u32 = undefined;

                    const byte_to_lock: win32.DWORD = (running_frame_index * audio_bytes_per_frame) % audio_buffer_byte_size;
                    const bytes_to_write: u32 =
                        if (byte_to_lock == play_cursor)
                            if (sound_is_playing) 0 else audio_buffer_byte_size
                        else if (byte_to_lock > play_cursor)
                            (audio_buffer_byte_size - byte_to_lock) + play_cursor
                        else
                            play_cursor - byte_to_lock;

                    if (global_sound_buffer.Lock(byte_to_lock, bytes_to_write, &region1_ptr, &region1_bytes, &region2_ptr, &region2_bytes, 0) == dsound.OK) {
                        const region_1_frame_count = region1_bytes / audio_bytes_per_frame;
                        var sample_out: [*]i16 = @ptrCast(@alignCast(region1_ptr));
                        for (0..region_1_frame_count) |_| {
                            const t: f32 = 2 * std.math.pi * (@as(f32, @floatFromInt(running_frame_index)) / @as(f32, @floatFromInt(wave_period)));
                            const sine_value: f32 = @sin(t);
                            const sample_value: i16 = @intFromFloat(@as(f32, tone_volume) * sine_value);
                            sample_out[0] = sample_value;
                            sample_out += 1;

                            sample_out[0] = sample_value;
                            sample_out += 1;

                            running_frame_index +%= 1;
                        }

                        const region_2_frame_count = region2_bytes / audio_bytes_per_frame;
                        sample_out = @ptrCast(@alignCast(region2_ptr));
                        for (0..region_2_frame_count) |_| {
                            const t: f32 = 2 * std.math.pi * (@as(f32, @floatFromInt(running_frame_index)) / @as(f32, @floatFromInt(wave_period)));
                            const sine_value: f32 = @sin(t);
                            const sample_value: i16 = @intFromFloat(@as(f32, tone_volume) * sine_value);
                            sample_out[0] = sample_value;
                            sample_out += 1;

                            sample_out[0] = sample_value;
                            sample_out += 1;

                            running_frame_index +%= 1;
                        }

                        _ = global_sound_buffer.Unlock(region1_ptr, region1_bytes, region2_ptr, region2_bytes);
                    }
                }
                if (!sound_is_playing) {
                    sound_is_playing = true;
                    _ = global_sound_buffer.Play(0, 0, dsound.BPLAY_LOOPING);
                }

                const dimension = getWindowDimension(window);
                win32DisplayBufferInWindow(device_context, dimension.width, dimension.height, &global_back_buffer);
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

fn renderWeirdGradient(buffer: *OffscreenBuffer, xoffset: i32, yoffset: i32) void {
    const uwidth: usize = @intCast(buffer.width);
    const uheight: usize = @intCast(buffer.height);

    var row: [*]u8 = buffer.memory.ptr;
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
        row += @intCast(buffer.pitch);
    }
}
