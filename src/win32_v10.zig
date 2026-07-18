const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.win32_v10);
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");

const options = @import("options");
const mem = @import("mem");
const win32 = @import("win32");
const xinput = win32.xinput;
const dsound = win32.direct_sound;

const arch = @import("arch").arch;

const math = @import("math");

const common = @import("v10_common");

const GameCode = common.GameCode;
const Memory = common.Memory;
const OffscreenBuffer = common.OffscreenBuffer;
const Input = common.Input;
const ControllerInput = common.ControllerInput;
const ButtonState = common.ButtonState;
const ThreadContext = common.ThreadContext;
const AudioBuffer = common.AudioBuffer;

const std_log_scope_levels = common.std_log_scope_levels ++ [_]std.log.ScopeLevel{
    .{ .scope = .win32_v10, .level = .info },
    .{ .scope = .xinput, .level = .debug },
    .{ .scope = .dsound, .level = .info },
};

pub const std_options: std.Options = blk: {
    var o = common.std_options;

    o.log_scope_levels = o.log_scope_levels ++ std_log_scope_levels;

    break :blk o;
};

var stderr_buf: [2048]u8 = undefined;
var stderr: *std.Io.Writer = undefined;
var stdout_buf: [2048]u8 = undefined;
var stdout: *std.Io.Writer = undefined;

var global_running = false;
var global_pause = false;
var global_back_buffer: Win32OffscreenBuffer = undefined;
var global_perf_count_frequency: u64 = undefined;
var global_DEBUG_show_cursor = options.internal_build;
var global_window_position: win32.WINDOWPLACEMENT = .{};

inline fn getWallClock() win32.LARGE_INTEGER {
    var result: win32.LARGE_INTEGER = .{ .quad_part = 0 };
    _ = win32.QueryPerformanceCounter(&result);
    return result;
}

inline fn getSecondsElapsed(start: win32.LARGE_INTEGER, end: win32.LARGE_INTEGER) f32 {
    const diff: f32 = @floatFromInt(end.quad_part - start.quad_part);
    return diff / @as(f32, @floatFromInt(global_perf_count_frequency));
}

pub const Win32OffscreenBuffer = struct {
    info: win32.BITMAPINFO,
    memory_opt: ?[*]u8,
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
    frames_per_video_frame: u32,
    bytes_per_video_frame: u32,

    buffer_byte_size: u32,
    running_frame_index: u32,
    safety_frame_bytes: u32,

    const Sample = AudioBuffer.Sample;
    const Frame = AudioBuffer.Frame;
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

fn fillAudioBuffer(audio_output: *AudioOutput, byte_to_lock: u32, bytes_to_write: u32, source_buffer: *AudioBuffer) void {
    var region1_ptr: *anyopaque = undefined;
    var region1_bytes: u32 = undefined;
    var region2_ptr: *anyopaque = undefined;
    var region2_bytes: u32 = undefined;

    if (audio_output.dsound_buffer) |buf| if (buf.Lock(byte_to_lock, bytes_to_write, &region1_ptr, &region1_bytes, &region2_ptr, &region2_bytes, 0) == dsound.OK) {
        const region_1_frame_count = region1_bytes / @sizeOf(AudioOutput.Frame);
        var dest_sample: [*]i16 = @ptrCast(@alignCast(region1_ptr));
        for (0..region_1_frame_count, source_buffer.frames[0..region_1_frame_count]) |_, source_frame| {
            dest_sample[0] = source_frame.left;
            dest_sample += 1;

            dest_sample[0] = source_frame.right;
            dest_sample += 1;

            audio_output.running_frame_index +%= 1;
        }

        const region_2_frame_count = region2_bytes / @sizeOf(AudioOutput.Frame);
        dest_sample = @ptrCast(@alignCast(region2_ptr));
        for (0..region_2_frame_count, source_buffer.frames[region_1_frame_count..]) |_, source_frame| {
            dest_sample[0] = source_frame.left;
            dest_sample += 1;

            dest_sample[0] = source_frame.right;
            dest_sample += 1;

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
                    dsound.log.debug("primary buffer format set", .{});
                } else {
                    dsound.log.warn("primary_buffer.SetFormat failed", .{});
                }
            } else {
                dsound.log.warn("CreateSoundBuffer failed (primary buffer)", .{});
            }
        } else {
            dsound.log.warn("SetCooperativeLevel failed", .{});
        }

        // Create secondary buffer
        const buffer_desc = dsound.BufferDesc{
            .wave_format = &waveformat,
            .buffer_bytes = buffer_size,
        };

        if (ds.CreateSoundBuffer(&buffer_desc, &sound_buffer_opt, null) == dsound.OK and sound_buffer_opt != null) {
            dsound.log.debug("secondary buffer created", .{});
        } else {
            dsound.log.warn("CreateSoundBuffer failed (secondary buffer)", .{});
        }
    } else {
        dsound.log.warn("DirectSoundCreate failed", .{});
    }

    return sound_buffer_opt;
}

const GamepadButton = std.meta.FieldEnum(xinput.GamepadButtonBits);

fn processPendingMessages(shared_state: *common.SharedState, keyboard_controller: *ControllerInput) void {
    var msg = win32.MSG{};

    const buttons = &keyboard_controller.buttons.named;

    while (win32.PeekMessageA(&msg, null, 0, 0, win32.PM_REMOVE) != .FALSE) {
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
                        processKeyboardMessage(&buttons.back, is_down);
                    } else if (vk_code == win32.VK_SPACE) {
                        processKeyboardMessage(&buttons.start, is_down);
                    }

                    if (options.internal_build and is_down) {
                        if (vk_code == win32.VK_P) {
                            global_pause = !global_pause;
                        } else if (vk_code == win32.VK_L) {
                            if (shared_state.input_recording_index == 0 and shared_state.input_playing_index == 0) {
                                beginRecordingInput(shared_state, 1);
                            } else if (shared_state.input_recording_index == 1) {
                                endRecordingInput(shared_state);
                                beginInputPlayback(shared_state, 1);
                            } else {
                                endInputPlayback(shared_state);
                                // TODO: Reset input, keys may be stuck in down state
                            }
                        }

                        const alt_key_was_down = (msg.lParam & (1 << 29)) != 0;
                        if ((vk_code == win32.VK_F4) and alt_key_was_down) {
                            global_running = false;
                        } else if ((vk_code == win32.VK_RETURN and alt_key_was_down) or
                            vk_code == win32.VK_F11)
                        {
                            toggleFullscreen(msg.hwnd.?);
                        }
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

fn processKeyboardMessage(new_state: *ButtonState, ended_down: bool) void {
    if (new_state.ended_down != ended_down) {
        new_state.ended_down = ended_down;
        new_state.half_transition_count += 1;
    }
}

fn processXInputDigitalButton(xinput_button_state: xinput.GamepadButtonBits, old_state: *const ButtonState, comptime button: GamepadButton, new_state: *ButtonState) void {
    new_state.ended_down = @field(xinput_button_state, @tagName(button));
    new_state.half_transition_count = if (old_state.ended_down == new_state.ended_down) 1 else 0;
}

fn processXInputStickValue(value: win32.SHORT, deadzone: win32.SHORT) f32 {
    var result: f32 = 0;

    const fvalue: f32 = @floatFromInt(value);
    if (value < -deadzone) {
        result = fvalue / -@as(f32, @floatFromInt(math.minInt(win32.SHORT)));
    } else if (value > deadzone) {
        result = fvalue / @as(f32, @floatFromInt(math.maxInt(win32.SHORT)));
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

const use_debug_allocator = switch (builtin.mode) {
    .Debug => true,
    .ReleaseSafe => !builtin.link_libc, // Not ideal, but the best we have for now.
    .ReleaseFast, .ReleaseSmall => !builtin.link_libc and builtin.single_threaded, // Also not ideal.
};
var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main(init: std.process.Init.Minimal) u8 {
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

    if (win32.AttachConsole(win32.ATTACH_PARENT_PROCESS).toBool() == false) {
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
    // const command_line = win32.GetCommandLineA();
    //
    // var startup_info: win32.STARTUPINFOA = undefined;
    // win32.GetStartupInfoA(&startup_info);

    const ret_code = windowsEntry(io, gpa, instance) catch 1;
    assert(ret_code >= 0);
    return @intCast(ret_code);
}

pub fn windowsEntry(
    io: std.Io,
    gpa: Allocator,
    instance: win32.HINSTANCE,
) !c_int {
    var shared_state: common.SharedState = .{};
    var thread_context: ThreadContext = .{ .io = io };

    try common.runAssetCompiler(io, gpa, stderr, stdout);

    const cwd_len = win32.GetCurrentDirectoryA(shared_state.cwd_buf.len, @ptrCast(&shared_state.cwd_buf));
    shared_state.cwd = shared_state.cwd_buf[0..cwd_len];
    log.info("cwd: '{s}'", .{shared_state.cwd});

    _ = win32.GetModuleFileNameA(null, @ptrCast(&shared_state.exe_dir_path_buf), shared_state.exe_dir_path_buf.len);
    const exe_name: [*:0]u8 = @ptrCast(&shared_state.exe_dir_path_buf);
    log.info("exe name: '{s}'", .{exe_name});
    shared_state.exe_dir_path = std.fs.path.dirname(std.mem.span(exe_name)) orelse unreachable;
    log.info("exe dir: '{s}'", .{shared_state.exe_dir_path});

    var source_dll_name_buf: [std.Io.Dir.max_path_bytes]u8 = @splat(0);
    var temp_dll_name_buf: [std.Io.Dir.max_path_bytes]u8 = @splat(0);
    var gamecode_lock_file_name_buf: [std.Io.Dir.max_path_bytes]u8 = @splat(0);

    const source_dll_name = try shared_state.buildExePathFilename(&source_dll_name_buf, "v10_game.dll");
    const temp_dll_name = try shared_state.buildExePathFilename(&temp_dll_name_buf, "v10_temp.dll");
    const gamecode_lock_file_name = try shared_state.buildExePathFilename(&gamecode_lock_file_name_buf, "lock.tmp");

    log.info("source dll: '{s}'", .{source_dll_name});
    log.info("temp dll: '{s}'", .{temp_dll_name});
    log.info("gamecode load lock: '{s}'", .{gamecode_lock_file_name});

    var qpf_result: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceFrequency(&qpf_result);
    global_perf_count_frequency = qpf_result.quad_part;

    const desired_scheduler_ms = 1;
    const sleep_is_granular = win32.timeBeginPeriod(desired_scheduler_ms) == win32.TIMERR_NOERROR;

    const back_buffer_width = 960;
    const back_buffer_height = 540;

    const window_class = win32.WNDCLASSA{
        .style = win32.CS_HREDRAW | win32.CS_VREDRAW,
        .lpfnWndProc = mainWindowCallback,
        .hInstance = instance,
        .lpszClassName = "v10_window_class",
        .hCursor = win32.LoadCursorA(null, win32.IDC_ARROW),
    };

    if (win32.RegisterClassA(&window_class) != 0) {
        const style: win32.DWORD = win32.WS_OVERLAPPEDWINDOW | win32.WS_VISIBLE;
        const ex_style: win32.DWORD = 0; //win32.WS_EX_TOPMOST | win32.WS_EX_LAYERED;

        var client_rect = win32.RECT{
            .left = 0,
            .top = 0,
            .right = back_buffer_width + 20, // The buffer is currently being drawn with a 10 pixel gutter
            .bottom = back_buffer_height + 20,
        };
        log.debug("suggested window client rect: {}", .{client_rect});
        const awr_rc = win32.AdjustWindowRectEx(&client_rect, style, .FALSE, ex_style);
        assert(awr_rc != win32.FALSE);

        log.debug("adjusted window client rect: {}", .{client_rect});

        const request_width = client_rect.right - client_rect.left;
        const request_height = client_rect.bottom - client_rect.top;
        log.info("request window (client rect) size: {},{}", .{ request_width, request_height });

        const window_opt = win32.CreateWindowExA(
            ex_style,
            window_class.lpszClassName,
            "v10",
            style,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            request_width,
            request_height,
            null,
            null,
            instance,
            null,
        );

        if (window_opt) |window| {
            global_running = true;

            // TODO: Manifest?
            _ = win32.SetProcessDpiAwareness(.PER_MONITOR_DPI_AWARE);

            var monitor_refresh_hz: c_int = 60;
            const dc = win32.GetDC(window);
            const win32_refresh_hz = win32.GetDeviceCaps(dc, win32.VREFRESH);
            if (win32_refresh_hz > 1) {
                monitor_refresh_hz = win32_refresh_hz;
                log.info("Detected monitor refresh rate: {}", .{monitor_refresh_hz});
            } else {
                log.warn("Could not detect monitor refresh rate, fallback to: {}", .{monitor_refresh_hz});
            }
            _ = win32.ReleaseDC(window, dc);

            if (options.internal_build and monitor_refresh_hz > 60) {
                log.warn("Capping update hz to 60 (/ 2)", .{});
                monitor_refresh_hz = 60;
            }

            const game_update_hz: f32 = @as(f32, @floatFromInt(monitor_refresh_hz)) / 2;
            const target_seconds_per_frame: f32 = 1.0 / game_update_hz;

            const dib_allocated = resizeDibSection(&global_back_buffer, back_buffer_width, back_buffer_height);

            const audio_fps = 48000;
            const audio_buffer_byte_size = audio_fps * @sizeOf(AudioBuffer.Frame);
            const frames_per_video_frame: u32 = @intFromFloat(@as(f32, @floatFromInt(audio_fps)) / game_update_hz);

            var audio_output: AudioOutput = .{
                .dsound_buffer = initDSound(window, audio_fps, audio_buffer_byte_size),
                .frames_per_second = audio_fps,
                .frames_per_video_frame = frames_per_video_frame,
                .bytes_per_video_frame = frames_per_video_frame * @sizeOf(AudioOutput.Frame),
                .buffer_byte_size = audio_buffer_byte_size,
                .running_frame_index = 0,
                .safety_frame_bytes = @as(u32, @intFromFloat((audio_fps / game_update_hz) / 3)) * @sizeOf(AudioOutput.Frame),
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

            const permanent_storage_size = mem.MiB * 256;
            const transient_storage_size = mem.GiB * 1;
            const total_size = permanent_storage_size + transient_storage_size;

            const perm_opt: ?[*]u8 = win32.VirtualAlloc(
                base_address,
                total_size,
                win32.MEM_RESERVE | win32.MEM_COMMIT,
                win32.PAGE_READWRITE,
            );

            const trans_opt: ?[*]u8 = if (perm_opt) |p|
                @as([*]u8, @ptrCast(p)) + permanent_storage_size
            else
                null;

            shared_state.game_memory_block = if (perm_opt) |p| p[0..total_size] else &.{};

            log.info("perm:  {*}", .{perm_opt});
            log.info("trans: {*}", .{trans_opt});

            var game_memory: Memory = .{
                .initialized = false,
                .permanent = if (perm_opt) |p| p[0..permanent_storage_size] else &.{},
                .transient = if (trans_opt) |t| t[0..transient_storage_size] else &.{},

                .debug = .{
                    .readEntireFile = &DEBUG.readEntireFile,
                    .freeFileMemory = &DEBUG.freeFileMemory,
                    .writeEntireFile = &DEBUG.writeEntireFile,
                },
            };

            if (options.internal_build) {
                for (&shared_state.replay_buffers, 1..) |*replay_buffer, i| {
                    const file_name = shared_state.getInputRecordingPath(&replay_buffer.filname_buf, false, i);

                    const file_handle = win32.CreateFileA(file_name, win32.GENERIC_READ | win32.GENERIC_WRITE, 0, null, win32.CREATE_ALWAYS, 0, null);
                    replay_buffer.file_handle = .{ .handle = file_handle, .flags = .{ .nonblocking = false } };

                    const max_size: win32.LARGE_INTEGER = .{ .quad_part = shared_state.game_memory_block.len };

                    const mapping = win32.CreateFileMappingA(file_handle, null, win32.PAGE_READWRITE, @intCast(max_size.u.high_part), max_size.u.low_part, null);
                    replay_buffer.memory_map = .{ .handle = mapping, .flags = .{ .nonblocking = false } };

                    if (win32.MapViewOfFile(mapping, win32.FILE_MAP_ALL_ACCESS, 0, 0, shared_state.game_memory_block.len)) |ptr| {
                        replay_buffer.memory = @as([*]u8, @ptrCast(ptr))[0..shared_state.game_memory_block.len];
                    } else {
                        log.warn("MapViewOfFile failed!", .{});
                    }
                }
            }

            if (dib_allocated and audio_frames != null and perm_opt != null and trans_opt != null) {
                xinput.load();

                var input: [2]Input = @splat(.{});
                var new_input = &input[0];
                var old_input = &input[1];

                var last_counter = getWallClock();
                var flip_wall_clock = getWallClock();

                var debug_time_marker_index: usize = 0;
                var debug_time_markers: [DEBUG.audio_time_marker_count]DEBUG.AudioTimeMarker = @splat(.{});

                var audio_latency_bytes: win32.DWORD = 0;
                var audio_latency_seconds: f32 = 0;
                var audio_valid = false;

                _ = win32.CopyFileA(source_dll_name, temp_dll_name, .FALSE);
                var game_code = GameCode.load(io, temp_dll_name);

                var last_cycle_count = arch.rdtsc();

                while (global_running) {
                    const new_dll_write_time = common.getLastWriteTime(io, source_dll_name);
                    if (new_dll_write_time > game_code.last_write_time) {
                        var __dummy__: win32.FILE_ATTRIBUTE_DATA = undefined;

                        // This isn't required with the zig build system, but it's easy to support
                        if (win32.GetFileAttributesExA(gamecode_lock_file_name, .standard, &__dummy__).toBool()) {
                            game_code.unload();

                            _ = win32.CopyFileA(source_dll_name, temp_dll_name, .FALSE);
                            game_code = GameCode.load(io, temp_dll_name);
                        }
                    }

                    new_input.dt = target_seconds_per_frame;

                    const keyboard_controller = &new_input.controllers[0];
                    const old_keyboard_controller = &old_input.controllers[0];
                    keyboard_controller.* = std.mem.zeroes(ControllerInput);
                    for (&keyboard_controller.buttons.array, old_keyboard_controller.buttons.array) |*new_button, old_button| {
                        new_button.ended_down = old_button.ended_down;
                    }
                    keyboard_controller.is_connected = true;

                    processPendingMessages(&shared_state, keyboard_controller);

                    if (options.debug) {
                        const mouse = &new_input.debug_mouse;
                        const old_mouse = &old_input.debug_mouse;
                        mouse.* = std.mem.zeroes(common.DebugMouseInput);
                        for (&mouse.buttons.array, old_mouse.buttons.array) |*new_button, old_button| {
                            new_button.ended_down = old_button.ended_down;
                        }
                    }

                    if (!global_pause) {
                        if (options.debug) {
                            var cursor_pos: win32.POINT = undefined;
                            var cursor_pos_valid = true;

                            if (win32.GetCursorPos(&cursor_pos) == .FALSE) {
                                cursor_pos_valid = false;
                            } else {
                                if (win32.ScreenToClient(window, &cursor_pos) == .FALSE) {
                                    cursor_pos_valid = false;
                                }
                            }

                            if (!cursor_pos_valid) {
                                cursor_pos = .{ .x = 0, .y = 0 };
                            }

                            new_input.debug_mouse.x = cursor_pos.x;
                            new_input.debug_mouse.y = cursor_pos.y;
                            new_input.debug_mouse.z = 0;

                            const buttons = &new_input.debug_mouse.buttons.named;
                            processKeyboardMessage(&buttons.left, win32.GetKeyState(win32.VK_LBUTTON).down);
                            processKeyboardMessage(&buttons.right, win32.GetKeyState(win32.VK_RBUTTON).down);
                            processKeyboardMessage(&buttons.middle, win32.GetKeyState(win32.VK_MBUTTON).down);
                            processKeyboardMessage(&buttons.extra0, win32.GetKeyState(win32.VK_XBUTTON1).down);
                            processKeyboardMessage(&buttons.extra1, win32.GetKeyState(win32.VK_XBUTTON2).down);
                        }

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
                                new_controller.is_analog = old_controller.is_analog;

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

                        var game_offscreen_buffer: OffscreenBuffer = .{
                            .memory = global_back_buffer.memory_opt.?,
                            .width = @intCast(global_back_buffer.width),
                            .height = @intCast(global_back_buffer.height),
                            .pitch = global_back_buffer.pitch,
                        };

                        if (shared_state.input_recording_index > 0) {
                            recordInput(&shared_state, new_input);
                        }

                        if (shared_state.input_playing_index > 0) {
                            playbackInput(&shared_state, new_input);
                        }

                        if (game_code.updateAndRender) |updateAndRender|
                            updateAndRender(&thread_context, &game_memory, new_input, &game_offscreen_buffer);

                        const audio_wall_clock = getWallClock();
                        const from_begin_to_audio_seconds = getSecondsElapsed(flip_wall_clock, audio_wall_clock);

                        var play_cursor: win32.DWORD = 0;
                        var write_cursor: win32.DWORD = 0;
                        if (audio_output.dsound_buffer.?.GetCurrentPosition(&play_cursor, &write_cursor) == dsound.OK) {
                            if (!audio_valid) {
                                audio_output.running_frame_index = write_cursor / @sizeOf(AudioOutput.Frame);
                                audio_valid = true;
                            }

                            const byte_to_lock: u32 = (audio_output.running_frame_index *% @sizeOf(AudioOutput.Frame)) % audio_output.buffer_byte_size;

                            const seconds_left_until_flip = target_seconds_per_frame - from_begin_to_audio_seconds;
                            const expected_frames_until_flip: win32.DWORD = @intFromFloat(@max(0, seconds_left_until_flip * @as(f32, @floatFromInt(audio_output.frames_per_second))));
                            const expected_bytes_until_flip = expected_frames_until_flip * @sizeOf(AudioOutput.Frame);
                            assert(expected_bytes_until_flip % @sizeOf(AudioOutput.Frame) == 0);
                            const expected_frame_boundary_byte: win32.DWORD = play_cursor + expected_bytes_until_flip;

                            var safe_write_cursor: win32.DWORD = write_cursor;
                            if (safe_write_cursor < play_cursor) {
                                safe_write_cursor += audio_output.buffer_byte_size;
                            }
                            assert(safe_write_cursor >= play_cursor);
                            safe_write_cursor += audio_output.safety_frame_bytes;

                            const audio_card_is_low_latency = safe_write_cursor < expected_frame_boundary_byte;

                            var target_cursor: u32 = 0;
                            if (audio_card_is_low_latency) {
                                target_cursor = expected_frame_boundary_byte + audio_output.bytes_per_video_frame;
                            } else {
                                target_cursor = write_cursor + audio_output.bytes_per_video_frame + audio_output.safety_frame_bytes;
                            }
                            target_cursor = target_cursor % audio_output.buffer_byte_size;

                            const bytes_to_write: u32 =
                                if (byte_to_lock > target_cursor)
                                    (audio_output.buffer_byte_size - byte_to_lock) + target_cursor
                                else
                                    target_cursor - byte_to_lock;

                            const frames_to_write: u32 = bytes_to_write / @sizeOf(AudioOutput.Frame);

                            var game_sound_output_buffer: AudioBuffer = .{
                                .frames = audio_output.buffer[0..frames_to_write],
                                .frames_per_second = audio_fps,
                            };

                            if (game_code.getAudioFrames) |getAudioFrames| getAudioFrames(&thread_context, &game_memory, &game_sound_output_buffer);

                            fillAudioBuffer(&audio_output, byte_to_lock, bytes_to_write, &game_sound_output_buffer);

                            if (options.internal_build) {
                                const marker = &debug_time_markers[debug_time_marker_index];
                                marker.output_play_cursor = play_cursor;
                                marker.output_write_cursor = write_cursor;
                                marker.output_location = byte_to_lock;
                                marker.output_byte_count = bytes_to_write;
                                marker.expected_flip_cursor = expected_frame_boundary_byte;

                                var unwrapped_write_cursor = write_cursor;
                                if (unwrapped_write_cursor < play_cursor) {
                                    unwrapped_write_cursor += audio_output.buffer_byte_size;
                                }
                                audio_latency_bytes = unwrapped_write_cursor - play_cursor;
                                audio_latency_seconds = (@as(f32, @floatFromInt(audio_latency_bytes)) / @sizeOf(AudioBuffer.Frame)) /
                                    @as(f32, @floatFromInt(audio_output.frames_per_second));

                                // log.debug("BTL:{} TC:{} BTW:{} - PC:{} WC:{} DELTA:{} ({d:.3}) LL:{}", .{
                                //     byte_to_lock,
                                //     target_cursor,
                                //     bytes_to_write,
                                //     play_cursor,
                                //     write_cursor,
                                //     audio_latency_bytes,
                                //     audio_latency_seconds,
                                //     audio_card_is_low_latency,
                                // });
                            }
                        } else {
                            audio_valid = false;
                        }

                        const work_counter = getWallClock();
                        const work_seconds_elapsed = getSecondsElapsed(last_counter, work_counter);

                        var seconds_elapsed_for_frame = work_seconds_elapsed;
                        if (seconds_elapsed_for_frame < target_seconds_per_frame) {
                            while (seconds_elapsed_for_frame < target_seconds_per_frame) {
                                if (sleep_is_granular) {
                                    const sleep_ms: win32.DWORD = @intFromFloat(std.time.ms_per_s * (target_seconds_per_frame - seconds_elapsed_for_frame));
                                    if (sleep_ms > 0) {
                                        win32.Sleep(sleep_ms);
                                    }
                                }
                                seconds_elapsed_for_frame = getSecondsElapsed(last_counter, getWallClock());
                            }
                        } else {
                            log.warn("Missed frame time! ({})", .{seconds_elapsed_for_frame * std.time.ms_per_s});
                        }

                        const end_counter = getWallClock();
                        const ms_per_frame = std.time.ms_per_s * getSecondsElapsed(last_counter, end_counter);
                        last_counter = end_counter;

                        const dimension = getWindowDimension(window);
                        const device_context = win32.GetDC(window);
                        displayBufferInWindow(device_context, dimension.width, dimension.height, &global_back_buffer);
                        _ = win32.ReleaseDC(window, device_context);

                        flip_wall_clock = getWallClock();

                        if (options.internal_build) {
                            var debug_play_cursor: win32.DWORD = 0;
                            var debug_write_cursor: win32.DWORD = 0;
                            if (audio_output.dsound_buffer.?.GetCurrentPosition(&debug_play_cursor, &debug_write_cursor) == dsound.OK) {
                                const marker = &debug_time_markers[debug_time_marker_index];

                                marker.flip_play_cursor = debug_play_cursor;
                                marker.flip_write_cursor = debug_write_cursor;
                            }
                        }

                        const tmp = new_input;
                        new_input = old_input;
                        old_input = tmp;

                        const end_cycle_count = arch.rdtsc();
                        const cycles_elapsed: f32 = @floatFromInt(end_cycle_count - last_cycle_count);
                        last_cycle_count = end_cycle_count;

                        const fps = std.time.ms_per_s / ms_per_frame;
                        const mcps = cycles_elapsed / (1000 * 1000);
                        // log.debug("{d:.2}ms/f,  {d:.2}f/s,  {d:.2}mc/f,  {d:.2}wms", .{ ms_per_frame, fps, mcps, work_seconds_elapsed * std.time.ms_per_s });
                        _ = .{ fps, mcps };

                        if (options.internal_build) {
                            debug_time_marker_index += 1;
                            if (debug_time_marker_index >= debug_time_markers.len) {
                                debug_time_marker_index = 0;
                            }
                        }
                    }
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

pub fn mainWindowCallback(window: win32.HWND, message: c_uint, wparam: win32.WPARAM, lparam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    var result: win32.LRESULT = 0;

    switch (message) {
        win32.WM_CLOSE, win32.WM_DESTROY => {
            global_running = false;
        },
        win32.WM_ACTIVATEAPP => {
            // if (wparam != 0) {
            //     _ = win32.SetLayeredWindowAttributes(window, win32.RGB(0, 0, 0), 255, win32.LWA_ALPHA);
            // } else {
            //     _ = win32.SetLayeredWindowAttributes(window, win32.RGB(0, 0, 0), 128, win32.LWA_ALPHA);
            // }
        },

        win32.WM_SETCURSOR => {
            if (global_DEBUG_show_cursor or !(win32.LOWORD(lparam) == win32.HTCLIENT)) {
                // Set the wanted cursor in window class
                result = win32.DefWindowProcA(window, message, wparam, lparam);
            } else {
                _ = win32.SetCursor(null);
                result = @intFromEnum(win32.TRUE);
            }
        },

        win32.WM_SYSKEYDOWN,
        win32.WM_SYSKEYUP,
        win32.WM_KEYDOWN,
        win32.WM_KEYUP,
        => {
            @panic("Unexpected WM_KEY* message"); // Assume keys are dispatched/handled in the main loop
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

fn resizeDibSection(buffer: *Win32OffscreenBuffer, width: c_int, height: c_int) bool {
    if (buffer.memory_opt) |m| {
        _ = win32.VirtualFree(m, 0, win32.MEM_RELEASE);
    }

    const bytes_per_pixel = 4;
    buffer.width = @intCast(width);
    buffer.height = @intCast(height);
    buffer.pitch = buffer.width * bytes_per_pixel;
    buffer.bytes_per_pixel = bytes_per_pixel;

    buffer.info = win32.BITMAPINFO{ .bmiHeader = .{
        .biWidth = @intCast(buffer.width),
        .biHeight = -@as(win32.LONG, @intCast(buffer.height)),
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
    buffer.memory_opt = @as([*]u8, @ptrCast(memory));
    return memory != null;
}

fn displayBufferInWindow(dc: win32.HDC, window_width: i32, window_height: i32, buffer: *Win32OffscreenBuffer) void {

    // // When stretching, and the windows is smaller than the buffer, this avoids artifacts
    // // TODO: Only set this after resize?
    // if (window_width < buffer.width or window_height < buffer.height) {
    //     _ = win32.SetStretchBltMode(dc, win32.STRETCH_DELETESCANS);
    // } else {
    //     _ = win32.SetStretchBltMode(dc, 0);
    // }

    const buffer_width: c_int = @intCast(buffer.width);
    const buffer_height: c_int = @intCast(buffer.height);

    const buffer_mem = buffer.memory_opt.?;

    if (window_width >= buffer_width * 2 and window_height >= buffer_height * 2) {
        _ = win32.PatBlt(dc, 2 * buffer_width, 0, window_width - (2 * buffer_width), window_height, win32.BLACKNESS);
        _ = win32.PatBlt(dc, 0, 2 * buffer_height, 2 * buffer_width, window_height - (2 * buffer_height), win32.BLACKNESS);
        win32.StretchDIBits(dc, 0, 0, 2 * buffer_width, 2 * buffer_height, 0, 0, buffer_width, buffer_height, buffer_mem, &buffer.info, win32.DIB_RGB_COLORS, win32.SRCCOPY);
    } else {

        // TODO: Offset mouse position by this
        const offset_x = 10;
        const offset_y = 10;

        _ = win32.PatBlt(dc, 0, 0, window_width, offset_y, win32.BLACKNESS);
        _ = win32.PatBlt(dc, 0, offset_y + buffer_height, window_width, window_height - (offset_y + buffer_height), win32.BLACKNESS);
        _ = win32.PatBlt(dc, 0, 0, offset_x, window_height, win32.BLACKNESS);
        _ = win32.PatBlt(dc, offset_x + buffer_width, 0, window_width - (offset_x + buffer_width), window_height, win32.BLACKNESS);

        win32.StretchDIBits(dc, offset_x, offset_y, buffer_width, buffer_height, 0, 0, buffer_width, buffer_height, buffer_mem, &buffer.info, win32.DIB_RGB_COLORS, win32.SRCCOPY);
    }
}

pub fn beginRecordingInput(shared_state: *common.SharedState, input_recording_index: usize) void {
    const replay_buffer = shared_state.getReplayBuffer(input_recording_index);

    if (replay_buffer.memory.len == shared_state.game_memory_block.len) {
        shared_state.input_recording_index = input_recording_index;

        var file_name_buf: [std.Io.Dir.max_name_bytes]u8 = undefined;
        const file_name = shared_state.getInputRecordingPath(&file_name_buf, true, input_recording_index);

        const handle = win32.CreateFileA(file_name, win32.GENERIC_WRITE, 0, null, win32.CREATE_ALWAYS, 0, null);
        shared_state.recording_handle = .{ .handle = handle, .flags = .{ .nonblocking = false } };

        @memcpy(replay_buffer.memory, shared_state.game_memory_block);
    }
}

pub fn endRecordingInput(shared_state: *common.SharedState) void {
    _ = win32.CloseHandle(shared_state.recording_handle.handle);
    shared_state.input_recording_index = 0;
}

pub fn beginInputPlayback(shared_state: *common.SharedState, input_playing_index: usize) void {
    const replay_buffer = shared_state.getReplayBuffer(input_playing_index);

    if (replay_buffer.memory.len == shared_state.game_memory_block.len) {
        shared_state.input_playing_index = input_playing_index;

        var file_name_buf: [std.Io.Dir.max_name_bytes]u8 = undefined;
        const file_name = shared_state.getInputRecordingPath(&file_name_buf, true, input_playing_index);

        const handle = win32.CreateFileA(file_name, win32.GENERIC_READ, 0, null, win32.OPEN_EXISTING, 0, null);
        shared_state.playback_handle = .{ .handle = handle, .flags = .{ .nonblocking = false } };

        @memcpy(shared_state.game_memory_block, replay_buffer.memory);
    }
}

pub fn endInputPlayback(shared_state: *common.SharedState) void {
    _ = win32.CloseHandle(shared_state.playback_handle.handle);
    shared_state.input_playing_index = 0;
}

pub fn recordInput(shared_state: *common.SharedState, input: *Input) void {
    var written: win32.DWORD = undefined;
    _ = win32.WriteFile(shared_state.recording_handle.handle, input, @sizeOf(Input), &written, null);
    assert(written == @sizeOf(Input));
}

pub fn playbackInput(shared_state: *common.SharedState, input: *Input) void {
    var read: win32.DWORD = 0;
    if (win32.ReadFile(shared_state.playback_handle.handle, input, @sizeOf(Input), &read, null) != .FALSE) {
        if (read == 0) {
            const playing_index = shared_state.input_playing_index;
            endInputPlayback(shared_state);
            beginInputPlayback(shared_state, playing_index);
            _ = win32.ReadFile(shared_state.playback_handle.handle, input, @sizeOf(Input), &read, null);
            assert(read == @sizeOf(Input));
        }
    }
}

pub fn toggleFullscreen(window: win32.HWND) void {
    const style = win32.GetWindowLongA(window, win32.GWL_STYLE);
    if (style & win32.WS_OVERLAPPEDWINDOW == win32.WS_OVERLAPPEDWINDOW) {
        var mi: win32.MONITORINFO = .{};
        if (win32.GetWindowPlacement(window, &global_window_position) != .FALSE and
            win32.GetMonitorInfoA(win32.MonitorFromWindow(window, win32.MONITOR_DEFAULTTOPRIMARY), &mi) != .FALSE)
        {
            _ = win32.SetWindowLongA(window, win32.GWL_STYLE, style & @as(win32.LONG, @bitCast(~win32.WS_OVERLAPPEDWINDOW)));
            _ = win32.SetWindowPos(window, win32.HWND_TOP, mi.monitor.left, mi.monitor.top, mi.monitor.right - mi.monitor.left, mi.monitor.bottom - mi.monitor.top, win32.SWP_NOOWNERZORDER | win32.SWP_FRAMECHANGED);
        }
    } else {
        _ = win32.SetWindowLongA(window, win32.GWL_STYLE, style | win32.WS_OVERLAPPEDWINDOW);
        _ = win32.SetWindowPlacement(window, &global_window_position);
        _ = win32.SetWindowPos(window, null, 0, 0, 0, 0, win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOZORDER | win32.SWP_NOOWNERZORDER | win32.SWP_FRAMECHANGED);
    }
}

pub const DEBUG = struct {
    pub fn readEntireFile(thread_context: *ThreadContext, path: [:0]const u8) common.DEBUG.ReadFileResult {
        var result: []u8 = &.{};

        const handle = win32.CreateFileA(path, win32.GENERIC_READ, win32.FILE_SHARE_READ, null, win32.OPEN_EXISTING, 0, null);

        if (handle != win32.INVALID_HANDLE_VALUE) {
            var file_size: win32.LARGE_INTEGER = undefined;
            if (win32.GetFileSizeEx(handle, &file_size) != .FALSE) {
                if (win32.VirtualAlloc(null, file_size.quad_part, win32.MEM_RESERVE | win32.MEM_COMMIT, win32.PAGE_READWRITE)) |alloc_res| {
                    const file_size_32 = safeTruncateU64(file_size.quad_part);

                    var bytes_read: win32.DWORD = undefined;
                    if (win32.ReadFile(handle, alloc_res, file_size_32, &bytes_read, null) != .FALSE and
                        file_size_32 == bytes_read)
                    {
                        result = alloc_res[0..file_size_32];
                    } else {
                        freeFileMemory(thread_context, alloc_res[0..file_size_32]);
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

    pub fn writeEntireFile(thread_context: *ThreadContext, path: [:0]const u8, memory: []const u8) bool {
        _ = thread_context;

        var result = false;

        const handle = win32.CreateFileA(path, win32.GENERIC_WRITE, 0, null, win32.CREATE_ALWAYS, 0, null);

        if (handle != win32.INVALID_HANDLE_VALUE) {
            var written: win32.DWORD = undefined;

            const memory_size_32 = safeTruncateU64(memory.len);

            if (win32.WriteFile(handle, memory.ptr, memory_size_32, &written, null) != .FALSE) {
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

    pub fn freeFileMemory(thread_context: *ThreadContext, memory: []const u8) void {
        _ = thread_context;

        if (memory.len > 0) {
            _ = win32.VirtualFree(memory.ptr, 0, win32.MEM_DECOMMIT);
        }
    }

    pub fn drawVertical(buffer: *Win32OffscreenBuffer, x: i32, c_top: i32, c_bottom: i32, color: u32) void {
        const top = if (c_top <= 0) 0 else c_top;
        const bottom = if (c_bottom > buffer.height) buffer.height else @as(u32, @intCast(c_bottom));

        if (x >= 0 and x < buffer.width) {
            var cursor: [*]u8 = buffer.memory.ptr +
                @as(usize, @intCast((x * @as(i32, @intCast(buffer.bytes_per_pixel))) +
                    (top * @as(i32, @intCast(buffer.pitch)))));

            for (@intCast(top)..@intCast(bottom + 1)) |_| {
                const pixel: *u32 = @ptrCast(@alignCast(cursor));
                pixel.* = color;
                cursor += @intCast(buffer.pitch);
            }
        }
    }

    pub fn drawAudioBufferMarker(buffer: *Win32OffscreenBuffer, audio_output: *AudioOutput, c: f32, pad_x: i32, top: i32, bottom: i32, value: win32.DWORD, color: u32) void {
        _ = audio_output;
        const real_x: f32 = c * @as(f32, @floatFromInt(value));
        const x = pad_x + @as(i32, @intFromFloat(real_x));

        drawVertical(buffer, x, top, bottom, color);
    }

    // pub fn audioSyncDisplay(buffer: *OffscreenBuffer, markers: [*]AudioTimeMarker, markers_len: usize, current_marker: isize, audio_output: *AudioOutput, seconds_per_frame: f32) callconv(.c) void {
    //     _ = seconds_per_frame;
    //
    //     const pad_x = 16;
    //     const pad_y = 16;
    //
    //     const line_height = 64;
    //
    //     const c = @as(f32, @floatFromInt(buffer.width - (2 * pad_x))) / @as(f32, @floatFromInt(audio_output.buffer_byte_size));
    //
    //     for (markers[0..markers_len], 0..) |marker, marker_index| {
    //         const play_color = 0xffffffff;
    //         const write_color = 0xffff0000;
    //         const expected_flip_color = 0xffffff00;
    //         const play_window_color = 0xffff00ff;
    //
    //         var top: i32 = pad_y;
    //         var bottom: i32 = pad_y + line_height;
    //
    //         if (marker_index == current_marker) {
    //             top += line_height + pad_y;
    //             bottom += line_height + pad_y;
    //
    //             drawAudioBufferMarker(buffer, audio_output, c, pad_x, top, bottom, marker.output_play_cursor, play_color);
    //             drawAudioBufferMarker(buffer, audio_output, c, pad_x, top, bottom, marker.output_write_cursor, write_color);
    //
    //             top += line_height + pad_y;
    //             bottom += line_height + pad_y;
    //
    //             drawAudioBufferMarker(buffer, audio_output, c, pad_x, top, bottom, marker.output_location, play_color);
    //             drawAudioBufferMarker(buffer, audio_output, c, pad_x, top, bottom, marker.output_location + marker.output_byte_count, write_color);
    //
    //             top += line_height + pad_y;
    //             bottom += line_height + pad_y;
    //
    //             drawAudioBufferMarker(buffer, audio_output, c, pad_x, pad_x, bottom, marker.expected_flip_cursor, expected_flip_color);
    //         }
    //
    //         drawAudioBufferMarker(buffer, audio_output, c, pad_x, top, bottom, marker.flip_play_cursor, play_color);
    //         drawAudioBufferMarker(buffer, audio_output, c, pad_x, top, bottom, marker.flip_play_cursor + (480 * @sizeOf(AudioOutput.Frame)), play_window_color);
    //         drawAudioBufferMarker(buffer, audio_output, c, pad_x, top, bottom, marker.flip_write_cursor, write_color);
    //     }
    // }

    pub const audio_time_marker_count = 25;

    pub const AudioTimeMarker = struct {
        output_play_cursor: win32.DWORD = 0,
        output_write_cursor: win32.DWORD = 0,
        output_location: win32.DWORD = 0,
        output_byte_count: win32.DWORD = 0,
        expected_flip_cursor: win32.DWORD = 0,

        flip_play_cursor: win32.DWORD = 0,
        flip_write_cursor: win32.DWORD = 0,
    };
};

inline fn safeTruncateU64(value: u64) u32 {
    assert(value <= math.maxInt(u32));
    return @intCast(value);
}
