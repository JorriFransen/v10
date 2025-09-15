const std = @import("std");
const log = std.log.scoped(.xinput);
const win32 = @import("win32.zig");

const XInput = @This();

pub const XUSER_MAX_COUNT = 4;

pub const STATE = extern struct {
    packet_number: win32.DWORD,
    gamepad: GAMEPAD,
};

pub const GAMEPAD = extern struct {
    buttons: GamepadButtons,
    left_trigger: win32.BYTE,
    right_trigger: win32.BYTE,
    thumb_l_x: win32.SHORT,
    thumb_l_y: win32.SHORT,
    thumb_r_x: win32.SHORT,
    thumb_r_y: win32.SHORT,
};

pub const GamepadButtons = packed struct(win32.DWORD) {
    dpad_up: bool,
    dpad_down: bool,
    dpad_left: bool,
    dpad_right: bool,
    start: bool,
    back: bool,
    left_thumb: bool,
    right_Thumb: bool,
    left_shoulder: bool,
    right_shoulder: bool,
    __reserved0__: u2,
    a: bool,
    b: bool,
    x: bool,
    y: bool,
    __reserved1__: u16,
};

pub const VIBRATION = extern struct {
    left_motor_speed: win32.WORD,
    right_motor_speed: win32.WORD,
};

pub const GAMEPAD_DPAD_UP = 0x0001;
pub const GAMEPAD_DPAD_DOWN = 0x0002;
pub const GAMEPAD_DPAD_LEFT = 0x0004;
pub const GAMEPAD_DPAD_RIGHT = 0x0008;
pub const GAMEPAD_START = 0x0010;
pub const GAMEPAD_BACK = 0x0020;
pub const GAMEPAD_LEFT_THUMB = 0x0040;
pub const GAMEPAD_RIGHT_THUMB = 0x0080;
pub const GAMEPAD_LEFT_SHOULDER = 0x0100;
pub const GAMEPAD_RIGHT_SHOULDER = 0x0200;
pub const GAMEPAD_A = 0x1000;
pub const GAMEPAD_B = 0x2000;
pub const GAMEPAD_X = 0x4000;
pub const GAMEPAD_Y = 0x8000;

pub fn load() void {
    var lib = std.DynLib.open("xinput1_3.dll");
    var loaded = true;

    if (lib) |*l| {
        const struct_info = @typeInfo(XInput).@"struct";
        inline for (struct_info.decls) |decl| {
            const decl_type = @TypeOf(@field(XInput, decl.name));
            const decl_info = @typeInfo(decl_type);

            if (decl_info == .pointer and @typeInfo(decl_info.pointer.child) == .@"fn") {
                @field(XInput, decl.name) = l.lookup(decl_type, decl.name) orelse {
                    l.close();
                    loaded = false;
                    break;
                };
            }
        }
    } else |_| {
        loaded = false;
    }

    if (!loaded) {
        log.debug("Xinput loading failed, returning stubs", .{});
        loadStubs();
    }
}

fn loadStubs() void {
    const struct_info = @typeInfo(XInput).@"struct";
    inline for (struct_info.decls) |decl| {
        const decl_type = @TypeOf(@field(XInput, decl.name));
        const decl_info = @typeInfo(decl_type);

        if (decl_info == .pointer and @typeInfo(decl_info.pointer.child) == .@"fn") {
            @field(XInput, decl.name) = @field(XInput, decl.name ++ "Stub");
        }
    }
}

pub var XInputGetState: *const fn (user_index: win32.DWORD, state: *STATE) callconv(.winapi) win32.DWORD = undefined;
fn XInputGetStateStub(user_index: win32.DWORD, state: *STATE) callconv(.winapi) win32.DWORD {
    _ = user_index;
    _ = state;
    return win32.ERROR_DEVICE_NOT_CONNECTED;
}

pub var XInputSetState: *const fn (user_index: win32.DWORD, vibration: *const VIBRATION) callconv(.winapi) win32.DWORD = undefined;
fn XInputSetStateStub(user_index: win32.DWORD, vibration: *const VIBRATION) callconv(.winapi) win32.DWORD {
    _ = user_index;
    _ = vibration;
    return win32.ERROR_DEVICE_NOT_CONNECTED;
}
