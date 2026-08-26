const std = @import("std");
const log = std.log.scoped(.linux_joystick);

const core = @import("core");
const assert = core.assert;
const linux = core.os.linux;
const math = core.math;
const udev = core.lib.udev;

const ABS = linux.ABS;
const EV = linux.EV;
const FF = linux.FF;
const InputEvent = linux.InputEvent;
const KEY = linux.KEY;
const fd_t = linux.fd_t;

const linux_v10 = @import("linux_v10.zig");

const Joystick = @This();

fd: linux.fd_t,
state: State,
kind: Kind,
id: Id = .{},
capabilities: Capabilities,

axis: [axis_count]f32 = @splat(0),
buttons: Buttons = .empty,

// cached rumble event
rumble_strong: u16 = 0,
rumble_weak: u16 = 0,
rumble_event_id: i16 = -1,

map: Map,
axis_meta: [axis_count]AxisMeta = @splat(.{ .available = false }),

open_timestamp: std.Io.Timestamp,
sync_report_count: u8,

pub const sync_ms_max = 200;

pub const State = enum(u8) {
    inactive,
    sync,
    active,
};

pub const Kind = enum(u8) {
    default,
    xbox,
};

pub const Id = struct {
    buf: [4]u8 = @splat(0),

    pub fn init(event_sub_path: []const u8) Id {
        const id = std.mem.cutPrefix(u8, event_sub_path, "event").?;

        var result: Id = .{};
        @memcpy(result.buf[0..id.len], id);
        return result;
    }

    pub fn eql(a: Id, b: Id) bool {
        const a_u32 = @as(*const u32, @ptrCast(@alignCast(&a.buf))).*;
        const b_u32 = @as(*const u32, @ptrCast(@alignCast(&b.buf))).*;
        return a_u32 == b_u32;
    }

    pub fn format(this: Id, writer: *std.Io.Writer) !void {
        try writer.print("{s}", .{std.mem.span(@as([*:0]const u8, @ptrCast(&this.buf)))});
    }
};

pub const Capabilities = packed struct(u8) {
    axis: bool = false,
    button: bool = false,
    rumble: bool = false,
    __reserved__: u5 = 0,
};

pub const AxisMeta = struct {
    available: bool,
    min: i32 = -1,
    max: i32 = 1,
    deadzone: i32 = 0,
};

pub const axis_count = @typeInfo(Axis).@"enum".fields.len;
pub const Axis = enum {
    left_x,
    left_y,
    left_z,
    right_x,
    right_y,
    right_z,
    dpad_x,
    dpad_y,
};

pub const button_count = @typeInfo(Button).@"enum".fields.len;
pub const Buttons = std.StaticBitSet(button_count);
pub const Button = enum {
    north,
    east,
    south,
    west,
    dpad_up,
    dpad_right,
    dpad_down,
    dpad_left,
    thumb_left,
    thumb_right,
    shoulder_left,
    shoulder_right,
    select,
    start,
    mode,
};

pub const AxisMap = std.enums.EnumFieldStruct(Axis, ABS, null);
pub const ButtonMap = std.enums.EnumFieldStruct(Button, KEY, null);
pub const Map = struct {
    axis: AxisMap,
    buttons: ButtonMap,
    rumble_max: u16 = math.maxInt(u16),
};

pub const default_map = xbox_map;
pub const xbox_map: Map = .{
    .axis = .{
        .left_x = .X,
        .left_y = .Y,
        .left_z = .Z,
        .right_x = .RX,
        .right_y = .RY,
        .right_z = .RZ,
        .dpad_x = .HAT0X,
        .dpad_y = .HAT0Y,
    },
    .buttons = .{
        .north = .BTN_Y,
        .east = .BTN_B,
        .south = .BTN_A,
        .west = .BTN_X,
        .thumb_left = .BTN_THUMBL,
        .thumb_right = .BTN_THUMBR,
        .shoulder_left = .BTN_TL,
        .shoulder_right = .BTN_TR,
        .select = .BTN_SELECT,
        .start = .BTN_START,
        .mode = .BTN_MODE,
        .dpad_up = .RESERVED,
        .dpad_right = .RESERVED,
        .dpad_down = .RESERVED,
        .dpad_left = .RESERVED,
    },
};

pub fn init(this: *Joystick, io: std.Io, id: Id, fd: fd_t, fd_open_ts: std.Io.Timestamp) !void {
    var sys_link_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const sys_link = std.fmt.bufPrint(&sys_link_buf, "{s}{f}", .{
        "/sys/class/input/event",
        id,
    }) catch unreachable;

    var dev_sys_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const dev_sys_path_len = try std.Io.Dir.realPathFileAbsolute(io, sys_link, &dev_sys_path_buf);
    const dev_sys_path = dev_sys_path_buf[0..dev_sys_path_len];

    const usb_iface_sys_path = if (linux.dirnameN(dev_sys_path, 3)) |p| core.stackPathZ(p) else "";

    log.warn("sys_link          : '{s}'", .{sys_link});
    log.warn("dev_sys_path      : '{s}'", .{dev_sys_path});
    log.warn("usb_iface_sys_path: '{s}'", .{usb_iface_sys_path});

    var driver_link_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const driver_link_fmt = std.fs.path.fmtJoin(&.{ std.fs.path.dirname(dev_sys_path).?, "device/driver" });
    const driver_link = std.fmt.bufPrint(&driver_link_buf, "{f}", .{driver_link_fmt}) catch unreachable;

    var driver_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const driver_path_len = try std.Io.Dir.readLinkAbsolute(io, driver_link, &driver_path_buf);
    const driver_path = driver_path_buf[0..driver_path_len];

    const driver_name = std.fs.path.basename(driver_path);

    log.warn("driver link: '{s}'", .{driver_link});
    log.warn("driver path: '{s}'", .{driver_path});
    log.warn("driver name: '{s}'", .{driver_name});

    const kind: Kind, var map: Map =
        if (std.mem.eql(u8, driver_name, "xpad") or std.mem.eql(u8, driver_name, "xboxdrv"))
            .{ .xbox, xbox_map }
        else
            .{ .default, default_map };

    if (linux.open(usb_iface_sys_path, .{ .ACCMODE = .RDONLY }, 0)) |usb_iface_fd| {
        defer linux.close(usb_iface_fd) catch |e| {
            log.warn("Failed to close usb_interface fd: '{s}', error: '{}'", .{ usb_iface_sys_path, e });
        };

        // TODO: These should print a warning, not return hard errors
        if (std.mem.eql(u8, driver_name, "xpad") and
            try sysAttrEql(usb_iface_fd, "bInterfaceClass", "ff") and
            try sysAttrEql(usb_iface_fd, "bInterfaceSubClass", "47") and
            try sysAttrEql(usb_iface_fd, "bInterfaceProtocol", "d0"))
        {
            map.rumble_max = 0xc9ff;
        }
    } else |_| {
        // TODO: Print warning
    }

    this.* = .{
        .fd = @intCast(fd),
        .state = .sync,
        .kind = kind,
        .id = id,
        .capabilities = .{},
        .map = map,
        .open_timestamp = fd_open_ts,
        .sync_report_count = 0,
    };

    const ev_bits: EV.Bitset = linux.ioctl_EVIOCGBIT(this.fd, EV) catch .empty;

    const has_axis = ev_bits.isSet(@intFromEnum(EV.ABS));
    const has_buttons = ev_bits.isSet(@intFromEnum(EV.KEY));

    const has_rumble: bool = if (ev_bits.isSet(@intFromEnum(EV.FF))) blk: {
        const ff_bits: FF.Bitset = linux.ioctl_EVIOCGBIT(this.fd, FF) catch .empty;
        break :blk ff_bits.isSet(@intFromEnum(FF.RUMBLE));
    } else false;

    this.capabilities = .{ .axis = has_axis, .button = has_buttons, .rumble = has_rumble };

    if (has_axis) {
        const abs_bits: ABS.Bitset = linux.ioctl_EVIOCGBIT(fd, ABS) catch .empty;

        inline for (std.meta.fields(Axis)) |field| {
            const axis_idx = field.value;
            const abs: ABS = @field(map.axis, field.name);

            if (abs_bits.isSet(@intFromEnum(abs))) {
                this.axis_meta[axis_idx] = if (linux.ioctl_EVIOCGABS(fd, abs)) |abs_info|
                    .{
                        .available = true,
                        .min = abs_info.minimum,
                        .max = abs_info.maximum,
                        .deadzone = abs_info.flat,
                    }
                else |_|
                    .{ .available = false };
            }
        }
    }
}

fn sysAttrEql(dir_fd: fd_t, attr: [:0]const u8, expect: []const u8) !bool {
    var result = false;

    if (linux.openat(dir_fd, attr, .{ .ACCMODE = .RDONLY }, 0)) |attr_fd| {
        defer linux.close(attr_fd) catch |e| {
            log.warn("Failed to close sysfs attribute fd: '{s}', error: '{}'", .{ attr, e });
        };

        var attr_buf: [16]u8 = @splat(0);
        var attr_value = try linux.read(attr_fd, attr_buf[0 .. attr_buf.len - 1]);
        attr_value.len = @min(attr_value.len, expect.len);

        result = std.mem.eql(u8, expect, attr_value);
    } else |e| {
        log.warn("Failed to open sysfs attribute: '{s}', error: '{}'", .{ attr, e });
    }

    return result;
}

pub fn deinit(this: *Joystick) void {
    linux.close(this.fd) catch |e| {
        log.warn("Failed to close joystick fd: '/dev/input/event{f}', error: '{}'", .{ this.id, e });
    };

    this.* = .{
        .fd = -1,
        .state = .inactive,
        .kind = undefined,
        .map = undefined,
        .capabilities = .{},
        .open_timestamp = .zero,
        .sync_report_count = 0,
    };
}

pub fn eventIsJoystick(fd: fd_t) bool {
    var result = false;

    const ev_bits: EV.Bitset = linux.ioctl_EVIOCGBIT(fd, EV) catch .empty;

    if (ev_bits.isSet(@intFromEnum(EV.ABS)) or
        ev_bits.isSet(@intFromEnum(EV.KEY)))
    {
        const abs_bits: ABS.Bitset = linux.ioctl_EVIOCGBIT(fd, ABS) catch .empty;
        const key_bits: KEY.Bitset = linux.ioctl_EVIOCGBIT(fd, KEY) catch .empty;

        const check_key_bits: KEY.Bitset = comptime blk: {
            var bits: KEY.Bitset = .empty;
            bits.setRangeValue(.{
                .start = @intFromEnum(KEY.BTN_JOYSTICK),
                .end = @intFromEnum(KEY.BTN_THUMBR),
            }, true);
            break :blk bits;
        };

        const has_some_buttons = check_key_bits.intersectWith(key_bits).findFirstSet() != null;

        const has_xy =
            abs_bits.isSet(@intFromEnum(ABS.X)) and
            abs_bits.isSet(@intFromEnum(ABS.Y));

        result = has_some_buttons and has_xy;
    }

    return result;
}

pub inline fn getButtonState(this: *const Joystick, button: Button) bool {
    return this.buttons.isSet(@intFromEnum(button));
}

pub inline fn setButtonState(this: *Joystick, button: Button, state: bool) void {
    this.buttons.setValue(@intFromEnum(button), state);
}

pub fn normalizedAxis(this: *const Joystick, axis: Axis, raw: i32) f32 {
    var result: f32 = 0;

    const meta = &this.axis_meta[@intFromEnum(axis)];

    if (raw < -meta.deadzone or raw > meta.deadzone) {
        const min: f32 = @floatFromInt(meta.min);
        const max: f32 = @floatFromInt(meta.max);
        result = @as(f32, @floatFromInt(raw)) / if (raw < 0) -min else max;
    }

    return result;
}

pub fn update(this: *Joystick, io: std.Io) void {
    if (this.state == .sync) {
        if (this.open_timestamp.nanoseconds + (sync_ms_max * std.time.ns_per_ms) < linux_v10.getWallClock(io).nanoseconds) {
            this.activate();
            assert(this.state == .active);
        }
    }
}

pub fn handleEvent(this: *Joystick, event: *const InputEvent) void {
    switch (event.type) {
        .ABS => {
            const abs: ABS = @enumFromInt(event.code);

            inline for (std.meta.fields(Axis)) |field| {
                const mapped_abs_axis = @field(this.map.axis, field.name);

                if (abs == mapped_abs_axis) {
                    const axis_idx: usize = field.value;
                    const axis = @field(Axis, field.name);

                    const axis_value = this.normalizedAxis(axis, event.value);
                    this.axis[axis_idx] = axis_value;

                    if (axis == .dpad_x) {
                        if (axis_value == 0) {
                            this.setButtonState(.dpad_left, false);
                            this.setButtonState(.dpad_right, false);
                        } else if (axis_value > 0) {
                            this.setButtonState(.dpad_left, false);
                            this.setButtonState(.dpad_right, true);
                        } else {
                            this.setButtonState(.dpad_left, true);
                            this.setButtonState(.dpad_right, false);
                        }
                    } else if (axis == .dpad_y) {
                        if (axis_value == 0) {
                            this.setButtonState(.dpad_up, false);
                            this.setButtonState(.dpad_down, false);
                        } else if (axis_value > 0) {
                            this.setButtonState(.dpad_up, false);
                            this.setButtonState(.dpad_down, true);
                        } else {
                            this.setButtonState(.dpad_up, true);
                            this.setButtonState(.dpad_down, false);
                        }
                    }

                    break;
                }
            }
        },

        .KEY => {
            const key: KEY = @enumFromInt(event.code);

            inline for (std.meta.fields(Button)) |field| {
                const mapped_key: KEY = @field(this.map.buttons, field.name);

                if (key == mapped_key) {
                    const button = @field(Button, field.name);
                    this.setButtonState(button, event.value != 0);
                    break;
                }
            }
        },

        .SYN => {
            const syn: linux.SYN = @enumFromInt(event.code);

            if (syn == .REPORT and this.state == .sync) {
                this.sync_report_count += 1;
            }
        },

        .FF, .MSC, .REL => {}, // ignore
        .FF_STATUS => {}, // ignore for now, reports playback-state changes, could be used to re-trigger or chain events

        else => {},
    }

    if (this.state == .sync and this.sync_report_count >= 2) {
        this.activate();
    }
}

pub fn activate(this: *Joystick) void {
    assert(this.state == .sync);
    this.state = .active;
}

pub fn setRumble(this: *Joystick, strong: f32, weak: f32) !void {
    if (this.capabilities.rumble) {
        assert(this.state == .active);
        assert(this.fd >= 0);

        const strong_u16: u16 = @intFromFloat(math.lerp(0, math.clamp01(strong), this.map.rumble_max));
        const weak_u16: u16 = @intFromFloat(math.lerp(0, math.clamp01(weak), this.map.rumble_max));

        if (strong_u16 != this.rumble_strong or weak_u16 != this.rumble_weak) {
            this.rumble_strong = strong_u16;
            this.rumble_weak = weak_u16;

            if (this.rumble_event_id != -1 and strong_u16 == 0 and weak_u16 == 0) {
                const stop_event = InputEvent{ .type = .FF, .code = @intCast(this.rumble_event_id), .value = 0 };
                const write_len = try linux.write(this.fd, @ptrCast(&stop_event));
                if (write_len != @sizeOf(InputEvent)) return error.EventWriteFailed;

                try linux.ioctl_EVIOCRMFF(this.fd, @intCast(this.rumble_event_id));

                this.rumble_event_id = -1;
            } else {
                var rumble_event = linux.FfEffect{
                    .type = .RUMBLE,
                    .id = this.rumble_event_id,
                    .u = .{ .rumble = .{ .strong_magnitude = this.rumble_strong, .weak_magnitude = this.rumble_weak } },
                    .replay = .{ .length = 0, .delay = 0 },
                };

                try linux.ioctl_EVIOCSFF(this.fd, &rumble_event);
                if (this.rumble_event_id != rumble_event.id) {
                    this.rumble_event_id = rumble_event.id;

                    const play_event = InputEvent{ .type = .FF, .code = @intCast(rumble_event.id), .value = 1 };
                    const write_len = try linux.write(this.fd, @ptrCast(&play_event));
                    if (write_len != @sizeOf(InputEvent)) return error.EventWriteFailed;
                }
            }
        }
    }
}
