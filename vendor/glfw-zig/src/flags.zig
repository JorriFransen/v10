const glwf = @import("glfw.zig");

pub const Hat = packed struct(u8) {
    centered: bool = false,
    up: bool = false,
    right: bool = false,
    down: bool = false,
    left: bool = false,
    _: u3 = 0,

    pub const right_up = Hat{ .right = true, .up = true };
    pub const right_down = Hat{ .right = true, .down = true };
    pub const left_up = Hat{ .left = true, .up = true };
    pub const left_down = Hat{ .left = true, .down = true };
};

pub const Mod = packed struct(c_int) {
    shift: bool = false,
    control: bool = false,
    alt: bool = false,
    super: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,
    _: u26 = 0,
};
