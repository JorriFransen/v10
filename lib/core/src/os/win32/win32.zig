const std = @import("std");
const zig_win32 = std.os.windows;

const assert = @import("../../assert.zig").assert;
const bits = @import("../../bits.zig");
const math = @import("../../math.zig");
const time = @import("../../time.zig");

pub fn getTime(clock: time.Clock) time.TimeStamp {
    switch (clock) {
        .monotonic => {
            const expected_qpf = 10_000_000;
            var qpf: LARGE_INTEGER = .{ .quad_part = expected_qpf };
            _ = NT.RtlQueryPerformanceFrequency(&qpf);

            var qpc: LARGE_INTEGER = .{ .quad_part = 0 };
            return if (NT.RtlQueryPerformanceCounter(&qpc).toBool())
                if (qpf.quad_part == 10_000_000)
                    .{ ._ns = @as(i96, qpc.quad_part) * 100 }
                else
                    .{ ._ns = @intCast((@as(u128, qpc.quad_part) * std.time.ns_per_s) / qpf.quad_part) }
            else
                .zero;
        },

        .real => {
            // 100ns ticks
            const ticks = NT.RtlGetSystemTimePrecise();
            return .{ ._ns = (@as(i96, ticks) * 100) + (std.time.epoch.windows * std.time.ns_per_s) };
        },

        .cpu_thread => {
            var info: NT.KERNEL_USER_TIMES = undefined;
            var return_len: c_ulong = undefined;
            if (NT.NtQueryInformationThread(NT.CURRENT_THREAD, .Times, &info, @sizeOf(@TypeOf(info)), &return_len) == .SUCCESS) {
                assert(return_len == @sizeOf(NT.KERNEL_USER_TIMES));
                // 100ns ticks
                return .{ ._ns = (@as(i96, info.kernel_time.quad_part) + @as(i96, info.user_time.quad_part)) * 100 };
            } else {
                return .zero;
            }
        },

        .cpu_process => {
            var info: NT.KERNEL_USER_TIMES = undefined;
            var return_len: c_ulong = undefined;
            if (NT.NtQueryInformationProcess(NT.CURRENT_PROCESS, .Times, &info, @sizeOf(@TypeOf(info)), &return_len) == .SUCCESS) {
                assert(return_len == @sizeOf(NT.KERNEL_USER_TIMES));
                // 100ns ticks
                return .{ ._ns = (@as(i96, info.kernel_time.quad_part) + @as(i96, info.user_time.quad_part)) * 100 };
            } else {
                return .zero;
            }
        },
    }
}

pub inline fn peb() *zig_win32.PEB {
    comptime assert(@offsetOf(zig_win32.TEB, "ProcessEnvironmentBlock") == 0x60);
    return asm (
        \\ movq %%gs:0x60, %[ptr]
        : [ptr] "=r" (-> *zig_win32.PEB),
    );
}

pub const fs = @import("fs.zig");
pub const NT = @import("ntdll.zig");
pub const ACCESS_MASK = NT.ACCESS_MASK;
pub const NTSTATUS = NT.NTSTATUS;
pub const SECURITY_ATTRIBUTES = NT.SECURITY_ATTRIBUTES;
pub const OVERLAPPED = NT.OVERLAPPED;
pub const FILETIME = NT.FILETIME;

pub const BOOL = enum(c_int) {
    FALSE = 0,
    TRUE = 1,
    _,

    pub inline fn toBool(this: BOOL) bool {
        return @intFromEnum(this) != 0;
    }
};

pub const ERROR = @import("error.zig").ERROR;
pub const HANDLE = *anyopaque;
pub const HINSTANCE = HANDLE;
pub const HMODULE = HANDLE;
pub const HWND = HANDLE;
pub const HICON = HANDLE;
pub const HCURSOR = HICON;
pub const HBRUSH = HANDLE;
pub const HMENU = HANDLE;
pub const HDC = HANDLE;
pub const HMONITOR = HANDLE;

pub const BYTE = u8;
pub const CHAR = u8;
pub const WCHAR = u16;
pub const WORD = u16;
pub const SHORT = i16;
pub const USHORT = u16;
pub const DWORD = u32;
pub const INT = i32;
pub const UINT = u32;
pub const LONG = i32;
pub const ULONG = u32;
pub const LONGLONG = i64;
pub const ULONGLONG = u64;
pub const WPARAM = u64;
pub const LPARAM = i64;
pub const LRESULT = i64;
pub const ATOM = WORD;
pub const HRESULT = LONG;
pub const SIZE_T = usize;
pub const ULONG_PTR = usize;

pub const LPSTR = [*:0]CHAR;
pub const LPCSTR = [*:0]const CHAR;

pub const PWSTR = [*:0]WCHAR;
pub const LPWSTR = [*:0]WCHAR;
pub const PCWSTR = [*:0]const WCHAR;

pub const PVOID = *anyopaque;
pub const LPVOID = *anyopaque;
pub const LPCVOID = *const anyopaque;

pub const FARPROC = *anyopaque;

pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(math.maxInt(usize));

pub const MAX_PATH = 260;
pub const PATH_MAX_WIDE = 32767;
pub const NAME_MAX = 255;

pub const PROCESS = struct {
    pub const DPI_AWARENESS = enum(c_int) {
        DPI_UNAWARE = 0,
        SYSTEM_DPI_AWARE = 1,
        PER_MONITOR_DPI_AWARE = 2,
    };
};

pub const FILE = struct {
    pub const SHARE = NT.FILE.SHARE;

    /// This is a union of FILE_FLAG_* and FILE_ATTRIBUTE_ constants.
    /// This must stay in sync with NT.FILE.ATTRIBUTES.
    pub const FLAGS_AND_ATTRIBUTES = packed struct(ULONG) {
        READONLY: bool = false,
        HIDDEN: bool = false,
        SYSTEM: bool = false,
        __reserved0__: u1 = 0,
        DIRECTORY: bool = false,
        ARCHIVE: bool = false,
        DEVICE: bool = false,
        NORMAL: bool = false,
        TEMPORARY: bool = false,
        SPARSE_FILE: bool = false,
        REPARSE_POINT: bool = false,
        COMPRESSED: bool = false,
        OFFLINE: bool = false,
        NOT_CONTENT_INDEXED: bool = false,
        ENCRYPTED: bool = false,
        INTEGRITY_STREAM: bool = false,
        VIRTUAL: bool = false,
        NO_SCRUB_DATA: bool = false,
        RECALL_ON_OPEN: bool = false,
        PINNED: bool = false,
        UNPINNED: bool = false,
        OPEN_REPARSE_POINT: bool = false,
        RECALL_ON_DATA_ACCESS: bool = false,
        SESSION_AWARE: bool = false,
        POSIX_SEMANTICS: bool = false,
        BACKUP_SEMANTICS: bool = false,
        DELETE_ON_CLOSE: bool = false,
        SEQUENTIAL_SCAN: bool = false,
        RANDOM_ACCESS: bool = false,
        NO_BUFFERING: bool = false,
        OVERLAPPED: bool = false,
        WRITE_THROUGH: bool = false,

        pub const EA = @This(){ .RECALL_ON_OPEN = true };
        pub const OPEN_NO_RECALL = @This(){ .UNPINNED = true };
        pub const STRICTLY_SEQUENTIAL = @This(){ .NO_BUFFERING = true };

        pub const default = @This(){ .NORMAL = true };
    };

    pub const ATTRIBUTE_DATA = extern struct {
        file_attributes: NT.FILE.ATTRIBUTES,
        creation_time: FILETIME,
        last_access_time: FILETIME,
        last_write_time: FILETIME,
        file_size_high: DWORD,
        file_size_low: DWORD,
    };

    pub const Disposition = enum(ULONG) {
        CREATE_ALWAYS = 2,
        CREATE_NEW = 1,
        OPEN_ALWAYS = 4,
        OPEN_EXISTING = 3,
        TRUNCATE_EXISTING = 5,
    };
};

pub const WND = struct {
    pub const PROC = *const fn (HWND, WM, WPARAM, LPARAM) callconv(.winapi) LRESULT;

    pub const HWND_BOTTOM: ?HWND = @ptrFromInt(1);
    pub const HWND_NOTOPMOST: ?HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, -2))));
    pub const HWND_TOP: ?HWND = @ptrFromInt(0);
    pub const HWND_TOPMOST: ?HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));

    pub const CS = packed struct(UINT) {
        VREDRAW: bool = false,
        HREDRAW: bool = false,
        __reserved0__: u1 = 0,
        DBLCLKS: bool = false,
        __reserved1__: u1 = 0,
        OWNDC: bool = false,
        CLASSDC: bool = false,
        PARENTDC: bool = false,
        __reserved2__: u1 = 0,
        NOCLOSE: bool = false,
        __reserved3__: u1 = 0,
        SAVEBITS: bool = false,
        BYTEALIGNCLIENT: bool = false,
        BYTEALIGNWINDOW: bool = false,
        GLOBALCLASS: bool = false,
        __reserved4__: u2 = 0,
        DROPSHADOW: u1 = 0,
        __reserved5__: u14 = 0,
    };

    pub const CLASS = struct {
        pub const A = extern struct {
            style: CS = .{},
            lpfnWndProc: ?PROC = null,
            cbClsExtra: c_int = 0,
            cbWndExtra: c_int = 0,
            hInstance: ?HINSTANCE = null,
            hIcon: ?HICON = null,
            hCursor: ?HCURSOR = null,
            hbrBackground: ?HBRUSH = null,
            lpszMenuName: ?LPCSTR = null,
            lpszClassName: ?LPCSTR = null,
        };
    };

    pub const WS = packed struct(ULONG) {
        __reserved__: u16 = 0,
        TABSTOP: bool = false,
        GROUP: bool = false,
        THICKFRAME: bool = false,
        SYSMENU: bool = false,
        HSCROLL: bool = false,
        VSCROLL: bool = false,
        DLGFRAME: bool = false,
        BORDER: bool = false,
        MAXIMIZE: bool = false,
        CLIPCHILDREN: bool = false,
        CLIPSIBLINGS: bool = false,
        DISABLED: bool = false,
        VISIBLE: bool = false,
        MINIMIZE: bool = false,
        CHILD: bool = false,
        POPUP: bool = false,

        pub const OVERLAPPED = WS{};
        pub const TILED = WS{};
        pub const OVERLAPPEDWINDOW = WS{ .BORDER = true, .DLGFRAME = true, .SYSMENU = true, .THICKFRAME = true, .GROUP = true, .TABSTOP = true };
        pub const POPUPWINDOW = WS{ .POPUP = true, .BORDER = true, .SYSMENU = true };
        pub const CHILD_WINDOW = WS{ .CHILD = true };
        pub const ICONIC = WS{ .MINIMIZE = true };
        pub const MINIMIZEBOX = WS{ .GROUP = true };
        pub const MAXIMIZEBOX = WS{ .TABSTOP = true };
        pub const SIZEBOX = WS{ .THICKFRAME = true };
        pub const CAPTION = WS{ .BORDER = true, .DLGFRAME = true };
    };

    pub const WS_EX = packed struct(ULONG) {
        DLGMODALFRAME: bool = false,
        __reserved0__: u1 = 0,
        NOPARENTNOTIFY: bool = false,
        TOPMOST: bool = false,
        ACCEPTFILES: bool = false,
        TRANSPARENT: bool = false,
        MDICHILD: bool = false,
        TOOLWINDOW: bool = false,
        WINDOWEDGE: bool = false,
        CLIENTEDGE: bool = false,
        CONTEXTHELP: bool = false,
        __reserved1__: u1 = 0,
        RIGHT: bool = false,
        RTLREADING: bool = false,
        LEFTSCROLLBAR: bool = false,
        __reserved2__: u1 = 0,
        CONTROLPARENT: bool = false,
        STATICEDGE: bool = false,
        APPWINDOW: bool = false,
        LAYERED: bool = false,
        NOINHERITLAYOUT: bool = false,
        NOREDIRECTIONBITMAP: bool = false,
        LAYOUTRTL: bool = false,
        __reserved3: u2 = 0,
        COMPOSITED: bool = false,
        __reserved4: u1 = 0,
        NOACTIVATE: bool = false,
        __reserve5: u4 = 0,

        pub const LEFT = WS_EX{};
        pub const LTRREADING = WS_EX{};
        pub const RIGHTSCROLLBAR = WS_EX{};
        pub const OVERLAPPEDWINDOW = WS_EX{ .WINDOWEDGE = true, .CLIENTEDGE = true };
        pub const PALETTEWINDOW = WS_EX{ .WINDOWEDGE = true, .TOOLWINDOW = true, .TOPMOST = true };
    };

    pub const CW = struct {
        pub const USEDEFAULT: c_int = @bitCast(@as(c_uint, 0x80000000));
    };

    pub const MSG = extern struct {
        hwnd: ?HWND = null,
        message: WM = .NULL,
        wParam: WPARAM = 0,
        lParam: LPARAM = 0,
        time: DWORD = 0,
        pt: POINT = .{ .x = 0, .y = 0 },
        lPrivate: DWORD = 0,
    };

    pub const WM = enum(c_uint) {
        NULL = 0x0000,
        CREATE = 0x0001,
        DESTROY = 0x0002,
        MOVE = 0x0003,
        SIZE = 0x0005,
        ACTIVATE = 0x0006,
        SETFOCUS = 0x0007,
        KILLFOCUS = 0x0008,
        ENABLE = 0x000A,
        SETREDRAW = 0x000B,
        SETTEXT = 0x000C,
        GETTEXT = 0x000D,
        GETTEXTLENGTH = 0x000E,
        PAINT = 0x000F,
        CLOSE = 0x0010,
        QUERYENDSESSION = 0x0011,
        QUERYOPEN = 0x0013,
        ENDSESSION = 0x0016,
        QUIT = 0x0012,
        ERASEBKGND = 0x0014,
        SYSCOLORCHANGE = 0x0015,
        SHOWWINDOW = 0x0018,
        WININICHANGE = 0x001A,
        DEVMODECHANGE = 0x001B,
        ACTIVATEAPP = 0x001C,
        FONTCHANGE = 0x001D,
        TIMECHANGE = 0x001E,
        CANCELMODE = 0x001F,
        SETCURSOR = 0x0020,
        MOUSEACTIVATE = 0x0021,
        CHILDACTIVATE = 0x0022,
        QUEUESYNC = 0x0023,
        GETMINMAXINFO = 0x0024,
        PAINTICON = 0x0026,
        ICONERASEBKGND = 0x0027,
        NEXTDLGCTL = 0x0028,
        SPOOLERSTATUS = 0x002A,
        DRAWITEM = 0x002B,
        MEASUREITEM = 0x002C,
        DELETEITEM = 0x002D,
        VKEYTOITEM = 0x002E,
        CHARTOITEM = 0x002F,
        SETFONT = 0x0030,
        GETFONT = 0x0031,
        SETHOTKEY = 0x0032,
        GETHOTKEY = 0x0033,
        QUERYDRAGICON = 0x0037,
        COMPAREITEM = 0x0039,
        GETOBJECT = 0x003D,
        COMPACTING = 0x0041,
        COMMNOTIFY = 0x0044,
        WINDOWPOSCHANGING = 0x0046,
        WINDOWPOSCHANGED = 0x0047,
        POWER = 0x0048,
        COPYDATA = 0x004A,
        CANCELJOURNAL = 0x004B,
        NOTIFY = 0x004E,
        INPUTLANGCHANGEREQUEST = 0x0050,
        INPUTLANGCHANGE = 0x0051,
        TCARD = 0x0052,
        HELP = 0x0053,
        USERCHANGED = 0x0054,
        NOTIFYFORMAT = 0x0055,
        CONTEXTMENU = 0x007B,
        STYLECHANGING = 0x007C,
        STYLECHANGED = 0x007D,
        DISPLAYCHANGE = 0x007E,
        GETICON = 0x007F,
        SETICON = 0x0080,
        NCCREATE = 0x0081,
        NCDESTROY = 0x0082,
        NCCALCSIZE = 0x0083,
        NCHITTEST = 0x0084,
        NCPAINT = 0x0085,
        NCACTIVATE = 0x0086,
        GETDLGCODE = 0x0087,
        SYNCPAINT = 0x0088,
        NCMOUSEMOVE = 0x00A0,
        NCLBUTTONDOWN = 0x00A1,
        NCLBUTTONUP = 0x00A2,
        NCLBUTTONDBLCLK = 0x00A3,
        NCRBUTTONDOWN = 0x00A4,
        NCRBUTTONUP = 0x00A5,
        NCRBUTTONDBLCLK = 0x00A6,
        NCMBUTTONDOWN = 0x00A7,
        NCMBUTTONUP = 0x00A8,
        NCMBUTTONDBLCLK = 0x00A9,
        NCXBUTTONDOWN = 0x00AB,
        NCXBUTTONUP = 0x00AC,
        NCXBUTTONDBLCLK = 0x00AD,
        INPUT = 0x00FF,
        KEYDOWN = 0x0100,
        KEYUP = 0x0101,
        CHAR = 0x0102,
        DEADCHAR = 0x0103,
        SYSKEYDOWN = 0x0104,
        SYSKEYUP = 0x0105,
        SYSCHAR = 0x0106,
        SYSDEADCHAR = 0x0107,
        UNICHAR = 0x0109,
        IME_STARTCOMPOSITION = 0x010D,
        IME_ENDCOMPOSITION = 0x010E,
        IME_COMPOSITION = 0x010F,
        INITDIALOG = 0x0110,
        COMMAND = 0x0111,
        SYSCOMMAND = 0x0112,
        TIMER = 0x0113,
        HSCROLL = 0x0114,
        VSCROLL = 0x0115,
        INITMENU = 0x0116,
        INITMENUPOPUP = 0x0117,
        MENUSELECT = 0x011F,
        MENUCHAR = 0x0120,
        ENTERIDLE = 0x0121,
        MENURBUTTONUP = 0x0122,
        MENUDRAG = 0x0123,
        MENUGETOBJECT = 0x0124,
        UNINITMENUPOPUP = 0x0125,
        MENUCOMMAND = 0x0126,
        CHANGEUISTATE = 0x0127,
        UPDATEUISTATE = 0x0128,
        QUERYUISTATE = 0x0129,
        CTLCOLORMSGBOX = 0x0132,
        CTLCOLOREDIT = 0x0133,
        CTLCOLORLISTBOX = 0x0134,
        CTLCOLORBTN = 0x0135,
        CTLCOLORDLG = 0x0136,
        CTLCOLORSCROLLBAR = 0x0137,
        CTLCOLORSTATIC = 0x0138,
        MOUSEMOVE = 0x0200,
        LBUTTONDOWN = 0x0201,
        LBUTTONUP = 0x0202,
        LBUTTONDBLCLK = 0x0203,
        RBUTTONDOWN = 0x0204,
        RBUTTONUP = 0x0205,
        RBUTTONDBLCLK = 0x0206,
        MBUTTONDOWN = 0x0207,
        MBUTTONUP = 0x0208,
        MBUTTONDBLCLK = 0x0209,
        MOUSEWHEEL = 0x020A,
        XBUTTONDOWN = 0x020B,
        XBUTTONUP = 0x020C,
        XBUTTONDBLCLK = 0x020D,
        PARENTNOTIFY = 0x0210,
        ENTERMENULOOP = 0x0211,
        EXITMENULOOP = 0x0212,
        NEXTMENU = 0x0213,
        SIZING = 0x0214,
        CAPTURECHANGED = 0x0215,
        MOVING = 0x0216,
        POWERBROADCAST = 0x0218,
        DEVICECHANGE = 0x0219,
        MDICREATE = 0x0220,
        MDIDESTROY = 0x0221,
        MDIACTIVATE = 0x0222,
        MDIRESTORE = 0x0223,
        MDINEXT = 0x0224,
        MDIMAXIMIZE = 0x0225,
        MDITILE = 0x0226,
        MDICASCADE = 0x0227,
        MDIICONARRANGE = 0x0228,
        MDIGETACTIVE = 0x0229,
        MDISETMENU = 0x0230,
        ENTERSIZEMOVE = 0x0231,
        EXITSIZEMOVE = 0x0232,
        DROPFILES = 0x0233,
        MDIREFRESHMENU = 0x0234,
        IME_SETCONTEXT = 0x0281,
        IME_NOTIFY = 0x0282,
        IME_CONTROL = 0x0283,
        IME_COMPOSITIONFULL = 0x0284,
        IME_SELECT = 0x0285,
        IME_CHAR = 0x0286,
        IME_REQUEST = 0x0288,
        IME_KEYDOWN = 0x0290,
        IME_KEYUP = 0x0291,
        MOUSEHOVER = 0x02A1,
        MOUSELEAVE = 0x02A3,
        NCMOUSEHOVER = 0x02A0,
        NCMOUSELEAVE = 0x02A2,
        WTSSESSION_CHANGE = 0x02B1,
        TABLET_FIRST = 0x02C0,
        TABLET_LAST = 0x02DF,
        CUT = 0x0300,
        COPY = 0x0301,
        PASTE = 0x0302,
        CLEAR = 0x0303,
        UNDO = 0x0304,
        RENDERFORMAT = 0x0305,
        RENDERALLFORMATS = 0x0306,
        DESTROYCLIPBOARD = 0x0307,
        DRAWCLIPBOARD = 0x0308,
        PAINTCLIPBOARD = 0x0309,
        VSCROLLCLIPBOARD = 0x030A,
        SIZECLIPBOARD = 0x030B,
        ASKCBFORMATNAME = 0x030C,
        CHANGECBCHAIN = 0x030D,
        HSCROLLCLIPBOARD = 0x030E,
        QUERYNEWPALETTE = 0x030F,
        PALETTEISCHANGING = 0x0310,
        PALETTECHANGED = 0x0311,
        HOTKEY = 0x0312,
        PRINT = 0x0317,
        PRINTCLIENT = 0x0318,
        APPCOMMAND = 0x0319,
        THEMECHANGED = 0x031A,
        HANDHELDFIRST = 0x0358,
        HANDHELDLAST = 0x035F,
        AFXFIRST = 0x0360,
        AFXLAST = 0x037F,
        PENWINFIRST = 0x0380,
        PENWINLAST = 0x038F,
        USER = 0x0400,
        APP = 0x8000,

        _,

        pub const SETTINGCHANGE = .WININICHANGE;
        pub const KEYFIRST = .KEYDOWN;
        pub const KEYLAST = .UNICHAR;
        pub const IME_KEYLAST = .IME_COMPOSITION;
        pub const MOUSEFIRST = .MOUSEMOVE;
        pub const MOUSELAST_95 = .MBUTTONDBLCLK;
        pub const MOUSELAST_NT4_98 = .MOUSEWHEEL;
        pub const MOUSELAST_2K_XP_2k3 = .XBUTTONDBLCLK;
    };

    pub const PM = packed struct(c_int) {
        REMOVE: bool = false,
        NOYIELD: bool = false,
        __reserved__: @Int(.unsigned, @bitSizeOf(c_int) - 2) = 0,

        pub const NOREMOVE = PM{};
        pub const QS_INPUT: PM = @bitCast(@as(c_int, @bitCast(QS.INPUT)) << 16);
        pub const QS_POSTMESSAGE: PM = @bitCast(@as(c_int, @bitCast(QS{ .POSTMESSAGE = true, .HOTKEY = true, .TIMER = true })) << 16);
        pub const QS_PAINT: PM = @bitCast(@as(c_int, @bitCast(QS{ .PAINT = true })) << 16);
        pub const QS_SENDMESSAGE: PM = @bitCast(@as(c_int, @bitCast(QS{ .SENDMESSAGE = true })) << 16);
    };

    pub const HT = enum(c_int) {
        BORDER = 18,
        BOTTOM = 15,
        BOTTOMLEFT = 16,
        BOTTOMRIGHT = 17,
        CAPTION = 2,
        CLIENT = 1,
        CLOSE = 20,
        ERROR = -2,
        GROWBOX = 4,
        HELP = 21,
        HSCROLL = 6,
        LEFT = 10,
        MENU = 5,
        MAXBUTTON = 9,
        MINBUTTON = 8,
        NOWHERE = 0,
        RIGHT = 11,
        SYSMENU = 3,
        TOP = 12,
        TOPLEFT = 13,
        TOPRIGHT = 14,
        TRANSPARENT = -1,
        VSCROLL = 7,
        _,

        pub const REDUCE = .MINBUTTON;
        pub const SIZE = .GROWBOX;
        pub const ZOOM = .MAXBUTTON;
    };

    pub const SWP = packed struct(UINT) {
        NOSIZE: bool = false,
        NOMOVE: bool = false,
        NOZORDER: bool = false,
        NOREDRAW: bool = false,
        NOACTIVATE: bool = false,
        FRAMECHANGED: bool = false,
        SHOWWINDOW: bool = false,
        HIDEWINDOW: bool = false,
        NOCOPYBITS: bool = false,
        NOOWNERZORDER: bool = false,
        NOSENDCHANGING: bool = false,
        __reserved0__: u2 = 0,
        DEFERERASE: bool = false,
        ASYNCWINDOWPOS: bool = false,
        __reserved1__: @Int(.unsigned, @bitSizeOf(UINT) - 15) = 0,

        pub const DRAWFRAME = SWP{ .FRAMECHANGED = true };
        pub const NOREPOSITION = SWP{ .NOOWNERZORDER = true };
    };

    pub const WL = enum(c_int) {
        USERDATA = -21,
        EXSTYLE = -20,
        STYLE = -16,
        ID = -12,
        HWNDPARENT = -8,
        HINSTANCE = -6,
        WNDPROC = -4,
        DIALOG_MSGRESULT = 0,
        DIALOG_DLGPROC = 4,
        DIALOG_USER = 8,
    };
};

pub const MONITORINFO = extern struct {
    size: DWORD = @sizeOf(@This()),
    monitor: RECT = .{},
    work: RECT = .{},
    flags: DWORD = 0,
};

pub const WINDOWPLACEMENT = extern struct {
    length: UINT = @sizeOf(@This()),
    flags: UINT = 0,
    chow_cmd: UINT = 0,
    min_position: POINT = .{},
    max_position: POINT = .{},
    normal_position: RECT = .{},
    device: RECT = .{},
};

pub const IDC = enum(c_int) {
    ARROW = 32512,
    IBEAM = 32513,
    WAIT = 32514,
    CROSS = 32515,
    UPARROW = 32516,
    SIZENWSE = 32642,
    SIZENESW = 32643,
    SIZEWE = 32644,
    SIZENS = 32645,
    SIZEALL = 32646,
    NO = 32648,
    HAND = 32649,
    APPSTARTING = 32650,
    HELP = 32651,
    PIN = 32671,
    PERSON = 32672,
};

pub const BITMAPINFOHEADER = extern struct {
    biSize: DWORD = @sizeOf(BITMAPINFOHEADER),
    biWidth: LONG,
    biHeight: LONG,
    biPlanes: WORD,
    biBitCount: WORD,
    biCompression: COMPRESSION,
    biSizeImage: DWORD = 0,
    biXPelsPerMeter: LONG = 0,
    biYPelsPerMeter: LONG = 0,
    biClrUsed: DWORD = 0,
    biClrImportant: DWORD = 0,

    pub const COMPRESSION = enum(DWORD) {
        RGB = 0,
        RLE8 = 1,
        RLE4 = 2,
        BITFIELDS = 3,
        JPEG = 4,
        PNG = 5,

        _,
    };
};

pub const BITMAPINFO = extern struct {
    bmiHeader: BITMAPINFOHEADER,
    bmiColors: [1]RGBQUAD = .{.{}},
};

pub const RGBQUAD = extern struct {
    rgbBlue: BYTE = 0,
    rgbGreen: BYTE = 0,
    rgbRed: BYTE = 0,
    rgbReserved: BYTE = 0,
};

pub const ROP = packed struct(DWORD) {
    op: OP,
    __reserved__: u1 = 0,
    CAPTUREBLT: bool = false,
    NOMIRRORBITMAP: bool = false,

    pub const OP = enum(u29) {
        BLACKNESS = 0x00000042,
        NOTSRCERASE = 0x001100A6,
        NOTSRCCOPY = 0x00330008,
        SRCERASE = 0x00440328,
        DSTINVERT = 0x00550009,
        PATINVERT = 0x005A0049,
        SRCINVERT = 0x00660046,
        SRCAND = 0x008800C6,
        MERGEPAINT = 0x00BB0226,
        MERGECOPY = 0x00C000CA,
        SRCCOPY = 0x00CC0020,
        SRCPAINT = 0x00EE0086,
        PATCOPY = 0x00F00021,
        PATPAINT = 0x00FB0A09,
        WHITENESS = 0x00FF0062,

        _,
    };
};

pub const DIB_USAGE = enum(c_uint) {
    RGB_COLORS = 0,
    PAL_COLORS = 1,
};

pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]BYTE,
};

pub const MEM = struct {
    comptime {
        assert(@bitSizeOf(ALL) == @bitSizeOf(ALLOC));
        assert(@bitSizeOf(ALL) == @bitSizeOf(FREE));
    }

    pub const ALL = packed struct(ULONG) {
        EXTENDED_PARAMETER: packed struct(u9) {
            GRAPHICS: bool = false,
            NONPAGED: bool = false,
            ZERO_PAGES_OPTIONAL: bool = false,
            NONPAGED_LARGE: bool = false,
            NONPAGED_HUGE: bool = false,
            SOFT_FAULT_PAGES: bool = false,
            EC_CODE: bool = false,
            SECURE_PAGES: bool = false,
            TAGGED: bool = false,
        } = .{},

        __reserved0__: u3 = 0,
        COMMIT: bool = false,
        RESERVE: bool = false,
        DECOMMIT: bool = false,
        RELEASE: bool = false,
        FREE: bool = false,
        PRIVATE: bool = false,
        MAPPED: bool = false,
        RESET: bool = false,
        TOP_DOWN: bool = false,
        WRITE_WATCH: bool = false,
        PHYSICAL: bool = false,
        ROTATE: bool = false,
        RESET_UNDO: bool = false,
        __reserved1__: u4 = 0,
        LARGE_PAGES: bool = false,
        __reserved2__: u1 = 0,
        @"4MB_PAGES": bool = false,
    };

    pub const ALLOC = packed struct(ULONG) {
        __reserved0__: u12 = 0,
        COMMIT: bool = false,
        RESERVE: bool = false,
        __reserved1__: u5 = 0,
        RESET: bool = false,
        TOP_DOWN: bool = false,
        WRITE_WATCH: bool = false,
        PHYSICAL: bool = false,
        __reserved2__: u1 = 0,
        RESET_UNDO: bool = false,
        __reserved3__: u4 = 0,
        LARGE_PAGES: bool = false,
        __reserved4__: u2 = 0,
    };

    pub const FREE = packed struct(ULONG) {
        COALESCE_PLACEHOLDERS: bool = false,
        PRESERVE_PLACEHOLDER: bool = false,
        __reserved0__: u12 = 0,
        DECOMMIT: bool = false,
        RELEASE: bool = false,
        __reserved1__: u16 = 0,
    };

    pub const UNMAP_WITH_TRANSIENT_BOOST = ALL{ .EXTENDED_PARAMETER = .{ .GRAPHICS = true } };
    pub const COALESCE_PLACEHOLDERS = ALL{ .EXTENDED_PARAMETER = .{ .GRAPHICS = true } };
    pub const PRESERVE_PLACEHOLDER = ALL{ .EXTENDED_PARAMETER = .{ .GRAPHICS = true } };
    pub const REPLACE_PLACEHOLDER = ALL{ .DECOMMIT = true };
    pub const RESERVE_PLACEHOLDER = ALL{ .MAPPED = true };
    pub const DIFFERENT_IMAGE_BASE_OK = ALL{ .ROTATE = true };
    pub const IMAGE = ALL{ .RESET_UNDO = true };
};

pub const PAGE = packed struct(ULONG) {
    NOACCESS: bool = false,
    READONLY: bool = false,
    READWRITE: bool = false,
    WRITECOPY: bool = false,
    EXECUTE: bool = false,
    EXECUTE_READ: bool = false,
    EXECUTE_READWRITE: bool = false,
    EXECUTE_WRITECOPY: bool = false,
    GUARD: bool = false,
    NOCACHE: bool = false,
    WRITECOMBINE: bool = false,
    __reserved0__: u19 = 0,
    TARGETS_INVALID: bool = false,
    __reserved1__: u1 = 0,

    pub const TARGETS_NO_UPDATE = PAGE{ .TARGETS_INVALID = true };
};

pub const FILE_MAP = packed struct(ULONG) {
    COPY: bool = false,
    WRITE: bool = false,
    READ: bool = false,
    __reserved0__: u2 = 0,
    EXECUTE: bool = false,
    __reserved1__: u23 = 0,
    LARGE_PAGES: bool = false,
    TARGETS_INVALID: bool = false,
    RESERVE: bool = false,

    pub const ALL_ACCESS: FILE_MAP = @bitCast(@as(ULONG, 0xF001F));
};

pub const VK = enum(c_int) {
    LBUTTON = 0x01,
    RBUTTON = 0x02,
    CANCEL = 0x03,
    MBUTTON = 0x04,
    XBUTTON1 = 0x05,
    XBUTTON2 = 0x06,
    BACK = 0x08,
    TAB = 0x09,
    CLEAR = 0x0C,
    RETURN = 0x0D,
    SHIFT = 0x10,
    CONTROL = 0x11,
    MENU = 0x12,
    PAUSE = 0x13,
    CAPITAL = 0x14,
    KANA = 0x15,
    IME_ON = 0x16,
    JUNJA = 0x17,
    FINAL = 0x18,
    HANJA = 0x19,
    IME_OFF = 0x1A,
    ESCAPE = 0x1B,
    CONVERT = 0x1C,
    NONCONVERT = 0x1D,
    ACCEPT = 0x1E,
    MODECHANGE = 0x1F,
    SPACE = 0x20,
    PRIOR = 0x21,
    NEXT = 0x22,
    END = 0x23,
    HOME = 0x24,
    LEFT = 0x25,
    UP = 0x26,
    RIGHT = 0x27,
    DOWN = 0x28,
    SELECT = 0x29,
    PRINT = 0x2A,
    EXECUTE = 0x2B,
    SNAPSHOT = 0x2C,
    INSERT = 0x2D,
    DELETE = 0x2E,
    HELP = 0x2F,
    @"0" = '0',
    @"1" = '1',
    @"2" = '2',
    @"3" = '3',
    @"4" = '4',
    @"5" = '5',
    @"6" = '6',
    @"7" = '7',
    @"8" = '8',
    @"9" = '9',
    A = 0x41,
    B = 0x42,
    C = 0x43,
    D = 0x44,
    E = 0x45,
    F = 0x46,
    G = 0x47,
    H = 0x48,
    I = 0x49,
    J = 0x4A,
    K = 0x4B,
    L = 0x4C,
    M = 0x4D,
    N = 0x4E,
    O = 0x4F,
    P = 0x50,
    Q = 0x51,
    R = 0x52,
    S = 0x53,
    T = 0x54,
    U = 0x55,
    V = 0x56,
    W = 0x57,
    X = 0x58,
    Y = 0x59,
    Z = 0x5A,
    LWIN = 0x5B,
    RWIN = 0x5C,
    APPS = 0x5D,
    SLEEP = 0x5F,
    NUMPAD0 = 0x60,
    NUMPAD1 = 0x61,
    NUMPAD2 = 0x62,
    NUMPAD3 = 0x63,
    NUMPAD4 = 0x64,
    NUMPAD5 = 0x65,
    NUMPAD6 = 0x66,
    NUMPAD7 = 0x67,
    NUMPAD8 = 0x68,
    NUMPAD9 = 0x69,
    MULTIPLY = 0x6A,
    ADD = 0x6B,
    SEPARATOR = 0x6C,
    SUBTRACT = 0x6D,
    DECIMAL = 0x6E,
    DIVIDE = 0x6F,
    F1 = 0x70,
    F2 = 0x71,
    F3 = 0x72,
    F4 = 0x73,
    F5 = 0x74,
    F6 = 0x75,
    F7 = 0x76,
    F8 = 0x77,
    F9 = 0x78,
    F10 = 0x79,
    F11 = 0x7A,
    F12 = 0x7B,
    F13 = 0x7C,
    F14 = 0x7D,
    F15 = 0x7E,
    F16 = 0x7F,
    F17 = 0x80,
    F18 = 0x81,
    F19 = 0x82,
    F20 = 0x83,
    F21 = 0x84,
    F22 = 0x85,
    F23 = 0x86,
    F24 = 0x87,
    NUMLOCK = 0x90,
    SCROLL = 0x91,
    LSHIFT = 0xA0,
    RSHIFT = 0xA1,
    LCONTROL = 0xA2,
    RCONTROL = 0xA3,
    LMENU = 0xA4,
    RMENU = 0xA5,
    BROWSER_BACK = 0xA6,
    BROWSER_FORWARD = 0xA7,
    BROWSER_REFRESH = 0xA8,
    BROWSER_STOP = 0xA9,
    BROWSER_SEARCH = 0xAA,
    BROWSER_FAVORITES = 0xAB,
    BROWSER_HOME = 0xAC,
    VOLUME_MUTE = 0xAD,
    VOLUME_DOWN = 0xAE,
    VOLUME_UP = 0xAF,
    MEDIA_NEXT_TRACK = 0xB0,
    MEDIA_PREV_TRACK = 0xB1,
    MEDIA_STOP = 0xB2,
    MEDIA_PLAY_PAUSE = 0xB3,
    LAUNCH_MAIL = 0xB4,
    LAUNCH_MEDIA_SELECT = 0xB5,
    LAUNCH_APP1 = 0xB6,
    LAUNCH_APP2 = 0xB7,
    OEM_1 = 0xBA,
    OEM_PLUS = 0xBB,
    OEM_COMMA = 0xBC,
    OEM_MINUS = 0xBD,
    OEM_PERIOD = 0xBE,
    OEM_2 = 0xBF,
    OEM_3 = 0xC0,
    OEM_4 = 0xDB,
    OEM_5 = 0xDC,
    OEM_6 = 0xDD,
    OEM_7 = 0xDE,
    OEM_8 = 0xDF,
    OEM_102 = 0xE2,
    PROCESSKEY = 0xE5,
    PACKET = 0xE7,
    ATTN = 0xF6,
    CRSEL = 0xF7,
    EXSEL = 0xF8,
    EREOF = 0xF9,
    PLAY = 0xFA,
    ZOOM = 0xFB,
    NONAME = 0xFC,
    PA1 = 0xFD,
    OEM_CLEAR = 0xFE,

    _,

    pub const HANGUL = .KANA;
    pub const KANJI = .HANJA;
};

pub const QS = packed struct(c_uint) {
    KEY: bool = false,
    MOUSEMOVE: bool = false,
    MOUSEBUTTON: bool = false,
    POSTMESSAGE: bool = false,
    TIMER: bool = false,
    PAINT: bool = false,
    SENDMESSAGE: bool = false,
    HOTKEY: bool = false,
    ALLPOSTMESSAGE: bool = false,
    __reserved0__: u1 = 0,
    RAWINPUT: bool = false,
    TOUCH: bool = false,
    POINTER: bool = false,

    __reserved1__: @Int(.unsigned, @bitSizeOf(c_uint) - 13) = 0,

    pub const MOUSE: QS = .{ .MOUSEMOVE = true, .MOUSEBUTTON = true };
    pub const INPUT: QS = .{ .MOUSEMOVE = true, .MOUSEBUTTON = true, .KEY = true, .RAWINPUT = true, .TOUCH = true, .POINTER = true };
    pub const ALLEVENTS = bits.unionOf(QS.INPUT, .{ .POSTMESSAGE = true, .TIMER = true, .PAINT = true, .HOTKEY = true });
    pub const ALLINPUT = bits.unionOf(QS.INPUT, .{ .POSTMESSAGE = true, .TIMER = true, .PAINT = true, .HOTKEY = true, .SENDMESSAGE = true });
};

pub const LARGE_INTEGER = extern union {
    u: extern struct {
        low_part: DWORD,
        high_part: LONG,
    },
    quad_part: u64,
};

pub const POINT = extern struct {
    x: LONG = 0,
    y: LONG = 0,
};

pub const RECT = extern struct {
    left: LONG = 0,
    top: LONG = 0,
    right: LONG = 0,
    bottom: LONG = 0,
};

pub const GUID = extern struct {
    data1: u32 = 0,
    data2: u16 = 0,
    data3: u16 = 0,
    data4: [8]u8 = @splat(0),
};

pub const MMRESULT = enum(UINT) {
    NOERROR = 0,
    ERROR = 1,
    BADDEVICEID = 2,
    NOTENABLED = 3,
    ALLOCATED = 4,
    INVALHANDLE = 5,
    NODRIVER = 6,
    NOMEM = 7,
    NOTSUPPORTED = 8,
    BADERRNUM = 9,
    INVALFLAG = 10,
    INVALPARAM = 11,
    HANDLEBUSY = 12,
    INVALIDALIAS = 13,
    BADDB = 14,
    KEYNOTFOUND = 15,
    READERROR = 16,
    WRITEERROR = 17,
    DELETEERROR = 18,
    VALNOTFOUND = 19,
    NODRIVERCB = 20,
    WAVERR_BADFORMAT = 32,
    WAVERR_STILLPLAYING = 33,
    WAVERR_UNPREPARED = 34,

    TIMERR_BASE = 96,
    TIMERR_NOCANDO = 97,
    TIMERR_STRUCT = 129,

    _,

    pub const TIMERR_NOERROR = .NOERROR;
};

pub inline fn LOWORD(l: anytype) WORD {
    const T = @TypeOf(l);
    comptime {
        const info = @typeInfo(T);
        if (info != .int and info != .comptime_int) @compileError("Expected integer type");
    }

    const UT = @Int(.unsigned, @bitSizeOf(T));
    const i: DWORD = @truncate(@as(UT, @bitCast(l)));
    return @truncate(i & 0xffff);
}

pub inline fn HIWORD(l: anytype) WORD {
    const T = @TypeOf(l);
    comptime {
        const info = @typeInfo(T);
        if (info != .int and info != .comptime_int) @compileError("Expected integer type");
    }
    const UT = @Int(.unsigned, @bitSizeOf(T));
    const i: DWORD = @truncate(@as(UT, @bitCast(l)));
    return @truncate((i & 0xffff0000) >> 16);
}

pub inline fn MAKEINTRESOURCEA(comptime i: anytype) LPCSTR {
    const T = @TypeOf(i);
    const info = @typeInfo(T);
    switch (info) {
        else => @compileError("Expected integer or enum type"),
        .int, .comptime_int => {
            assert(i >= 0 and i <= math.maxInt(usize));
            return @ptrFromInt(i);
        },
        .@"enum" => {
            assert(@sizeOf(T) <= @sizeOf(usize));
            return @ptrFromInt(@intFromEnum(i));
        },
    }
}

pub const MonitorFromFlags = enum(DWORD) {
    DEFAULTTONULL = 0x00000000,
    DEFAULTTOPRIMARY = 0x00000001,
    DEFAULTTONEAREST = 0x00000002,
};

pub const KeyState = packed struct(SHORT) { toggled: bool, __reserved__: u14, down: bool };

pub const MAPVK = enum(UINT) {
    /// The uCode parameter is a virtual-key code and is translated into a scan
    /// code. If it is a virtual-key code that does not distinguish between
    /// left- and right-hand keys, the left-hand scan code is returned.
    /// If there is no translation, the function returns 0.
    VK_TO_VSC = 0,
    /// The uCode parameter is a scan code and is translated into a virtual-key
    /// code that does not distinguish between left- and right-hand keys.
    /// If there is no translation, the function returns 0.
    /// Windows Vista and later: the high byte of the uCode value can contain
    /// either 0xe0 or 0xe1 to specify the extended scan code.
    VSC_TO_VK = 1,
    /// The uCode parameter is a virtual-key code and is translated into an
    /// unshifted character value in the low order word of the return value.
    /// Dead keys (diacritics) are indicated by setting the top bit of the
    /// return value. If there is no translation, the function returns 0. See Remarks.
    VK_TO_CHAR = 2,
    /// The uCode parameter is a scan code and is translated into a virtual-key
    /// code that distinguishes between left- and right-hand keys. If there is
    /// no translation, the function returns 0.
    ///Windows Vista and later: the high byte of the uCode value can contain
    ///either 0xe0 or 0xe1 to specify the extended scan code.
    VSC_TO_VK_EX = 3,
    /// Windows Vista and later: The uCode parameter is a virtual-key code and
    /// is translated into a scan code. If it is a virtual-key code that does
    /// not distinguish between left- and right-hand keys, the left-hand scan
    /// code is returned. If the scan code is an extended scan code, the high
    /// byte of the returned value will contain either 0xe0 or 0xe1 to specify
    /// the extended scan code. If there is no translation, the function returns 0.
    VK_TO_VSC_EX = 4,
};

pub extern "user32" fn AdjustWindowRectEx(rect: *RECT, style: WND.WS, menu: BOOL, ex_style: WND.WS_EX) callconv(.winapi) BOOL;
pub extern "user32" fn BeginPaint(hwnd: HWND, out_paint: *PAINTSTRUCT) callconv(.winapi) HDC;
pub extern "user32" fn CreateWindowExA(ex_style: WND.WS_EX, class_name: ?LPCSTR, window_name: ?LPCSTR, style: WND.WS, x: c_int, y: c_int, width: c_int, height: c_int, parent_window: ?HWND, menu: ?HMENU, instance: ?HINSTANCE, param: ?LPVOID) callconv(.winapi) ?HWND;
pub extern "user32" fn DefWindowProcA(window: HWND, msg: WND.WM, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn DispatchMessageA(msg: *const WND.MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn EndPaint(hwnd: HWND, paint: *const PAINTSTRUCT) callconv(.winapi) BOOL;
pub extern "user32" fn GetClientRect(hwnd: HWND, rect: *RECT) callconv(.winapi) BOOL;
pub extern "user32" fn GetCursorPos(point: *POINT) callconv(.winapi) BOOL;
pub extern "user32" fn GetKeyState(key: VK) callconv(.winapi) KeyState;
pub extern "user32" fn GetModuleHandleA(module_name: ?LPCSTR) callconv(.winapi) HMODULE;
pub extern "user32" fn GetMonitorInfoA(monitor: HMONITOR, out_info: *MONITORINFO) callconv(.winapi) BOOL;
pub extern "user32" fn GetWindowLongA(hwnd: HWND, index: WND.WL) callconv(.winapi) LONG;
pub extern "user32" fn GetWindowPlacement(hwnd: HWND, in_out_placement: *WINDOWPLACEMENT) callconv(.winapi) BOOL;
pub extern "user32" fn LoadCursorA(instance: ?HINSTANCE, cursor_name: LPCSTR) callconv(.winapi) HCURSOR;
pub extern "user32" fn MapVirtualKeyA(code: UINT, map_type: MAPVK) callconv(.winapi) UINT;
pub extern "user32" fn MonitorFromWindow(hwnd: HWND, flags: MonitorFromFlags) callconv(.winapi) HMONITOR;
pub extern "user32" fn PeekMessageA(msg: *WND.MSG, hwnd: ?HWND, msg_filter_min: c_uint, msg_filter_max: c_uint, remove_msg: WND.PM) callconv(.winapi) BOOL;
pub extern "user32" fn RegisterClassA(class: *const WND.CLASS.A) callconv(.winapi) ATOM;
pub extern "user32" fn ScreenToClient(hwnd: HWND, point: *POINT) callconv(.winapi) BOOL;
pub extern "user32" fn SetCursor(cursor: ?HCURSOR) callconv(.winapi) HCURSOR;
pub extern "user32" fn SetWindowLongA(hwnd: HWND, index: WND.WL, new_long: LONG) callconv(.winapi) LONG;
pub extern "user32" fn SetWindowPlacement(hwnd: HWND, placement: *const WINDOWPLACEMENT) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowPos(hwnd: HWND, insert_after: ?HWND, x: c_int, y: c_int, cx: c_int, cy: c_int, flags: WND.SWP) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(msg: *const WND.MSG) callconv(.winapi) BOOL;

pub extern "shcore" fn SetProcessDpiAwareness(value: PROCESS.DPI_AWARENESS) callconv(.winapi) HRESULT;

pub extern "winmm" fn timeBeginPeriod(period_ms: UINT) callconv(.winapi) MMRESULT;

pub const GetDeviceCapsIndex = enum(c_int) {
    DRIVERVERSION = 0,
    TECHNOLOGY = 2,
    HORZSIZE = 4,
    VERTSIZE = 6,
    HORZRES = 8,
    VERTRES = 10,
    BITSPIXEL = 12,
    PLANES = 14,
    NUMBRUSHES = 16,
    NUMPENS = 18,
    NUMMARKERS = 20,
    NUMFONTS = 22,
    NUMCOLORS = 24,
    PDEVICESIZE = 26,
    CURVECAPS = 28,
    LINECAPS = 30,
    POLYGONALCAPS = 32,
    TEXTCAPS = 34,
    CLIPCAPS = 36,
    RASTERCAPS = 38,
    ASPECTX = 40,
    ASPECTY = 42,
    ASPECTXY = 44,
    LOGPIXELSX = 88,
    LOGPIXELSY = 90,
    SIZEPALETTE = 104,
    NUMRESERVED = 106,
    COLORRES = 108,
    PHYSICALWIDTH = 110,
    PHYSICALHEIGHT = 111,
    PHYSICALOFFSETX = 112,
    PHYSICALOFFSETY = 113,
    SCALINGFACTORX = 114,
    SCALINGFACTORY = 115,
    VREFRESH = 116,
    DESKTOPVERTRES = 117,
    DESKTOPHORZRES = 118,
    BLTALIGNMENT = 119,
    SHADEBLENDCAPS = 120,
    COLORMGMTCAPS = 121,
};

pub extern "gdi32" fn GetDC(window: ?HWND) callconv(.winapi) HDC;
pub extern "gdi32" fn GetDeviceCaps(hdc: HDC, index: GetDeviceCapsIndex) callconv(.winapi) c_int;
pub extern "gdi32" fn PatBlt(hdc: ?HDC, x: c_int, y: c_int, w: c_int, h: c_int, rop: ROP) callconv(.winapi) BOOL;
pub extern "gdi32" fn ReleaseDC(window: ?HWND, hdc: HDC) callconv(.winapi) c_int;
pub extern "gdi32" fn StretchDIBits(hdc: HDC, xdest: c_int, ydest: c_int, wdest: c_int, hdest: c_int, xsrc: c_int, ysrc: c_int, wsrc: c_int, hsrc: c_int, bits: *const anyopaque, bits_info: *const BITMAPINFO, usage: DIB_USAGE, rop: ROP) callconv(.winapi) void;

pub const GET_FILEEX_INFO_LEVELS = enum(c_int) {
    standard,
    // max, // standard is the only value valid to use
};

pub const GetFinalPathNameByHandleFlags = packed struct(DWORD) {
    VOLUME_NAME: VolumeName,
    FILE_NAME_OPENED: bool = false,
    __reserved__: u28 = 0,

    pub const VolumeName = enum(u3) { DOS = 0x0, GUID = 0x1, NT = 0x2, NONE = 0x4 };

    pub const FILE_NAME_NORMALIZED = @This(){};
};

pub extern "kernel32" fn GetConsoleWindow() callconv(.winapi) ?HANDLE;
pub extern "kernel32" fn CloseHandle(handle: HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn CopyFileA(existing_file_name: LPCSTR, new_file_name: LPCSTR, fail_if_exists: BOOL) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreateFileA(file_name: LPCSTR, desired_access: ACCESS_MASK, share_mode: FILE.SHARE, security_attributes: ?*SECURITY_ATTRIBUTES, creation_disposition: FILE.Disposition, flags_and_attributes: FILE.FLAGS_AND_ATTRIBUTES, template_file: ?HANDLE) callconv(.winapi) HANDLE;
pub extern "kernel32" fn CreateFileMappingA(file: HANDLE, file_mapping_attributes: ?*SECURITY_ATTRIBUTES, protect: PAGE, maximum_size_high: DWORD, maximum_size_low: DWORD, name: ?LPCSTR) callconv(.winapi) HANDLE;
pub extern "kernel32" fn FreeLibrary(lib_module: HMODULE) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetCurrentDirectoryA(buffer_length: DWORD, buffer: LPCSTR) callconv(.winapi) DWORD;
pub extern "kernel32" fn GetFileAttributesExA(file_name: LPCSTR, info_level_id: GET_FILEEX_INFO_LEVELS, file_info: LPVOID) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetFileSizeEx(handle: HANDLE, out_size: *LARGE_INTEGER) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetFinalPathNameByHandleW(handle: HANDLE, file_path_out: LPWSTR, file_path_len: DWORD, flags: GetFinalPathNameByHandleFlags) callconv(.winapi) DWORD;
pub extern "kernel32" fn GetLastError() callconv(.winapi) ERROR;
pub extern "kernel32" fn GetModuleFileNameA(module: ?HMODULE, file_name: LPSTR, size: DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn GetProcAddress(module: HMODULE, proc_name: LPCSTR) callconv(.winapi) ?FARPROC;
pub extern "kernel32" fn LoadLibraryA(lib_file_name: LPCSTR) callconv(.winapi) ?HMODULE;
pub extern "kernel32" fn MapViewOfFile(file_mapping_object: HANDLE, desired_access: FILE_MAP, file_offset_high: DWORD, file_offset_low: DWORD, number_of_bytes_to_map: SIZE_T) callconv(.winapi) ?LPVOID;
pub extern "kernel32" fn ReadFile(handle: HANDLE, out_buffer: LPVOID, bytes_to_read: DWORD, bytes_read: ?*DWORD, in_out_overlapped: ?*OVERLAPPED) callconv(.winapi) BOOL;
pub extern "kernel32" fn Sleep(milliseconds: DWORD) callconv(.winapi) void;
pub extern "kernel32" fn VirtualAlloc(address: ?LPVOID, size: SIZE_T, allocation_type: MEM.ALLOC, protect: PAGE) callconv(.winapi) ?[*]u8;
pub extern "kernel32" fn VirtualFree(address: [*]const u8, size: SIZE_T, free_type: MEM.FREE) callconv(.winapi) BOOL;
pub extern "kernel32" fn WriteFile(handle: HANDLE, buffer: LPCVOID, bytes_to_write: DWORD, out_bytes_written: ?*DWORD, in_out_overlapped: ?*OVERLAPPED) callconv(.winapi) BOOL;
