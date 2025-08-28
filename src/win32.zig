const std = @import("std");
const c_translation = std.zig.c_translation;
const zig_win32 = std.os.windows;

pub const HINSTANCE = zig_win32.HINSTANCE;
pub const HMODULE = zig_win32.HMODULE;
pub const HANDLE = zig_win32.HANDLE;
pub const HDC = zig_win32.HDC;
pub const PWSTR = zig_win32.PWSTR;
pub const LPBYTE = zig_win32.LPBYTE;
pub const LPSTR = zig_win32.LPSTR;
pub const LPCSTR = zig_win32.LPCSTR;
pub const LPWSTR = zig_win32.LPWSTR;
pub const LPCWSTR = zig_win32.LPCWSTR;
pub const LPMSG = *MSG;
pub const HICON = zig_win32.HICON;
pub const HCURSOR = zig_win32.HCURSOR;
pub const HBRUSH = zig_win32.HBRUSH;
pub const HWND = zig_win32.HWND;
pub const HMENU = zig_win32.HMENU;
pub const WPARAM = zig_win32.WPARAM;
pub const LPARAM = zig_win32.LPARAM;
pub const LRESULT = zig_win32.LRESULT;
pub const ATOM = zig_win32.ATOM;
pub const BOOL = zig_win32.BOOL;
pub const BYTE = zig_win32.BYTE;
pub const WORD = zig_win32.WORD;
pub const DWORD = zig_win32.DWORD;
pub const LPVOID = zig_win32.LPVOID;
pub const POINT = zig_win32.POINT;
pub const RECT = zig_win32.RECT;

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

pub const CS_BYTEALIGNCLIENT: c_uint = 0x1000;
pub const CS_BYTEALIGNWINDOW: c_uint = 0x2000;
pub const CS_CLASSDC: c_uint = 0x0040;
pub const CS_DBLCLKS: c_uint = 0x0008;
pub const CS_DROPSHADOW: c_uint = 0x00020000;
pub const CS_GLOBALCLASS: c_uint = 0x4000;
pub const CS_HREDRAW: c_uint = 0x0002;
pub const CS_NOCLOSE: c_uint = 0x0200;
pub const CS_OWNDC: c_uint = 0x0020;
pub const CS_PARENTDC: c_uint = 0x0080;
pub const CS_SAVEBITS: c_uint = 0x0800;
pub const CS_VREDRAW: c_uint = 0x0001;

pub const WM_NULL: c_uint = 0x0000;
pub const WM_CREATE: c_uint = 0x0001;
pub const WM_DESTROY: c_uint = 0x0002;
pub const WM_MOVE: c_uint = 0x0003;
pub const WM_SIZE: c_uint = 0x0005;
pub const WM_ACTIVATE: c_uint = 0x0006;
pub const WM_SETFOCUS: c_uint = 0x0007;
pub const WM_KILLFOCUS: c_uint = 0x0008;
pub const WM_ENABLE: c_uint = 0x000A;
pub const WM_SETREDRAW: c_uint = 0x000B;
pub const WM_SETTEXT: c_uint = 0x000C;
pub const WM_GETTEXT: c_uint = 0x000D;
pub const WM_GETTEXTLENGTH: c_uint = 0x000E;
pub const WM_PAINT: c_uint = 0x000F;
pub const WM_CLOSE: c_uint = 0x0010;
pub const WM_QUERYENDSESSION: c_uint = 0x0011;
pub const WM_QUERYOPEN: c_uint = 0x0013;
pub const WM_ENDSESSION: c_uint = 0x0016;
pub const WM_QUIT: c_uint = 0x0012;
pub const WM_ERASEBKGND: c_uint = 0x0014;
pub const WM_SYSCOLORCHANGE: c_uint = 0x0015;
pub const WM_SHOWWINDOW: c_uint = 0x0018;
pub const WM_WININICHANGE: c_uint = 0x001A;
pub const WM_SETTINGCHANGE: c_uint = 0x001A;
pub const WM_DEVMODECHANGE: c_uint = 0x001B;
pub const WM_ACTIVATEAPP: c_uint = 0x001C;
pub const WM_FONTCHANGE: c_uint = 0x001D;
pub const WM_TIMECHANGE: c_uint = 0x001E;
pub const WM_CANCELMODE: c_uint = 0x001F;
pub const WM_SETCURSOR: c_uint = 0x0020;
pub const WM_MOUSEACTIVATE: c_uint = 0x0021;
pub const WM_CHILDACTIVATE: c_uint = 0x0022;
pub const WM_QUEUESYNC: c_uint = 0x0023;
pub const WM_GETMINMAXINFO: c_uint = 0x0024;
pub const WM_PAINTICON: c_uint = 0x0026;
pub const WM_ICONERASEBKGND: c_uint = 0x0027;
pub const WM_NEXTDLGCTL: c_uint = 0x0028;
pub const WM_SPOOLERSTATUS: c_uint = 0x002A;
pub const WM_DRAWITEM: c_uint = 0x002B;
pub const WM_MEASUREITEM: c_uint = 0x002C;
pub const WM_DELETEITEM: c_uint = 0x002D;
pub const WM_VKEYTOITEM: c_uint = 0x002E;
pub const WM_CHARTOITEM: c_uint = 0x002F;
pub const WM_SETFONT: c_uint = 0x0030;
pub const WM_GETFONT: c_uint = 0x0031;
pub const WM_SETHOTKEY: c_uint = 0x0032;
pub const WM_GETHOTKEY: c_uint = 0x0033;
pub const WM_QUERYDRAGICON: c_uint = 0x0037;
pub const WM_COMPAREITEM: c_uint = 0x0039;
pub const WM_GETOBJECT: c_uint = 0x003D;
pub const WM_COMPACTING: c_uint = 0x0041;
pub const WM_COMMNOTIFY: c_uint = 0x0044;
pub const WM_WINDOWPOSCHANGING: c_uint = 0x0046;
pub const WM_WINDOWPOSCHANGED: c_uint = 0x0047;
pub const WM_POWER: c_uint = 0x0048;
pub const WM_COPYDATA: c_uint = 0x004A;
pub const WM_CANCELJOURNAL: c_uint = 0x004B;
pub const WM_NOTIFY: c_uint = 0x004E;
pub const WM_INPUTLANGCHANGEREQUEST: c_uint = 0x0050;
pub const WM_INPUTLANGCHANGE: c_uint = 0x0051;
pub const WM_TCARD: c_uint = 0x0052;
pub const WM_HELP: c_uint = 0x0053;
pub const WM_USERCHANGED: c_uint = 0x0054;
pub const WM_NOTIFYFORMAT: c_uint = 0x0055;
pub const WM_CONTEXTMENU: c_uint = 0x007B;
pub const WM_STYLECHANGING: c_uint = 0x007C;
pub const WM_STYLECHANGED: c_uint = 0x007D;
pub const WM_DISPLAYCHANGE: c_uint = 0x007E;
pub const WM_GETICON: c_uint = 0x007F;
pub const WM_SETICON: c_uint = 0x0080;
pub const WM_NCCREATE: c_uint = 0x0081;
pub const WM_NCDESTROY: c_uint = 0x0082;
pub const WM_NCCALCSIZE: c_uint = 0x0083;
pub const WM_NCHITTEST: c_uint = 0x0084;
pub const WM_NCPAINT: c_uint = 0x0085;
pub const WM_NCACTIVATE: c_uint = 0x0086;
pub const WM_GETDLGCODE: c_uint = 0x0087;
pub const WM_SYNCPAINT: c_uint = 0x0088;
pub const WM_NCMOUSEMOVE: c_uint = 0x00A0;
pub const WM_NCLBUTTONDOWN: c_uint = 0x00A1;
pub const WM_NCLBUTTONUP: c_uint = 0x00A2;
pub const WM_NCLBUTTONDBLCLK: c_uint = 0x00A3;
pub const WM_NCRBUTTONDOWN: c_uint = 0x00A4;
pub const WM_NCRBUTTONUP: c_uint = 0x00A5;
pub const WM_NCRBUTTONDBLCLK: c_uint = 0x00A6;
pub const WM_NCMBUTTONDOWN: c_uint = 0x00A7;
pub const WM_NCMBUTTONUP: c_uint = 0x00A8;
pub const WM_NCMBUTTONDBLCLK: c_uint = 0x00A9;
pub const WM_NCXBUTTONDOWN: c_uint = 0x00AB;
pub const WM_NCXBUTTONUP: c_uint = 0x00AC;
pub const WM_NCXBUTTONDBLCLK: c_uint = 0x00AD;
pub const WM_INPUT: c_uint = 0x00FF;
pub const WM_KEYFIRST: c_uint = 0x0100;
pub const WM_KEYDOWN: c_uint = 0x0100;
pub const WM_KEYUP: c_uint = 0x0101;
pub const WM_CHAR: c_uint = 0x0102;
pub const WM_DEADCHAR: c_uint = 0x0103;
pub const WM_SYSKEYDOWN: c_uint = 0x0104;
pub const WM_SYSKEYUP: c_uint = 0x0105;
pub const WM_SYSCHAR: c_uint = 0x0106;
pub const WM_SYSDEADCHAR: c_uint = 0x0107;
pub const WM_KEYLAST: c_uint = 0x0109;
pub const WM_UNICHAR: c_uint = 0x0109;
pub const WM_IME_STARTCOMPOSITION: c_uint = 0x010D;
pub const WM_IME_ENDCOMPOSITION: c_uint = 0x010E;
pub const WM_IME_COMPOSITION: c_uint = 0x010F;
pub const WM_IME_KEYLAST: c_uint = 0x010F;
pub const WM_INITDIALOG: c_uint = 0x0110;
pub const WM_COMMAND: c_uint = 0x0111;
pub const WM_SYSCOMMAND: c_uint = 0x0112;
pub const WM_TIMER: c_uint = 0x0113;
pub const WM_HSCROLL: c_uint = 0x0114;
pub const WM_VSCROLL: c_uint = 0x0115;
pub const WM_INITMENU: c_uint = 0x0116;
pub const WM_INITMENUPOPUP: c_uint = 0x0117;
pub const WM_MENUSELECT: c_uint = 0x011F;
pub const WM_MENUCHAR: c_uint = 0x0120;
pub const WM_ENTERIDLE: c_uint = 0x0121;
pub const WM_MENURBUTTONUP: c_uint = 0x0122;
pub const WM_MENUDRAG: c_uint = 0x0123;
pub const WM_MENUGETOBJECT: c_uint = 0x0124;
pub const WM_UNINITMENUPOPUP: c_uint = 0x0125;
pub const WM_MENUCOMMAND: c_uint = 0x0126;
pub const WM_CHANGEUISTATE: c_uint = 0x0127;
pub const WM_UPDATEUISTATE: c_uint = 0x0128;
pub const WM_QUERYUISTATE: c_uint = 0x0129;
pub const WM_CTLCOLORMSGBOX: c_uint = 0x0132;
pub const WM_CTLCOLOREDIT: c_uint = 0x0133;
pub const WM_CTLCOLORLISTBOX: c_uint = 0x0134;
pub const WM_CTLCOLORBTN: c_uint = 0x0135;
pub const WM_CTLCOLORDLG: c_uint = 0x0136;
pub const WM_CTLCOLORSCROLLBAR: c_uint = 0x0137;
pub const WM_CTLCOLORSTATIC: c_uint = 0x0138;
pub const WM_MOUSEFIRST: c_uint = 0x0200;
pub const WM_MOUSEMOVE: c_uint = 0x0200;
pub const WM_LBUTTONDOWN: c_uint = 0x0201;
pub const WM_LBUTTONUP: c_uint = 0x0202;
pub const WM_LBUTTONDBLCLK: c_uint = 0x0203;
pub const WM_RBUTTONDOWN: c_uint = 0x0204;
pub const WM_RBUTTONUP: c_uint = 0x0205;
pub const WM_RBUTTONDBLCLK: c_uint = 0x0206;
pub const WM_MBUTTONDOWN: c_uint = 0x0207;
pub const WM_MBUTTONUP: c_uint = 0x0208;
pub const WM_MBUTTONDBLCLK: c_uint = 0x0209;
pub const WM_MOUSELAST_95: c_uint = 0x0209;
pub const WM_MOUSEWHEEL: c_uint = 0x020A;
pub const WM_MOUSELAST_NT4_98: c_uint = 0x020A;
pub const WM_XBUTTONDOWN: c_uint = 0x020B;
pub const WM_XBUTTONUP: c_uint = 0x020C;
pub const WM_XBUTTONDBLCLK: c_uint = 0x020D;
pub const WM_MOUSELAST_2K_XP_2k3: c_uint = 0x020D;
pub const WM_PARENTNOTIFY: c_uint = 0x0210;
pub const WM_ENTERMENULOOP: c_uint = 0x0211;
pub const WM_EXITMENULOOP: c_uint = 0x0212;
pub const WM_NEXTMENU: c_uint = 0x0213;
pub const WM_SIZING: c_uint = 0x0214;
pub const WM_CAPTURECHANGED: c_uint = 0x0215;
pub const WM_MOVING: c_uint = 0x0216;
pub const WM_POWERBROADCAST: c_uint = 0x0218;
pub const WM_DEVICECHANGE: c_uint = 0x0219;
pub const WM_MDICREATE: c_uint = 0x0220;
pub const WM_MDIDESTROY: c_uint = 0x0221;
pub const WM_MDIACTIVATE: c_uint = 0x0222;
pub const WM_MDIRESTORE: c_uint = 0x0223;
pub const WM_MDINEXT: c_uint = 0x0224;
pub const WM_MDIMAXIMIZE: c_uint = 0x0225;
pub const WM_MDITILE: c_uint = 0x0226;
pub const WM_MDICASCADE: c_uint = 0x0227;
pub const WM_MDIICONARRANGE: c_uint = 0x0228;
pub const WM_MDIGETACTIVE: c_uint = 0x0229;
pub const WM_MDISETMENU: c_uint = 0x0230;
pub const WM_ENTERSIZEMOVE: c_uint = 0x0231;
pub const WM_EXITSIZEMOVE: c_uint = 0x0232;
pub const WM_DROPFILES: c_uint = 0x0233;
pub const WM_MDIREFRESHMENU: c_uint = 0x0234;
pub const WM_IME_SETCONTEXT: c_uint = 0x0281;
pub const WM_IME_NOTIFY: c_uint = 0x0282;
pub const WM_IME_CONTROL: c_uint = 0x0283;
pub const WM_IME_COMPOSITIONFULL: c_uint = 0x0284;
pub const WM_IME_SELECTpub: c_uint = 0x0285;
pub const WM_IME_CHAR: c_uint = 0x0286;
pub const WM_IME_REQUEST: c_uint = 0x0288;
pub const WM_IME_KEYDOWN: c_uint = 0x0290;
pub const WM_IME_KEYUP: c_uint = 0x0291;
pub const WM_MOUSEHOVER: c_uint = 0x02A1;
pub const WM_MOUSELEAVE: c_uint = 0x02A3;
pub const WM_NCMOUSEHOVER: c_uint = 0x02A0;
pub const WM_NCMOUSELEAVE: c_uint = 0x02A2;
pub const WM_WTSSESSION_CHANGE: c_uint = 0x02B1;
pub const WM_TABLET_FIRST: c_uint = 0x02C0;
pub const WM_TABLET_LAST: c_uint = 0x02DF;
pub const WM_CUT: c_uint = 0x0300;
pub const WM_COPY: c_uint = 0x0301;
pub const WM_PASTE: c_uint = 0x0302;
pub const WM_CLEAR: c_uint = 0x0303;
pub const WM_UNDO: c_uint = 0x0304;
pub const WM_RENDERFORMAT: c_uint = 0x0305;
pub const WM_RENDERALLFORMATS: c_uint = 0x0306;
pub const WM_DESTROYCLIPBOARD: c_uint = 0x0307;
pub const WM_DRAWCLIPBOARD: c_uint = 0x0308;
pub const WM_PAINTCLIPBOARD: c_uint = 0x0309;
pub const WM_VSCROLLCLIPBOARD: c_uint = 0x030A;
pub const WM_SIZECLIPBOARD: c_uint = 0x030B;
pub const WM_ASKCBFORMATNAME: c_uint = 0x030C;
pub const WM_CHANGECBCHAIN: c_uint = 0x030D;
pub const WM_HSCROLLCLIPBOARD: c_uint = 0x030E;
pub const WM_QUERYNEWPALETTE: c_uint = 0x030F;
pub const WM_PALETTEISCHANGING: c_uint = 0x0310;
pub const WM_PALETTECHANGED: c_uint = 0x0311;
pub const WM_HOTKEY: c_uint = 0x0312;
pub const WM_PRINT: c_uint = 0x0317;
pub const WM_PRINTCLIENT: c_uint = 0x0318;
pub const WM_APPCOMMAND: c_uint = 0x0319;
pub const WM_THEMECHANGED: c_uint = 0x031A;
pub const WM_HANDHELDFIRST: c_uint = 0x0358;
pub const WM_HANDHELDLAST: c_uint = 0x035F;
pub const WM_AFXFIRST: c_uint = 0x0360;
pub const WM_AFXLAST: c_uint = 0x037F;
pub const WM_PENWINFIRST: c_uint = 0x0380;
pub const WM_PENWINLAST: c_uint = 0x038F;
pub const WM_USER: c_uint = 0x0400;
pub const WM_APP: c_uint = 0x8000;

pub const WS_BORDER: DWORD = 0x00800000;
pub const WS_CAPTION: DWORD = 0x00C00000;
pub const WS_CHILD: DWORD = 0x40000000;
pub const WS_CHILDWINDOW: DWORD = 0x40000000;
pub const WS_CLIPCHILDREN: DWORD = 0x02000000;
pub const WS_CLIPSIBLINGS: DWORD = 0x04000000;
pub const WS_DISABLED: DWORD = 0x08000000;
pub const WS_DLGFRAME: DWORD = 0x00400000;
pub const WS_GROUP: DWORD = 0x00020000;
pub const WS_HSCROLL: DWORD = 0x00100000;
pub const WS_ICONIC: DWORD = 0x20000000;
pub const WS_MAXIMIZE: DWORD = 0x01000000;
pub const WS_MAXIMIZEBOX: DWORD = 0x00010000;
pub const WS_MINIMIZE: DWORD = 0x20000000;
pub const WS_MINIMIZEBOX: DWORD = 0x00020000;
pub const WS_OVERLAPPED: DWORD = 0x00000000;
pub const WS_OVERLAPPEDWINDOW: DWORD = (WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX);
pub const WS_POPUP: DWORD = 0x80000000;
pub const WS_POPUPWINDOW: DWORD = (WS_POPUP | WS_BORDER | WS_SYSMENU);
pub const WS_SIZEBOX: DWORD = 0x00040000;
pub const WS_SYSMENU: DWORD = 0x00080000;
pub const WS_TABSTOP: DWORD = 0x00010000;
pub const WS_THICKFRAME: DWORD = 0x00040000;
pub const WS_TILED: DWORD = 0x00000000;
pub const WS_VISIBLE: DWORD = 0x10000000;
pub const WS_VSCROLL: DWORD = 0x00200000;

pub const CW_USEDEFAULT = c_translation.cast(c_int, c_translation.promoteIntLiteral(c_int, 0x80000000, .hex));

pub const PATCOPY: DWORD = 0x00F00021;
pub const PATPAINT: DWORD = 0x00FB0A09;
pub const PATINVERT: DWORD = 0x005A0049;
pub const DSTINVERT: DWORD = 0x00550009;
pub const BLACKNESS: DWORD = 0x00000042;
pub const WHITENESS: DWORD = 0x00FF0062;

pub const WNDCLASSA = extern struct {
    style: c_uint = 0,
    lpfnWndProc: ?WNDPROC = null,
    cbClsExtra: c_int = 0,
    cbWndExtra: c_int = 0,
    hInstance: ?HINSTANCE = null,
    hIcon: ?HICON = null,
    hCursor: ?HCURSOR = null,
    hbrBackground: ?HBRUSH = null,
    lpszMenuName: ?LPCSTR = null,
    lpszClassName: ?LPCSTR = null,
};

pub const WNDCLASSW = extern struct {
    style: c_uint = 0,
    lpfnWndProc: ?WNDPROC = null,
    cbClsExtra: c_int = 0,
    cbWndExtra: c_int = 0,
    hInstance: ?HINSTANCE = null,
    hIcon: ?HICON = null,
    hCursor: ?HCURSOR = null,
    hbrBackground: ?HBRUSH = null,
    lpszMenuName: ?LPCWSTR = null,
    lpszClassName: ?LPCWSTR = null,
};

pub const STARTUPINFOA = extern struct {
    cb: DWORD = 0,
    lpReserved: LPSTR = null,
    lpDesktop: LPSTR = null,
    lpTitle: LPSTR = null,
    dwX: DWORD = 0,
    dwY: DWORD = 0,
    dwXSize: DWORD = 0,
    dwYSize: DWORD = 0,
    dwXCountChars: DWORD = 0,
    dwYCountChars: DWORD = 0,
    dwFillAttribute: DWORD = 0,
    dwFlags: DWORD = 0,
    wShowWindow: WORD = 0,
    cbReserved2: WORD = 0,
    lpReserved2: LPBYTE = null,
    hStdInput: HANDLE = null,
    hStdOutput: HANDLE = null,
    hStdError: HANDLE = null,
};

pub const STARTUPINFOW = extern struct {
    cb: DWORD = 0,
    lpReserved: LPWSTR = null,
    lpDesktop: LPWSTR = null,
    lpTitle: LPWSTR = null,
    dwX: DWORD = 0,
    dwY: DWORD = 0,
    dwXSize: DWORD = 0,
    dwYSize: DWORD = 0,
    dwXCountChars: DWORD = 0,
    dwYCountChars: DWORD = 0,
    dwFillAttribute: DWORD = 0,
    dwFlags: DWORD = 0,
    wShowWindow: WORD = 0,
    cbReserved2: WORD = 0,
    lpReserved2: LPBYTE = null,
    hStdInput: HANDLE = null,
    hStdOutput: HANDLE = null,
    hStdError: HANDLE = null,
};

pub const MSG = extern struct {
    hwnd: ?HWND = null,
    message: c_uint = 0,
    wParam: WPARAM = 0,
    lParam: LPARAM = 0,
    time: DWORD = 0,
    pt: POINT = .{ .x = 0, .y = 0 },
    lPrivate: DWORD = 0,
};

pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]BYTE,
};

pub const WNDPROC = *const fn (HWND, c_uint, WPARAM, LPARAM) callconv(.winapi) LRESULT;

pub extern "user32" fn GetModuleHandleA(module_name: ?LPCSTR) callconv(.winapi) HMODULE;
pub extern "user32" fn GetModuleHandleW(module_name: ?LPCWSTR) callconv(.winapi) HMODULE;
pub extern "user32" fn GetCommandLineA() callconv(.winapi) LPSTR;
pub extern "user32" fn GetCommandLineW() callconv(.winapi) LPWSTR;
pub extern "user32" fn GetStartupInfoA(info: *STARTUPINFOA) callconv(.winapi) void;
pub extern "user32" fn GetStartupInfoW(info: *STARTUPINFOW) callconv(.winapi) void;

pub extern "user32" fn MessageBoxA(instance: ?HINSTANCE, text: LPCSTR, caption: LPCSTR, type: c_uint) callconv(.winapi) c_int;
pub extern "user32" fn MessageBoxW(instance: ?HINSTANCE, text: LPCWSTR, caption: LPCWSTR, type: c_uint) callconv(.winapi) c_int;

pub extern "user32" fn DefWindowProcA(window: HWND, msg: c_uint, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn DefWindowProcW(window: HWND, msg: c_uint, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT;

pub extern "user32" fn RegisterClassA(class: *const WNDCLASSA) callconv(.winapi) ATOM;
pub extern "user32" fn RegisterClassW(class: *const WNDCLASSW) callconv(.winapi) ATOM;

pub extern "user32" fn CreateWindowExA(ex_style: DWORD, class_name: ?LPCSTR, window_name: ?LPCSTR, style: DWORD, x: c_int, y: c_int, width: c_int, height: c_int, parent_window: ?HWND, menu: ?HMENU, instance: ?HINSTANCE, param: ?LPVOID) callconv(.winapi) ?HWND;

pub extern "user32" fn GetMessageA(msg: LPMSG, hwnd: ?HWND, msg_filter_min: c_uint, msg_filter_max: c_uint) callconv(.winapi) BOOL;
pub extern "user32" fn GetMessageW(msg: LPMSG, hwnd: ?HWND, msg_filter_min: c_uint, msg_filter_max: c_uint) callconv(.winapi) BOOL;

pub extern "user32" fn TranslateMessage(msg: *const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageA(msg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn DispatchMessageW(msg: *const MSG) callconv(.winapi) LRESULT;

pub extern "user32" fn BeginPaint(hwnd: HWND, paint: *PAINTSTRUCT) callconv(.winapi) HDC;
pub extern "user32" fn EndPaint(hwnd: HWND, paint: *PAINTSTRUCT) callconv(.winapi) BOOL;
pub extern "gdi32" fn PatBlt(hdc: HDC, x: c_int, y: c_int, w: c_int, h: c_int, rop: DWORD) callconv(.winapi) BOOL;
