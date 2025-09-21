const std = @import("std");
const c_translation = std.zig.c_translation;
const zig_win32 = std.os.windows;

pub const HINSTANCE = zig_win32.HINSTANCE;
pub const HMODULE = zig_win32.HMODULE;
pub const HANDLE = zig_win32.HANDLE;
pub const HRESULT = zig_win32.HRESULT;
pub const HDC = zig_win32.HDC;
pub const HBITMAP = HANDLE;
pub const HGDIOBJ = HANDLE;
pub const PWSTR = zig_win32.PWSTR;
pub const LPBYTE = *BYTE;
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
pub const SHORT = zig_win32.SHORT;
pub const WORD = zig_win32.WORD;
pub const DWORD = zig_win32.DWORD;
pub const LONG = zig_win32.LONG;
pub const SIZE_T = zig_win32.SIZE_T;
pub const LPVOID = zig_win32.LPVOID;
pub const POINT = zig_win32.POINT;
pub const RECT = zig_win32.RECT;
pub const LPRECT = *RECT;

pub const ERROR_SUCCESS = 0x0;
pub const ERROR_DEVICE_NOT_CONNECTED = 0x48f;

pub const MEM_COALESCE_PLACEHOLDERS: DWORD = 0x00000001;
pub const MEM_PRESERVE_PLACEHOLDER: DWORD = 0x00000002;
pub const MEM_COMMIT: DWORD = 0x00001000;
pub const MEM_RESERVE: DWORD = 0x00002000;
pub const MEM_DECOMMIT: DWORD = 0x00004000;
pub const MEM_RELEASE: DWORD = 0x00008000;
pub const MEM_RESET: DWORD = 0x00080000;
pub const MEM_RESET_UNDO: DWORD = 0x1000000;
pub const MEM_LARGE_PAGES: DWORD = 0x20000000;
pub const MEM_PHYSICAL: DWORD = 0x00400000;
pub const MEM_TOP_DOWN: DWORD = 0x00100000;
pub const MEM_WRITE_WATCH: DWORD = 0x00200000;

pub const PAGE_EXECUTE: DWORD = 0x10;
pub const PAGE_EXECUTE_READ: DWORD = 0x20;
pub const PAGE_EXECUTE_READWRITE: DWORD = 0x40;
pub const PAGE_EXECUTE_WRITECOPY: DWORD = 0x80;
pub const PAGE_NOACCESS: DWORD = 0x01;
pub const PAGE_READONLY: DWORD = 0x02;
pub const PAGE_READWRITE: DWORD = 0x04;
pub const PAGE_WRITECOPY: DWORD = 0x08;
pub const PAGE_TARGETS_INVALID: DWORD = 0x40000000;
pub const PAGE_TARGETS_NO_UPDATE: DWORD = 0x40000000;
pub const PAGE_GUARD: DWORD = 0x100;
pub const PAGE_NOCACHE: DWORD = 0x200;
pub const PAGE_WRITECOMBINE: DWORD = 0x400;

pub const QS_KEY: c_uint = 0x0001;
pub const QS_MOUSEMOVE: c_uint = 0x0002;
pub const QS_MOUSEBUTTON: c_uint = 0x0004;
pub const QS_POSTMESSAGE: c_uint = 0x0008;
pub const QS_TIMER: c_uint = 0x0010;
pub const QS_PAINT: c_uint = 0x0020;
pub const QS_SENDMESSAGE: c_uint = 0x0040;
pub const QS_HOTKEY: c_uint = 0x0080;
pub const QS_ALLPOSTMESSAGE: c_uint = 0x0100;
pub const QS_RAWINPUT: c_uint = 0x0400;
pub const QS_TOUCH: c_uint = 0x0800;
pub const QS_POINTER: c_uint = 0x1000;
pub const QS_MOUSE: c_uint = (QS_MOUSEMOVE | QS_MOUSEBUTTON);
pub const QS_INPUT: c_uint = (QS_MOUSE | QS_KEY | QS_RAWINPUT | QS_TOUCH | QS_POINTER);
pub const QS_ALLEVENTS: c_uint = (QS_INPUT | QS_POSTMESSAGE | QS_TIMER | QS_PAINT | QS_HOTKEY);
pub const QS_ALLINPUT: c_uint = (QS_INPUT | QS_POSTMESSAGE | QS_TIMER | QS_PAINT | QS_HOTKEY | QS_SENDMESSAGE);

pub const PM_NOREMOVE: c_uint = 0x0000;
pub const PM_REMOVE: c_uint = 0x0001;
pub const PM_NOYIELD: c_uint = 0x0002;
pub const PM_QS_INPUT: c_uint = (QS_INPUT << 16);
pub const PM_QS_POSTMESSAGE: c_uint = ((QS_POSTMESSAGE | QS_HOTKEY | QS_TIMER) << 16);
pub const PM_QS_PAINT: c_uint = (QS_PAINT << 16);
pub const PM_QS_SENDMESSAGE: c_uint = (QS_SENDMESSAGE << 16);

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

pub const SRCCOPY: DWORD = 0x00CC0020;
pub const SRCPAINT: DWORD = 0x00EE0086;
pub const SRCAND: DWORD = 0x008800C6;
pub const SRCINVERT: DWORD = 0x00660046;
pub const SRCERASE: DWORD = 0x00440328;
pub const NOTSRCCOPY: DWORD = 0x00330008;
pub const NOTSRCERASE: DWORD = 0x001100A6;
pub const MERGECOPY: DWORD = 0x00C000CA;
pub const MERGEPAINT: DWORD = 0x00BB0226;
pub const PATCOPY: DWORD = 0x00F00021;
pub const PATPAINT: DWORD = 0x00FB0A09;
pub const PATINVERT: DWORD = 0x005A0049;
pub const DSTINVERT: DWORD = 0x00550009;
pub const BLACKNESS: DWORD = 0x00000042;
pub const WHITENESS: DWORD = 0x00FF0062;
pub const NOMIRRORBITMAP: DWORD = 0x80000000;
pub const CAPTUREBLT: DWORD = 0x40000000;

pub const VK_LBUTTON: WPARAM = 0x01;
pub const VK_RBUTTON: WPARAM = 0x02;
pub const VK_CANCEL: WPARAM = 0x03;
pub const VK_MBUTTON: WPARAM = 0x04;
pub const VK_XBUTTON1: WPARAM = 0x05;
pub const VK_XBUTTON2: WPARAM = 0x06;
pub const VK_BACK: WPARAM = 0x08;
pub const VK_TAB: WPARAM = 0x09;
pub const VK_CLEAR: WPARAM = 0x0C;
pub const VK_RETURN: WPARAM = 0x0D;
pub const VK_SHIFT: WPARAM = 0x10;
pub const VK_CONTROL: WPARAM = 0x11;
pub const VK_MENU: WPARAM = 0x12;
pub const VK_PAUSE: WPARAM = 0x13;
pub const VK_CAPITAL: WPARAM = 0x14;
pub const VK_KANA: WPARAM = 0x15;
pub const VK_HANGUL: WPARAM = 0x15;
pub const VK_IME_ON: WPARAM = 0x16;
pub const VK_JUNJA: WPARAM = 0x17;
pub const VK_FINAL: WPARAM = 0x18;
pub const VK_HANJA: WPARAM = 0x19;
pub const VK_KANJI: WPARAM = 0x19;
pub const VK_IME_OFF: WPARAM = 0x1A;
pub const VK_ESCAPE: WPARAM = 0x1B;
pub const VK_CONVERT: WPARAM = 0x1C;
pub const VK_NONCONVERT: WPARAM = 0x1D;
pub const VK_ACCEPT: WPARAM = 0x1E;
pub const VK_MODECHANGE: WPARAM = 0x1F;
pub const VK_SPACE: WPARAM = 0x20;
pub const VK_PRIOR: WPARAM = 0x21;
pub const VK_NEXT: WPARAM = 0x22;
pub const VK_END: WPARAM = 0x23;
pub const VK_HOME: WPARAM = 0x24;
pub const VK_LEFT: WPARAM = 0x25;
pub const VK_UP: WPARAM = 0x26;
pub const VK_RIGHT: WPARAM = 0x27;
pub const VK_DOWN: WPARAM = 0x28;
pub const VK_SELECT: WPARAM = 0x29;
pub const VK_PRINT: WPARAM = 0x2A;
pub const VK_EXECUTE: WPARAM = 0x2B;
pub const VK_SNAPSHOT: WPARAM = 0x2C;
pub const VK_INSERT: WPARAM = 0x2D;
pub const VK_DELETE: WPARAM = 0x2E;
pub const VK_HELP: WPARAM = 0x2F;
pub const VK_0: WPARAM = '0';
pub const VK_1: WPARAM = '1';
pub const VK_2: WPARAM = '2';
pub const VK_3: WPARAM = '3';
pub const VK_4: WPARAM = '4';
pub const VK_5: WPARAM = '5';
pub const VK_6: WPARAM = '6';
pub const VK_7: WPARAM = '7';
pub const VK_8: WPARAM = '8';
pub const VK_A: WPARAM = 0x41;
pub const VK_B: WPARAM = 0x42;
pub const VK_C: WPARAM = 0x43;
pub const VK_D: WPARAM = 0x44;
pub const VK_E: WPARAM = 0x45;
pub const VK_F: WPARAM = 0x46;
pub const VK_G: WPARAM = 0x47;
pub const VK_H: WPARAM = 0x48;
pub const VK_I: WPARAM = 0x49;
pub const VK_J: WPARAM = 0x4A;
pub const VK_K: WPARAM = 0x4B;
pub const VK_L: WPARAM = 0x4C;
pub const VK_M: WPARAM = 0x4D;
pub const VK_N: WPARAM = 0x4E;
pub const VK_O: WPARAM = 0x4F;
pub const VK_P: WPARAM = 0x50;
pub const VK_Q: WPARAM = 0x51;
pub const VK_R: WPARAM = 0x52;
pub const VK_S: WPARAM = 0x53;
pub const VK_T: WPARAM = 0x54;
pub const VK_U: WPARAM = 0x55;
pub const VK_V: WPARAM = 0x56;
pub const VK_W: WPARAM = 0x57;
pub const VK_X: WPARAM = 0x58;
pub const VK_Y: WPARAM = 0x59;
pub const VK_Z: WPARAM = 0x5A;
pub const VK_LWIN: WPARAM = 0x5B;
pub const VK_RWIN: WPARAM = 0x5C;
pub const VK_APPS: WPARAM = 0x5D;
pub const VK_SLEEP: WPARAM = 0x5F;
pub const VK_NUMPAD0: WPARAM = 0x60;
pub const VK_NUMPAD1: WPARAM = 0x61;
pub const VK_NUMPAD2: WPARAM = 0x62;
pub const VK_NUMPAD3: WPARAM = 0x63;
pub const VK_NUMPAD4: WPARAM = 0x64;
pub const VK_NUMPAD5: WPARAM = 0x65;
pub const VK_NUMPAD6: WPARAM = 0x66;
pub const VK_NUMPAD7: WPARAM = 0x67;
pub const VK_NUMPAD8: WPARAM = 0x68;
pub const VK_NUMPAD9: WPARAM = 0x69;
pub const VK_MULTIPLY: WPARAM = 0x6A;
pub const VK_ADD: WPARAM = 0x6B;
pub const VK_SEPARATOR: WPARAM = 0x6C;
pub const VK_SUBTRACT: WPARAM = 0x6D;
pub const VK_DECIMAL: WPARAM = 0x6E;
pub const VK_DIVIDE: WPARAM = 0x6F;
pub const VK_F1: WPARAM = 0x70;
pub const VK_F2: WPARAM = 0x71;
pub const VK_F3: WPARAM = 0x72;
pub const VK_F4: WPARAM = 0x73;
pub const VK_F5: WPARAM = 0x74;
pub const VK_F6: WPARAM = 0x75;
pub const VK_F7: WPARAM = 0x76;
pub const VK_F8: WPARAM = 0x77;
pub const VK_F9: WPARAM = 0x78;
pub const VK_F10: WPARAM = 0x79;
pub const VK_F11: WPARAM = 0x7A;
pub const VK_F12: WPARAM = 0x7B;
pub const VK_F13: WPARAM = 0x7C;
pub const VK_F14: WPARAM = 0x7D;
pub const VK_F15: WPARAM = 0x7E;
pub const VK_F16: WPARAM = 0x7F;
pub const VK_F17: WPARAM = 0x80;
pub const VK_F18: WPARAM = 0x81;
pub const VK_F19: WPARAM = 0x82;
pub const VK_F20: WPARAM = 0x83;
pub const VK_F21: WPARAM = 0x84;
pub const VK_F22: WPARAM = 0x85;
pub const VK_F23: WPARAM = 0x86;
pub const VK_F24: WPARAM = 0x87;
pub const VK_NUMLOCK: WPARAM = 0x90;
pub const VK_SCROLL: WPARAM = 0x91;
pub const VK_LSHIFT: WPARAM = 0xA0;
pub const VK_RSHIFT: WPARAM = 0xA1;
pub const VK_LCONTROL: WPARAM = 0xA2;
pub const VK_RCONTROL: WPARAM = 0xA3;
pub const VK_LMENU: WPARAM = 0xA4;
pub const VK_RMENU: WPARAM = 0xA5;
pub const VK_BROWSER_BACK: WPARAM = 0xA6;
pub const VK_BROWSER_FORWARD: WPARAM = 0xA7;
pub const VK_BROWSER_REFRESH: WPARAM = 0xA8;
pub const VK_BROWSER_STOP: WPARAM = 0xA9;
pub const VK_BROWSER_SEARCH: WPARAM = 0xAA;
pub const VK_BROWSER_FAVORITES: WPARAM = 0xAB;
pub const VK_BROWSER_HOME: WPARAM = 0xAC;
pub const VK_VOLUME_MUTE: WPARAM = 0xAD;
pub const VK_VOLUME_DOWN: WPARAM = 0xAE;
pub const VK_VOLUME_UP: WPARAM = 0xAF;
pub const VK_MEDIA_NEXT_TRACK: WPARAM = 0xB0;
pub const VK_MEDIA_PREV_TRACK: WPARAM = 0xB1;
pub const VK_MEDIA_STOP: WPARAM = 0xB2;
pub const VK_MEDIA_PLAY_PAUSE: WPARAM = 0xB3;
pub const VK_LAUNCH_MAIL: WPARAM = 0xB4;
pub const VK_LAUNCH_MEDIA_SELECT: WPARAM = 0xB5;
pub const VK_LAUNCH_APP1: WPARAM = 0xB6;
pub const VK_LAUNCH_APP2: WPARAM = 0xB7;
pub const VK_OEM_1: WPARAM = 0xBA;
pub const VK_OEM_PLUS: WPARAM = 0xBB;
pub const VK_OEM_COMMA: WPARAM = 0xBC;
pub const VK_OEM_MINUS: WPARAM = 0xBD;
pub const VK_OEM_PERIOD: WPARAM = 0xBE;
pub const VK_OEM_2: WPARAM = 0xBF;
pub const VK_OEM_3: WPARAM = 0xC0;
pub const VK_OEM_4: WPARAM = 0xDB;
pub const VK_OEM_5: WPARAM = 0xDC;
pub const VK_OEM_6: WPARAM = 0xDD;
pub const VK_OEM_7: WPARAM = 0xDE;
pub const VK_OEM_8: WPARAM = 0xDF;
pub const VK_OEM_102: WPARAM = 0xE2;
pub const VK_PROCESSKEY: WPARAM = 0xE5;
pub const VK_PACKET: WPARAM = 0xE7;
pub const VK_ATTN: WPARAM = 0xF6;
pub const VK_CRSEL: WPARAM = 0xF7;
pub const VK_EXSEL: WPARAM = 0xF8;
pub const VK_EREOF: WPARAM = 0xF9;
pub const VK_PLAY: WPARAM = 0xFA;
pub const VK_ZOOM: WPARAM = 0xFB;
pub const VK_NONAME: WPARAM = 0xFC;
pub const VK_PA1: WPARAM = 0xFD;
pub const VK_OEM_CLEAR: WPARAM = 0xFE;

pub const DIB_RGB_COLORS: c_int = 0;
pub const DIB_PAL_COLORS: c_int = 1;

pub const BI_RGB: c_int = 0;
pub const BI_RLE8: c_int = 1;
pub const BI_RLE4: c_int = 2;
pub const BI_BITFIELDS: c_int = 3;
pub const BI_JPEG: c_int = 4;
pub const bi_png: c_int = 5;

pub const STRETCH_ANDSCANS = 0x01;
pub const STRETCH_ORSCANS = 0x02;
pub const STRETCH_DELETESCANS = 0x03;
pub const STRETCH_HALFTONE = 0x04;
pub const BLACKONWHITE = STRETCH_ANDSCANS;
pub const COLORONCOLOR = STRETCH_DELETESCANS;
pub const HALFTONE = STRETCH_HALFTONE;
pub const WHITEONBLACK = STRETCH_ORSCANS;

pub const GUID = extern struct {
    data1: u32 = 0,
    data2: u16 = 0,
    data3: u16 = 0,
    data4: [8]u8 = .{0} ** 8,
};

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
    lpReserved: ?LPSTR = null,
    lpDesktop: ?LPSTR = null,
    lpTitle: ?LPSTR = null,
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
    lpReserved2: ?LPBYTE = null,
    hStdInput: ?HANDLE = null,
    hStdOutput: ?HANDLE = null,
    hStdError: ?HANDLE = null,
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

pub const BITMAPINFOHEADER = extern struct {
    biSize: DWORD = @sizeOf(BITMAPINFOHEADER),
    biWidth: LONG = 0,
    biHeight: LONG = 0,
    biPlanes: WORD = 0,
    biBitCount: WORD = 0,
    biCompression: DWORD = 0,
    biSizeImage: DWORD = 0,
    biXPelsPerMeter: LONG = 0,
    biYPelsPerMeter: LONG = 0,
    biClrUsed: DWORD = 0,
    biClrImportant: DWORD = 0,
};

pub const RGBQUAD = extern struct {
    rgbBlue: BYTE = 0,
    rgbGreen: BYTE = 0,
    rgbRed: BYTE = 0,
    rgbReserved: BYTE = 0,
};

pub const BITMAPINFO = extern struct {
    bmiHeader: BITMAPINFOHEADER = .{},
    bmiColors: [1]RGBQUAD = std.mem.zeroes([1]RGBQUAD),
};

pub const LARGE_INTEGER = extern union {
    u: extern struct {
        low_part: DWORD,
        high_part: LONG,
    },
    quad_part: u64,
};

pub const WNDPROC = *const fn (HWND, c_uint, WPARAM, LPARAM) callconv(.winapi) LRESULT;

pub extern "kernel32" fn QueryPerformanceCounter(perf_count: *LARGE_INTEGER) callconv(.winapi) BOOL;
pub extern "kernel32" fn QueryPerformanceFrequency(freq: *LARGE_INTEGER) callconv(.winapi) BOOL;
pub extern "kernel32" fn VirtualAlloc(address: ?LPVOID, size: SIZE_T, allocation_type: DWORD, protect: DWORD) callconv(.winapi) LPVOID;
pub extern "kernel32" fn VirtualFree(address: LPVOID, size: SIZE_T, free_type: DWORD) callconv(.winapi) BOOL;

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
pub extern "user32" fn DestroyWindow(hwnd: HWND) callconv(.c) BOOL;

pub extern "user32" fn GetMessageA(msg: LPMSG, hwnd: ?HWND, msg_filter_min: c_uint, msg_filter_max: c_uint) callconv(.winapi) BOOL;
pub extern "user32" fn GetMessageW(msg: LPMSG, hwnd: ?HWND, msg_filter_min: c_uint, msg_filter_max: c_uint) callconv(.winapi) BOOL;
pub extern "user32" fn PeekMessageA(msg: LPMSG, hwnd: ?HWND, msg_filter_min: c_uint, msg_filter_max: c_uint, remove_msg: c_uint) callconv(.winapi) BOOL;
pub extern "user32" fn PeekMessageW(msg: LPMSG, hwnd: ?HWND, msg_filter_min: c_uint, msg_filter_max: c_uint, remove_msg: c_uint) callconv(.winapi) BOOL;

pub extern "user32" fn TranslateMessage(msg: *const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageA(msg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn DispatchMessageW(msg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn PostQuitMessage(exit_code: c_int) callconv(.winapi) void;

pub extern "user32" fn BeginPaint(hwnd: HWND, paint: *PAINTSTRUCT) callconv(.winapi) HDC;
pub extern "user32" fn EndPaint(hwnd: HWND, paint: *PAINTSTRUCT) callconv(.winapi) BOOL;
pub extern "user32" fn GetClientRect(hwnd: HWND, rect: LPRECT) callconv(.winapi) BOOL;
pub extern "gdi32" fn PatBlt(hdc: ?HDC, x: c_int, y: c_int, w: c_int, h: c_int, rop: DWORD) callconv(.winapi) BOOL;
pub extern "gdi32" fn CreateDIBSection(hdc: ?HDC, bitmap_info: *const BITMAPINFO, usage: c_uint, ppv_bit: **anyopaque, section: ?HANDLE, offset: DWORD) callconv(.winapi) HBITMAP;
pub extern "gdi32" fn StretchDIBits(hdc: HDC, xdest: c_int, ydest: c_int, wdest: c_int, hdest: c_int, xsrc: c_int, ysrc: c_int, wsrc: c_int, hsrc: c_int, bits: *const anyopaque, bits_info: *const BITMAPINFO, usage: c_uint, rop: DWORD) callconv(.winapi) void;
pub extern "gdi32" fn SetStretchBltMode(hdc: HDC, mode: c_int) callconv(.winapi) c_int;
pub extern "gdi32" fn DeleteObject(obj: HGDIOBJ) callconv(.winapi) BOOL;
pub extern "gdi32" fn CreateCompatibleDC(hdc: ?HDC) callconv(.winapi) HDC;
pub extern "gdi32" fn GetDC(window: ?HWND) callconv(.winapi) HDC;
pub extern "gdi32" fn ReleaseDC(window: ?HWND, hdc: HDC) callconv(.winapi) c_int;
