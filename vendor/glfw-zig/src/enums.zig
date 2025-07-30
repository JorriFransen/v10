const std = @import("std");
const glfw = @import("glfw.zig");

pub const InitHint = enum(c_int) {
    platform = glfw.PLATFORM,
    joystick_hat_buttons = glfw.JOYSTICK_HAT_BUTTONS,
    angle_platform_type = glfw.ANGLE_PLATFORM_TYPE,
    cocoa_chdir_resources = glfw.COCOA_CHDIR_RESOURCES,
    cocoa_menubar = glfw.COCOA_MENUBAR,
    wayland_libdecor = glfw.WAYLAND_LIBDECOR,
    x11_cxb_vulkan_surface = glfw.X11_XCB_VULKAN_SURFACE,
};

pub const InitHintValue = enum(c_int) {
    platform_any = glfw.ANY_PLATFORM,
    platform_win32 = glfw.PLATFORM_WIN32,
    platform_cocoa = glfw.PLATFORM_COCOA,
    platform_wayland = glfw.PLATFORM_WAYLAND,
    platform_x11 = glfw.PLATFORM_X11,
    platform_null = glfw.PLATFORM_NULL,
    true = glfw.TRUE,
    false = glfw.FALSE,
    angle_platform_type_none = glfw.ANGLE_PLATFORM_TYPE_NONE,
    angle_platform_type_opengl = glfw.ANGLE_PLATFORM_TYPE_OPENGL,
    angle_platform_type_opengles = glfw.ANGLE_PLATFORM_TYPE_OPENGLES,
    angle_platform_type_d3d9 = glfw.ANGLE_PLATFORM_TYPE_D3D9,
    angle_platform_type_d3d11 = glfw.ANGLE_PLATFORM_TYPE_D3D11,
    angle_platform_type_vulkan = glfw.ANGLE_PLATFORM_TYPE_VULKAN,
    angle_platform_type_metal = glfw.ANGLE_PLATFORM_TYPE_METAL,
};

pub const Platform = enum(c_int) {
    any = glfw.ANY_PLATFORM,
    win32 = glfw.PLATFORM_WIN32,
    cocoa = glfw.PLATFORM_COCOA,
    wayland = glfw.PLATFORM_WAYLAND,
    x11 = glfw.PLATFORM_X11,
    null = glfw.PLATFORM_NULL,

    pub fn initHint(value: Platform) InitHintValue {
        return @enumFromInt(@intFromEnum(value));
    }
};

pub const Action = enum(c_int) {
    release = glfw.RELEASE,
    press = glfw.PRESS,
    repeat = glfw.REPEAT,
};

pub const GamepadAction = enum(u8) {
    press = glfw.PRESS,
    release = glfw.RELEASE,
};

pub const MouseButton = enum(c_int) {
    @"1" = glfw.MOUSE_BUTTON_1,
    @"2" = glfw.MOUSE_BUTTON_2,
    @"3" = glfw.MOUSE_BUTTON_3,
    @"4" = glfw.MOUSE_BUTTON_4,
    @"5" = glfw.MOUSE_BUTTON_5,
    @"6" = glfw.MOUSE_BUTTON_6,
    @"7" = glfw.MOUSE_BUTTON_7,
    @"8" = glfw.MOUSE_BUTTON_8,

    pub const last: c_int = glfw.MOUSE_BUTTON_LAST;
    pub const left: c_int = glfw.MOUSE_BUTTON_1;
    pub const right: c_int = glfw.MOUSE_BUTTON_2;
    pub const middle: c_int = glfw.MOUSE_BUTTON_3;
};

pub const Joystick = enum(c_int) {
    @"1" = glfw.JOYSTICK_1,
    @"2" = glfw.JOYSTICK_2,
    @"3" = glfw.JOYSTICK_3,
    @"4" = glfw.JOYSTICK_4,
    @"5" = glfw.JOYSTICK_5,
    @"6" = glfw.JOYSTICK_6,
    @"7" = glfw.JOYSTICK_7,
    @"8" = glfw.JOYSTICK_8,
    @"9" = glfw.JOYSTICK_9,
    @"10" = glfw.JOYSTICK_10,
    @"11" = glfw.JOYSTICK_11,
    @"12" = glfw.JOYSTICK_12,
    @"13" = glfw.JOYSTICK_13,
    @"14" = glfw.JOYSTICK_14,
    @"15" = glfw.JOYSTICK_15,
    @"16" = glfw.JOYSTICK_16,

    pub const last: c_int = glfw.JOYSTICK_LAST;
};

pub const GamepadButton = enum(c_int) {
    a = glfw.GAMEPAD_BUTTON_A,
    b = glfw.GAMEPAD_BUTTON_B,
    x = glfw.GAMEPAD_BUTTON_X,
    y = glfw.GAMEPAD_BUTTON_Y,
    left_bumper = glfw.GAMEPAD_BUTTON_LEFT_BUMPER,
    right_bumper = glfw.GAMEPAD_BUTTON_RIGHT_BUMPER,
    back = glfw.GAMEPAD_BUTTON_BACK,
    start = glfw.GAMEPAD_BUTTON_START,
    guide = glfw.GAMEPAD_BUTTON_GUIDE,
    left_thumb = glfw.GAMEPAD_BUTTON_LEFT_THUMB,
    right_thumb = glfw.GAMEPAD_BUTTON_RIGHT_THUMB,
    dpad_up = glfw.GAMEPAD_BUTTON_DPAD_UP,
    dpad_right = glfw.GAMEPAD_BUTTON_DPAD_RIGHT,
    dpad_down = glfw.GAMEPAD_BUTTON_DPAD_DOWN,
    dpad_left = glfw.GAMEPAD_BUTTON_DPAD_LEFT,

    pub const last: c_int = glfw.GAMEPAD_BUTTON_LAST;
    pub const cross: c_int = glfw.GAMEPAD_BUTTON_CROSS;
    pub const circle: c_int = glfw.GAMEPAD_BUTTON_CIRCLE;
    pub const square: c_int = glfw.GAMEPAD_BUTTON_SQUARE;
    pub const triangle: c_int = glfw.GAMEPAD_BUTTON_TRIANGLE;
};

pub const GamepadAxis = enum(c_int) {
    left_x = glfw.GAMEPAD_AXIS_LEFT_X,
    left_y = glfw.GAMEPAD_AXIS_LEFT_Y,
    right_x = glfw.GAMEPAD_AXIS_RIGHT_X,
    right_y = glfw.GAMEPAD_AXIS_RIGHT_Y,
    left_trigger = glfw.GAMEPAD_AXIS_LEFT_TRIGGER,
    right_trigger = glfw.GAMEPAD_AXIS_RIGHT_TRIGGER,

    pub const last: c_int = glfw.GAMEPAD_AXIS_LAST;
};

pub const Error = error{
    no_error,
    not_initialized,
    no_current_context,
    invalid_enum,
    invalid_value,
    out_of_memory,
    api_unavailable,
    version_unavailable,
    platform_error,
    format_unavailable,
    no_window_context,
    cursor_unavailable,
    feature_unavailable,
    feature_unimplemented,
    platform_unavailable,
};

pub const ErrorEnum = enum(c_int) {
    no_error = glfw.NO_ERROR,
    not_initialized = glfw.NOT_INITIALIZED,
    no_current_context = glfw.NO_CURRENT_CONTEXT,
    invalid_enum = glfw.INVALID_ENUM,
    invalid_value = glfw.INVALID_VALUE,
    out_of_memory = glfw.OUT_OF_MEMORY,
    api_unavailable = glfw.API_UNAVAILABLE,
    version_unavailable = glfw.VERSION_UNAVAILABLE,
    platform_error = glfw.PLATFORM_ERROR,
    format_unavailable = glfw.FORMAT_UNAVAILABLE,
    no_window_context = glfw.NO_WINDOW_CONTEXT,
    cursor_unavailable = glfw.CURSOR_UNAVAILABLE,
    feature_unavailable = glfw.FEATURE_UNAVAILABLE,
    feature_unimplemented = glfw.FEATURE_UNIMPLEMENTED,
    platform_unavailable = glfw.PLATFORM_UNAVAILABLE,
};

pub const WindowHint = enum(c_int) {
    focused = glfw.FOCUSED,
    iconified = glfw.ICONIFIED,
    resizable = glfw.RESIZABLE,
    visible = glfw.VISIBLE,
    decorated = glfw.DECORATED,
    auto_iconify = glfw.AUTO_ICONIFY,
    floating = glfw.FLOATING,
    maximized = glfw.MAXIMIZED,
    center_cursor = glfw.CENTER_CURSOR,
    transparent_framebuffer = glfw.TRANSPARENT_FRAMEBUFFER,
    hovered = glfw.HOVERED,
    focus_on_show = glfw.FOCUS_ON_SHOW,
    mouse_passthrough = glfw.MOUSE_PASSTHROUGH,
    position_x = glfw.POSITION_X,
    position_y = glfw.POSITION_Y,
    red_bits = glfw.RED_BITS,
    green_bits = glfw.GREEN_BITS,
    blue_bits = glfw.BLUE_BITS,
    alpha_bits = glfw.ALPHA_BITS,
    depth_bits = glfw.DEPTH_BITS,
    stencil_bits = glfw.STENCIL_BITS,
    accum_red_bits = glfw.ACCUM_RED_BITS,
    accum_green_bits = glfw.ACCUM_GREEN_BITS,
    accum_blue_bits = glfw.ACCUM_BLUE_BITS,
    accum_alpha_bits = glfw.ACCUM_ALPHA_BITS,
    aux_buffers = glfw.AUX_BUFFERS,
    stereo = glfw.STEREO,
    samples = glfw.SAMPLES,
    srgb_capable = glfw.SRGB_CAPABLE,
    refresh_rate = glfw.REFRESH_RATE,
    doublebuffer = glfw.DOUBLEBUFFER,
    client_api = glfw.CLIENT_API,
    context_version_major = glfw.CONTEXT_VERSION_MAJOR,
    context_version_minor = glfw.CONTEXT_VERSION_MINOR,
    context_revision = glfw.CONTEXT_REVISION,
    context_robustness = glfw.CONTEXT_ROBUSTNESS,
    opengl_forward_compat = glfw.OPENGL_FORWARD_COMPAT,
    context_debug = glfw.CONTEXT_DEBUG,
    opengl_profile = glfw.OPENGL_PROFILE,
    context_release_behavior = glfw.CONTEXT_RELEASE_BEHAVIOR,
    context_no_error = glfw.CONTEXT_NO_ERROR,
    context_creation_api = glfw.CONTEXT_CREATION_API,
    scale_to_monitor = glfw.SCALE_TO_MONITOR,
    scale_framebuffer = glfw.SCALE_FRAMEBUFFER,
    cocoa_retina_framebuffer = glfw.COCOA_RETINA_FRAMEBUFFER,
    cocoa_frame_name = glfw.COCOA_FRAME_NAME,
    cocoa_graphics_switching = glfw.COCOA_GRAPHICS_SWITCHING,
    x11_class_name = glfw.X11_CLASS_NAME,
    x11_instance_name = glfw.X11_INSTANCE_NAME,
    win32_showdefault = glfw.WIN32_SHOWDEFAULT,
    wayland_app_id = glfw.WAYLAND_APP_ID,

    pub const opengl_debug_context: c_int = glfw.OPENGL_DEBUG_CONTEXT;
};

pub const WindowHintValue = enum(c_int) {
    true = glfw.TRUE,
    false = glfw.FALSE,
    any_position = @as(c_int, @bitCast(glfw.ANY_POSITION)),
    dont_care = glfw.DONT_CARE,
    opengl_api = glfw.OPENGL_API,
    opengl_es_api = glfw.OPENGL_ES_API,
    native_context_api = glfw.NATIVE_CONTEXT_API,
    egl_context_api = glfw.EGL_CONTEXT_API,
    osmesa_context_api = glfw.OSMESA_CONTEXT_API,
    no_reset_notification = glfw.NO_RESET_NOTIFICATION,
    lose_context_on_reset = glfw.LOSE_CONTEXT_ON_RESET,
    release_behaviour_flush = glfw.RELEASE_BEHAVIOR_FLUSH,
    release_behaviour_none = glfw.RELEASE_BEHAVIOR_NONE,
    opengl_compat_profile = glfw.OPENGL_COMPAT_PROFILE,
    opengl_core_profile = glfw.OPENGL_CORE_PROFILE,

    _,

    pub const no_api: WindowHintValue = fromInt(glfw.NO_API);
    pub const no_robustness: WindowHintValue = fromInt(glfw.NO_ROBUSTNESS);
    pub const any_release_behaviour: WindowHintValue = fromInt(glfw.ANY_RELEASE_BEHAVIOR);
    pub const opengl_any_profile: WindowHintValue = fromInt(glfw.OPENGL_ANY_PROFILE);

    pub fn fromInt(int: c_int) WindowHintValue {
        return @enumFromInt(int);
    }
};

pub const CursorShape = enum(c_int) {
    arrow = glfw.ARROW_CURSOR,
    ibeam = glfw.IBEAM_CURSOR,
    crosshair = glfw.CROSSHAIR_CURSOR,
    pointing_hand = glfw.POINTING_HAND_CURSOR,
    resize_ew = glfw.RESIZE_EW_CURSOR,
    resize_ns = glfw.RESIZE_NS_CURSOR,
    resize_nwse = glfw.RESIZE_NWSE_CURSOR,
    resize_nesw = glfw.RESIZE_NESW_CURSOR,
    resize_all = glfw.RESIZE_ALL_CURSOR,

    not_allowed = glfw.NOT_ALLOWED_CURSOR,
    pub const hresize = glfw.RESIZE_EW_CURSOR;
    pub const vresize = glfw.RESIZE_NS_CURSOR;
    pub const hand = glfw.POINTING_HAND_CURSOR;
};

pub const JoystickEvent = enum(c_int) {
    connected = glfw.CONNECTED,
    disconnected = glfw.DISCONNECTED,
};

pub const Key = enum(c_int) {
    unknown = glfw.KEY_UNKNOWN,

    space = glfw.KEY_SPACE,
    /// /* ' */
    apostrophe = glfw.KEY_APOSTROPHE,
    /// /* , */
    comma = glfw.KEY_COMMA,
    /// /* - */
    minus = glfw.KEY_MINUS,
    /// /* . */
    period = glfw.KEY_PERIOD,
    /// /* / */
    slash = glfw.KEY_SLASH,
    @"0" = glfw.KEY_0,
    @"1" = glfw.KEY_1,
    @"2" = glfw.KEY_2,
    @"3" = glfw.KEY_3,
    @"4" = glfw.KEY_4,
    @"5" = glfw.KEY_5,
    @"6" = glfw.KEY_6,
    @"7" = glfw.KEY_7,
    @"8" = glfw.KEY_8,
    @"9" = glfw.KEY_9,
    /// /* ; */
    semicolon = glfw.KEY_SEMICOLON,
    /// /* = */
    equal = glfw.KEY_EQUAL,
    a = glfw.KEY_A,
    b = glfw.KEY_B,
    c = glfw.KEY_C,
    d = glfw.KEY_D,
    e = glfw.KEY_E,
    f = glfw.KEY_F,
    g = glfw.KEY_G,
    h = glfw.KEY_H,
    i = glfw.KEY_I,
    j = glfw.KEY_J,
    k = glfw.KEY_K,
    l = glfw.KEY_L,
    m = glfw.KEY_M,
    n = glfw.KEY_N,
    o = glfw.KEY_O,
    p = glfw.KEY_P,
    q = glfw.KEY_Q,
    r = glfw.KEY_R,
    s = glfw.KEY_S,
    t = glfw.KEY_T,
    u = glfw.KEY_U,
    v = glfw.KEY_V,
    w = glfw.KEY_W,
    x = glfw.KEY_X,
    y = glfw.KEY_Y,
    z = glfw.KEY_Z,
    /// /* [ */
    left_bracket = glfw.KEY_LEFT_BRACKET,
    /// /* \ */
    backslash = glfw.KEY_BACKSLASH,
    /// /* ] */
    right_bracket = glfw.KEY_RIGHT_BRACKET,
    /// /* ` */
    grave_accent = glfw.KEY_GRAVE_ACCENT,
    ////* non-US #1 */
    world_1 = glfw.KEY_WORLD_1,
    ////* non-US #2 */
    world_2 = glfw.KEY_WORLD_2,

    // Function keys
    escape = glfw.KEY_ESCAPE,
    enter = glfw.KEY_ENTER,
    tab = glfw.KEY_TAB,
    backspace = glfw.KEY_BACKSPACE,
    insert = glfw.KEY_INSERT,
    delete = glfw.KEY_DELETE,
    right = glfw.KEY_RIGHT,
    left = glfw.KEY_LEFT,
    down = glfw.KEY_DOWN,
    up = glfw.KEY_UP,
    page_up = glfw.KEY_PAGE_UP,
    page_down = glfw.KEY_PAGE_DOWN,
    home = glfw.KEY_HOME,
    end = glfw.KEY_END,
    caps_lock = glfw.KEY_CAPS_LOCK,
    scroll_lock = glfw.KEY_SCROLL_LOCK,
    num_lock = glfw.KEY_NUM_LOCK,
    print_screen = glfw.KEY_PRINT_SCREEN,
    pause = glfw.KEY_PAUSE,
    f1 = glfw.KEY_F1,
    f2 = glfw.KEY_F2,
    f3 = glfw.KEY_F3,
    f4 = glfw.KEY_F4,
    f5 = glfw.KEY_F5,
    f6 = glfw.KEY_F6,
    f7 = glfw.KEY_F7,
    f8 = glfw.KEY_F8,
    f9 = glfw.KEY_F9,
    f10 = glfw.KEY_F10,
    f11 = glfw.KEY_F11,
    f12 = glfw.KEY_F12,
    f13 = glfw.KEY_F13,
    f14 = glfw.KEY_F14,
    f15 = glfw.KEY_F15,
    f16 = glfw.KEY_F16,
    f17 = glfw.KEY_F17,
    f18 = glfw.KEY_F18,
    f19 = glfw.KEY_F19,
    f20 = glfw.KEY_F20,
    f21 = glfw.KEY_F21,
    f22 = glfw.KEY_F22,
    f23 = glfw.KEY_F23,
    f24 = glfw.KEY_F24,
    f25 = glfw.KEY_F25,
    kp_0 = glfw.KEY_KP_0,
    kp_1 = glfw.KEY_KP_1,
    kp_2 = glfw.KEY_KP_2,
    kp_3 = glfw.KEY_KP_3,
    kp_4 = glfw.KEY_KP_4,
    kp_5 = glfw.KEY_KP_5,
    kp_6 = glfw.KEY_KP_6,
    kp_7 = glfw.KEY_KP_7,
    kp_8 = glfw.KEY_KP_8,
    kp_9 = glfw.KEY_KP_9,
    kp_decimal = glfw.KEY_KP_DECIMAL,
    kp_divide = glfw.KEY_KP_DIVIDE,
    kp_multiply = glfw.KEY_KP_MULTIPLY,
    kp_subtract = glfw.KEY_KP_SUBTRACT,
    kp_add = glfw.KEY_KP_ADD,
    kp_enter = glfw.KEY_KP_ENTER,
    kp_equal = glfw.KEY_KP_EQUAL,
    left_shift = glfw.KEY_LEFT_SHIFT,
    left_control = glfw.KEY_LEFT_CONTROL,
    left_alt = glfw.KEY_LEFT_ALT,
    left_super = glfw.KEY_LEFT_SUPER,
    right_shift = glfw.KEY_RIGHT_SHIFT,
    right_control = glfw.KEY_RIGHT_CONTROL,
    right_alt = glfw.KEY_RIGHT_ALT,
    right_super = glfw.KEY_RIGHT_SUPER,
    menu = glfw.KEY_MENU,

    pub const last: c_int = glfw.KEY_LAST;
};
