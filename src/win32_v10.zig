const std = @import("std");
const log = std.log.scoped(.win32_v10);
const win32 = @import("win32.zig");

const assert = std.debug.assert;

var running = false;
var global_back_buffer: OffscreenBuffer = undefined;

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
            running = true;
            var x_offset: i32 = 0;
            const y_offset = 0;
            while (running) {
                var msg = win32.MSG{};
                while (win32.PeekMessageA(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
                    if (msg.message == win32.WM_QUIT) {
                        running = false;
                    }
                    _ = win32.TranslateMessage(&msg);
                    _ = win32.DispatchMessageA(&msg);
                }

                renderWeirdGradient(global_back_buffer, x_offset, y_offset);
                x_offset += 1;

                const device_context = win32.GetDC(window);
                const dimension = getWindowDimension(window);
                win32DisplayBufferInWindow(
                    device_context,
                    dimension.width,
                    dimension.height,
                    global_back_buffer,
                    0,
                    0,
                    global_back_buffer.width,
                    global_back_buffer.height,
                );
                _ = win32.ReleaseDC(window, device_context);
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
            running = false;
        },
        win32.WM_ACTIVATEAPP => {
            log.debug("WM_ACTIVATEAPP", .{});
        },

        win32.WM_KEYDOWN => {
            if (wparam == win32.VK_ESCAPE) {
                running = false;
            }
        },

        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            const dc = win32.BeginPaint(window, &paint);
            {
                const x = paint.rcPaint.left;
                const y = paint.rcPaint.top;
                const w = paint.rcPaint.right - paint.rcPaint.left;
                const h = paint.rcPaint.bottom - paint.rcPaint.top;

                const dimension = getWindowDimension(window);
                win32DisplayBufferInWindow(dc, dimension.width, dimension.height, global_back_buffer, x, y, w, h);
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

    buffer.bytes_per_pixel = 4;
    buffer.width = width;
    buffer.height = height;
    buffer.pitch = buffer.width * buffer.bytes_per_pixel;

    buffer.info = win32.BITMAPINFO{ .bmiHeader = .{
        .biWidth = buffer.width,
        .biHeight = -buffer.height,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = win32.BI_RGB,
    } };

    const bitmap_memory_size: usize = @intCast(width * height * buffer.bytes_per_pixel);
    buffer.memory = @as([*]u8, @ptrCast(win32.VirtualAlloc(
        null,
        bitmap_memory_size,
        win32.MEM_COMMIT,
        win32.PAGE_READWRITE,
    )))[0..bitmap_memory_size];
}

fn win32DisplayBufferInWindow(dc: win32.HDC, window_width: i32, window_height: i32, buffer: OffscreenBuffer, x: i32, y: i32, width: i32, height: i32) void {
    _ = x;
    _ = y;
    _ = width;
    _ = height;

    win32.StretchDIBits(dc, 0, 0, window_width, window_height, 0, 0, buffer.width, buffer.height, buffer.memory.ptr, &buffer.info, win32.DIB_RGB_COLORS, win32.SRCCOPY);
}

fn renderWeirdGradient(buffer: OffscreenBuffer, xoffset: i32, yoffset: i32) void {
    const uwidth: usize = @intCast(buffer.width);
    const uheight: usize = @intCast(buffer.height);

    var row: [*]u8 = buffer.memory.ptr;
    for (0..uheight) |uy| {
        const y: i32 = @intCast(uy);
        var pixel: [*]u32 = @ptrCast(@alignCast(row));
        for (0..uwidth) |ux| {
            const x: i32 = @intCast(ux);

            const b: u8 = @truncate(@as(usize, @intCast(x + xoffset)));
            const g: u8 = @truncate(@as(usize, @intCast(y + yoffset)));
            pixel[0] = (@as(u16, g) << 8) | b;
            pixel += 1;
        }
        row += @intCast(buffer.pitch);
    }
}
