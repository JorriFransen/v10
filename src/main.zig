const std = @import("std");
const log = std.log.scoped(.main);
const win32 = @import("win32.zig");

const assert = std.debug.assert;

var running = false;
var bitmap_info = win32.BITMAPINFO{};
var bitmap_memory: *anyopaque = undefined;
var bitmap_handle: ?win32.HBITMAP = null;
var bitmap_device_context: ?win32.HDC = null;

pub fn main() u8 {
    log.debug("entry", .{});
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

    const window_class = win32.WNDCLASSA{
        .style = win32.CS_OWNDC | win32.CS_HREDRAW | win32.CS_VREDRAW,
        .lpfnWndProc = windowProcA,
        .hInstance = instance,
        .lpszClassName = "v10_window_class",
    };

    if (win32.RegisterClassA(&window_class) != 0) {
        const window_handle_opt = win32.CreateWindowExA(
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

        if (window_handle_opt) |_| {
            running = true;
            while (running) {
                var msg = win32.MSG{};
                if (win32.GetMessageA(&msg, null, 0, 0) > 0) {
                    _ = win32.TranslateMessage(&msg);
                    _ = win32.DispatchMessageA(&msg);
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
        win32.WM_SIZE => {
            var client_rect: win32.RECT = undefined;
            _ = win32.GetClientRect(window, &client_rect);
            const width = client_rect.right - client_rect.left;
            const height = client_rect.bottom - client_rect.top;
            win32ResizeDibSection(width, height);
        },
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
                win32UpdateWindow(dc, x, y, w, h);
            }
            _ = win32.EndPaint(window, &paint);
        },

        else => {
            // log.debug("Unhandled window message: {}", .{message});
            result = win32.DefWindowProcA(window, message, wparam, lparam);
        },
    }

    return result;
}

fn win32ResizeDibSection(width: c_int, height: c_int) void {
    if (bitmap_handle) |handle| {
        _ = win32.DeleteObject(handle);
    }

    if (bitmap_device_context == null) {
        bitmap_device_context = win32.CreateCompatibleDC(null);
    }

    bitmap_info = win32.BITMAPINFO{ .bmiHeader = .{
        .biWidth = width,
        .biHeight = height,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = win32.BI_RGB,
    } };

    bitmap_handle = win32.CreateDIBSection(bitmap_device_context, &bitmap_info, win32.DIB_RGB_COLORS, &bitmap_memory, null, 0);
}

fn win32UpdateWindow(dc: win32.HDC, x: c_int, y: c_int, width: c_int, height: c_int) void {
    win32.StretchDIBits(dc, x, y, width, height, x, y, width, height, bitmap_memory, &bitmap_info, win32.DIB_RGB_COLORS, win32.SRCCOPY);
}
