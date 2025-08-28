const std = @import("std");
const log = std.log.scoped(.main);
const win32 = @import("win32.zig");

const assert = std.debug.assert;

const c = @cImport(@cInclude("windows.h"));

pub fn main() u8 {
    const instance: win32.HINSTANCE = @ptrCast(win32.GetModuleHandleA(null));
    const command_line = win32.GetCommandLineA();

    var startup_info: c.STARTUPINFOA = undefined;
    c.GetStartupInfoA(&startup_info);

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

    log.debug("Hello Windows!", .{});

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
            var msg: win32.MSG = undefined;
            while (win32.GetMessageA(&msg, null, 0, 0) > 0) {
                _ = win32.TranslateMessage(&msg);
                _ = win32.DispatchMessageA(&msg);
            }
        } else {
            log.err("CreateWindow failed!", .{});
        }
    } else {
        log.err("RegisterClass failed!", .{});
    }

    return 0;
}

var blt_op = win32.WHITENESS;

pub fn windowProcA(window: win32.HWND, message: c_uint, wparam: win32.WPARAM, lparam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    var result: win32.LRESULT = 0;

    switch (message) {
        win32.WM_SIZE => {
            log.debug("WM_SIZE", .{});
        },
        win32.WM_DESTROY => {
            log.debug("WM_DESTROY", .{});
        },
        win32.WM_CLOSE => {
            log.debug("WM_CLOSE", .{});
        },
        win32.WM_QUIT => {
            log.debug("WM_QUIT", .{});
        },
        win32.WM_ACTIVATEAPP => {
            log.debug("WM_ACTIVATEAPP", .{});
        },

        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            const dc = win32.BeginPaint(window, &paint);
            {
                const w = paint.rcPaint.right - paint.rcPaint.left;
                const h = paint.rcPaint.bottom - paint.rcPaint.top;
                _ = win32.PatBlt(dc, paint.rcPaint.left, paint.rcPaint.top, w, h, blt_op);
                blt_op = if (blt_op == win32.WHITENESS) win32.BLACKNESS else win32.WHITENESS;
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
