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

const linux_v10 = @import("linux_v10.zig");

const Joystick = @This();

fd: linux.fd_t,
state: State,
kind: Kind,
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

/// Zero terminated devnode path
dev_path: [std.Io.Dir.max_path_bytes]u8 = @splat(0),

pub const State = enum(u8) {
    inactive,
    sync,
    active,
};

pub const Kind = enum(u8) {
    default,
    xbox,
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

pub fn init(this: *Joystick, io: std.Io, device: *udev.Device, devnode_path: [*:0]const u8) !void {
    const input_dev = udev.device_get_parent_with_subsystem_devtype(device, "input", null).?;
    const parent_syspath = std.mem.span(udev.device_get_syspath(input_dev).?);

    var usb_class: []const u8 = "";
    var usb_subclass: []const u8 = "";
    var usb_protocol: []const u8 = "";

    if (udev.device_get_parent_with_subsystem_devtype(input_dev, "usb", "usb_interface")) |usb_interface_dev| {
        const usb_class_z = udev.device_get_sysattr_value(usb_interface_dev, "bInterfaceClass");
        const usb_subclass_z = udev.device_get_sysattr_value(usb_interface_dev, "bInterfaceSubClass");
        const usb_protocol_z = udev.device_get_sysattr_value(usb_interface_dev, "bInterfaceProtocol");

        if (usb_class_z) |v| usb_class = std.mem.span(v);
        if (usb_subclass_z) |v| usb_subclass = std.mem.span(v);
        if (usb_protocol_z) |v| usb_protocol = std.mem.span(v);
    }

    var driver_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const driver_path_fmt = std.fs.path.fmtJoin(&.{ parent_syspath, "device/driver" });
    const driver_path = try std.fmt.bufPrint(&driver_path_buffer, "{f}", .{driver_path_fmt});

    var driver_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const driver_name_len = try std.Io.Dir.readLinkAbsolute(io, driver_path, &driver_name_buffer);
    const driver_name = std.fs.path.basename(driver_name_buffer[0..driver_name_len]);

    const kind: Kind, var map: Map =
        if (std.mem.eql(u8, driver_name, "xpad") or std.mem.eql(u8, driver_name, "xboxdrv"))
            .{ .xbox, xbox_map }
        else
            .{ .default, default_map };

    // xpad xbox one quirck
    if (std.mem.eql(u8, driver_name, "xpad") and
        std.mem.eql(u8, usb_class, "ff") and
        std.mem.eql(u8, usb_subclass, "47") and
        std.mem.eql(u8, usb_protocol, "d0"))
    {
        map.rumble_max = 0xc9ff;
    }

    const fd = try linux.open(devnode_path, .{ .ACCMODE = .RDWR, .NONBLOCK = true }, 0);
    const open_timestamp = linux_v10.getWallClock(io);

    this.* = .{
        .fd = @intCast(fd),
        .state = .sync,
        .kind = kind,
        .capabilities = .{},
        .map = map,
        .open_timestamp = open_timestamp,
        .sync_report_count = 0,
    };

    const dev_path_z = udev.device_get_devpath(device).?;
    const dev_path = std.mem.span(dev_path_z);
    assert(this.dev_path.len > dev_path.len + 1);
    @memcpy(this.dev_path[0..dev_path.len], dev_path);
    this.dev_path[dev_path.len] = 0;

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

pub fn deinit(this: *Joystick) !void {
    try linux.close(this.fd);

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

/// Returns the devnode path if the device is a joystick, otherwise returns null.
pub fn udevDeviceIsJoystick(ctx: *udev.Udev, device: *udev.Device) ?[*:0]const u8 {
    var result: ?[*:0]const u8 = null;

    var is_keyboard = false;
    var is_mouse = false;

    if (udev.device_get_devnode(device)) |n| {
        const devnode_path = std.mem.span(n);

        if (std.mem.indexOf(u8, devnode_path, "event") != null) {
            if (udev.device_get_property_value(device, "ID_INPUT_JOYSTICK") != null) {
                var sibling_check = false;

                if (udev.device_get_parent_with_subsystem_devtype(device, "usb", null)) |parent| {
                    if (udev.enumerate_new(ctx)) |sibling_enumerator| {
                        defer _ = udev.enumerate_unref(sibling_enumerator);
                        sibling_check = true;

                        _ = udev.enumerate_add_match_subsystem(sibling_enumerator, "input");
                        _ = udev.enumerate_add_match_parent(sibling_enumerator, parent);
                        _ = udev.enumerate_scan_devices(sibling_enumerator);

                        var sibling = udev.enumerate_get_list_entry(sibling_enumerator);
                        while (sibling) |s| {
                            const sib_syspath = udev.list_entry_get_name(s);
                            if (udev.device_new_from_syspath(ctx, sib_syspath)) |sib_dev| {
                                defer _ = udev.device_unref(sib_dev);

                                if (udev.device_get_property_value(sib_dev, "ID_INPUT_KEYBOARD")) |_| {
                                    is_keyboard = true;
                                    break;
                                }

                                if (udev.device_get_property_value(sib_dev, "ID_INPUT_MOUSE")) |_| {
                                    is_mouse = true;
                                    break;
                                }
                            }
                            sibling = udev.list_entry_get_next(s);
                        }
                    }
                }

                if (sibling_check and !is_keyboard and !is_mouse) {
                    result = devnode_path;
                }
            }
        }
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
        if (this.open_timestamp.nanoseconds + (200 * std.time.ns_per_ms) < linux_v10.getWallClock(io).nanoseconds) {
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
