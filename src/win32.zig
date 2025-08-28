const std = @import("std");
const zig_win32 = std.os.windows;

pub const HINSTANCE = zig_win32.HINSTANCE;
pub const PWSTR = zig_win32.PWSTR;
pub const LPCSTR = zig_win32.LPCSTR;

pub const MB_OK: c_uint = 0x0;
pub const MB_OKCANCEL: c_uint = 0x1;
pub const MB_ABORTRETRYIGNORE: c_uint = 0x2;
pub const MB_YESNOCANCEL: c_uint = 0x3;
pub const MB_YESNO: c_uint = 0x4;
pub const MB_RETRYCANCEL: c_uint = 0x5;
pub const MB_CANCELTRYCONTINUE: c_uint = 0x6;
pub const MB_HELP: c_uint = 0x4000;

pub const MB_ICONEXCLAMATION: c_uint = 0x30;
pub const MB_ICONWARNING: c_uint = 0x30;
pub const MB_ICONINFORMATION: c_uint = 0x40;
pub const MB_ICONASTERISK: c_uint = 0x40;
pub const MB_ICONQUESTION: c_uint = 0x20;
pub const MB_ICONSTOP: c_uint = 0x10;
pub const MB_ICONERROR: c_uint = 0x10;
pub const MB_ICONHAND: c_uint = 0x10;

pub const MB_DEFBUTTON1: c_uint = 0x0;
pub const MB_DEFBUTTON2: c_uint = 0x100;
pub const MB_DEFBUTTON3: c_uint = 0x200;
pub const MB_DEFBUTTON4: c_uint = 0x300;

pub const MB_APPLMODAL: c_uint = 0x0;
pub const MB_SYSTEMMODAL: c_uint = 0x1000;
pub const MB_TASKMODAL: c_uint = 0x2000;

pub const MB_DEFAULT_DESKTOP_ONLY: c_uint = 0x20000;
pub const MB_RIGHT: c_uint = 0x80000;
pub const MB_RTLREADING: c_uint = 0x100000;
pub const MB_SETFOREGROUND: c_uint = 0x10000;
pub const MB_TOPMOST: c_uint = 0x40000;
pub const MB_SERVICE_NOTIFICATION: c_uint = 0x200000;

pub const IDABORT: c_int = 3;
pub const IDCANCEL: c_int = 2;
pub const IDCONTINUE: c_int = 11;
pub const IDIGNORE: c_int = 5;
pub const IDNO: c_int = 7;
pub const IDOK: c_int = 1;
pub const IDRETRY: c_int = 4;
pub const IDTRYAGAIN: c_int = 10;
pub const IDYES: c_int = 6;

pub extern "user32" fn MessageBoxA(hwnd: ?HINSTANCE, text: LPCSTR, caption: LPCSTR, type: c_uint) callconv(.c) c_int;
