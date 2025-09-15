const std = @import("std");
const log = std.log.scoped(.win32_v10);
const win32 = @import("win32.zig");

const assert = std.debug.assert;

var running = false;
var bitmap_info = win32.BITMAPINFO{};
var bitmap_memory: []u8 = &.{};
var bitmap_width: c_int = undefined;
var bitmap_height: c_int = undefined;
const bytes_per_pixel: usize = 4;

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

        if (window_handle_opt) |window_handle| {
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

                renderWeirdGradient(x_offset, y_offset);
                x_offset += 1;

                const device_context = win32.GetDC(window_handle);
                var client_rect: win32.RECT = undefined;
                _ = win32.GetClientRect(window_handle, &client_rect);
                win32UpdateWindow(device_context, &client_rect, 0, 0, bitmap_width, bitmap_height);
                _ = win32.ReleaseDC(window_handle, device_context);
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

                var client_rect: win32.RECT = undefined;
                _ = win32.GetClientRect(window, &client_rect);
                win32UpdateWindow(dc, &client_rect, x, y, w, h);
            }
            _ = win32.EndPaint(window, &paint);
        },

        else => {
            result = win32.DefWindowProcA(window, message, wparam, lparam);
        },
    }

    return result;
}

fn win32ResizeDibSection(width: c_int, height: c_int) void {
    if (bitmap_memory.len > 0) {
        _ = win32.VirtualFree(bitmap_memory.ptr, 0, win32.MEM_RELEASE);
    }

    bitmap_width = width;
    bitmap_height = height;

    bitmap_info = win32.BITMAPINFO{ .bmiHeader = .{
        .biWidth = bitmap_width,
        .biHeight = -bitmap_height,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = win32.BI_RGB,
    } };

    const uwidth: usize = @intCast(bitmap_width);
    const uheight: usize = @intCast(bitmap_height);

    const bitmap_memory_size: usize = uwidth * uheight * bytes_per_pixel;
    bitmap_memory = @as([*]u8, @ptrCast(win32.VirtualAlloc(
        null,
        bitmap_memory_size,
        win32.MEM_COMMIT,
        win32.PAGE_READWRITE,
    )))[0..bitmap_memory_size];
}

fn win32UpdateWindow(dc: win32.HDC, client_rect: *win32.RECT, x: c_int, y: c_int, width: c_int, height: c_int) void {
    _ = x;
    _ = y;
    _ = width;
    _ = height;

    const window_width = client_rect.right - client_rect.left;
    const window_height = client_rect.bottom - client_rect.top;
    win32.StretchDIBits(dc, 0, 0, bitmap_width, bitmap_height, 0, 0, window_width, window_height, bitmap_memory.ptr, &bitmap_info, win32.DIB_RGB_COLORS, win32.SRCCOPY);
}

fn renderWeirdGradient(xoffset: i32, yoffset: i32) void {
    const uwidth: usize = @intCast(bitmap_width);
    const uheight: usize = @intCast(bitmap_height);

    const pitch = uwidth * bytes_per_pixel;
    var row: [*]u8 = bitmap_memory.ptr;
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
        row += pitch;
    }
}
