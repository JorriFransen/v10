const std = @import("std");
const log = std.log.scoped(.linux_joystick);

const options = @import("options");

const core = @import("core");
const assert = core.assert;
const linux = core.os.linux;
const math = core.math;

const ABS = linux.ABS;
const EV = linux.EV;
const FF = linux.FF;
const InputEvent = linux.InputEvent;
const KEY = linux.KEY;
const fd_t = linux.fd_t;

const linux_v10 = @import("linux_v10.zig");

pub const io_uring_entry_count = 64;
pub var io_uring: std.os.linux.IoUring = undefined;
pub var io_in_flight: [io_uring_entry_count]IoInFlight = @splat(.{ .input_id = -1, .event_id = -1, .event_name = undefined, .event_name_len = 0 });

pub const invalid_id: u32 = math.maxInt(u32);
pub const sync_ms_max = 200;

const IoInFlight = struct {
    input_id: i32 = -1,
    event_id: i11,
    flags: Flags = .{},
    event_name: [10]u8,
    event_name_len: u8,

    pub const Flags = packed struct(u2) {
        retry_pending: bool = false,
        close_on_complete: bool = false,
    };
};

pub const Joystick = struct {
    fd: linux.fd_t,
    state: State,
    kind: Kind,
    input_id: i32 = -1,
    event_id: i11 = -1,
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

    pub const State = enum(u8) {
        inactive,
        wait_settle,
        active,
    };

    pub const Kind = enum(u8) {
        default,
        xbox,
    };

    pub const Capabilities = packed struct(u3) {
        axis: bool = false,
        button: bool = false,
        rumble: bool = false,
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

    pub fn init(this: *Joystick, io: std.Io, event_id: u10, input_id: u31, fd: fd_t, fd_open_ts: std.Io.Timestamp) !void {
        var sys_link_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const sys_link = std.fmt.bufPrint(&sys_link_buf, "/sys/class/input/event{}", .{event_id}) catch unreachable;

        var dev_sys_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const dev_sys_path_len = try std.Io.Dir.realPathFileAbsolute(io, sys_link, &dev_sys_path_buf);
        const dev_sys_path = dev_sys_path_buf[0..dev_sys_path_len];

        const usb_iface_sys_path = if (linux.dirnameN(dev_sys_path, 3)) |p| core.stackPathZ(p) else "";

        log.debug("sys_link          : '{s}'", .{sys_link});
        log.debug("dev_sys_path      : '{s}'", .{dev_sys_path});
        log.debug("usb_iface_sys_path: '{s}'", .{usb_iface_sys_path});

        var driver_link_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const driver_link = std.fmt.bufPrint(&driver_link_buf, "{s}/device/driver", .{
            std.fs.path.dirname(dev_sys_path).?,
        }) catch unreachable;

        var driver_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const driver_path_len = try std.Io.Dir.readLinkAbsolute(io, driver_link, &driver_path_buf);
        const driver_path = driver_path_buf[0..driver_path_len];

        const driver_name = std.fs.path.basename(driver_path);

        log.debug("driver link: '{s}'", .{driver_link});
        log.debug("driver path: '{s}'", .{driver_path});
        log.debug("driver name: '{s}'", .{driver_name});

        const kind: Kind, var map: Map =
            if (std.mem.eql(u8, driver_name, "xpad") or std.mem.eql(u8, driver_name, "xboxdrv"))
                .{ .xbox, xbox_map }
            else
                .{ .default, default_map };

        if (linux.open(usb_iface_sys_path, .{ .ACCMODE = .RDONLY }, 0)) |usb_iface| {
            defer linux.close(usb_iface) catch |e| {
                log.warn("Failed to close usb_interface : '{s}', error: '{}'", .{ usb_iface_sys_path, e });
            };

            if (std.mem.eql(u8, driver_name, "xpad") and
                sysAttrEql(usb_iface, "bInterfaceClass", "ff") and
                sysAttrEql(usb_iface, "bInterfaceSubClass", "47") and
                sysAttrEql(usb_iface, "bInterfaceProtocol", "d0"))
            {
                // xpad/gip quirk: gip controllers expect rumble values 0-100, xpad sends 0-255.
                map.rumble_max = 0xc9ff;
            }
        } else |_| {}

        const ev_bits: EV.BitSet = linux.ioctl_EVIOCGBIT(fd, EV) catch .empty;

        const has_axis = ev_bits.isSet(@intFromEnum(EV.ABS));
        const has_buttons = ev_bits.isSet(@intFromEnum(EV.KEY));

        const has_rumble: bool = if (ev_bits.isSet(@intFromEnum(EV.FF))) blk: {
            const ff_bits: FF.BitSet = linux.ioctl_EVIOCGBIT(fd, FF) catch .empty;
            break :blk ff_bits.isSet(@intFromEnum(FF.RUMBLE));
        } else false;

        this.* = .{
            .fd = @intCast(fd),
            .state = .wait_settle,
            .kind = kind,
            .event_id = event_id,
            .input_id = input_id,
            .capabilities = .{ .axis = has_axis, .button = has_buttons, .rumble = has_rumble },
            .map = map,
            .open_timestamp = fd_open_ts,
            .sync_report_count = 0,
        };

        if (has_axis) {
            const abs_bits: ABS.BitSet = linux.ioctl_EVIOCGBIT(fd, ABS) catch .empty;

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

    pub fn deinit(this: *Joystick) void {
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

    pub fn updateState(this: *Joystick, io: std.Io) void {
        if (this.state == .wait_settle) {
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

                if (syn == .REPORT and this.state == .wait_settle) {
                    this.sync_report_count += 1;
                }
            },

            .FF, .MSC, .REL => {}, // ignore
            .FF_STATUS => {}, // ignore for now, reports playback-state changes, could be used to re-trigger or chain events

            else => {},
        }

        if (this.state == .wait_settle and this.sync_report_count >= 2) {
            this.activate();
        }
    }

    pub fn activate(this: *Joystick) void {
        assert(this.state == .wait_settle);
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
};

pub fn eventFdIsJoystick(fd: fd_t) bool {
    var result = false;

    const ev_bits: EV.BitSet = linux.ioctl_EVIOCGBIT(fd, EV) catch .empty;

    if (ev_bits.isSet(@intFromEnum(EV.ABS)) or
        ev_bits.isSet(@intFromEnum(EV.KEY)))
    {
        const abs_bits: ABS.BitSet = linux.ioctl_EVIOCGBIT(fd, ABS) catch .empty;
        const key_bits: KEY.BitSet = linux.ioctl_EVIOCGBIT(fd, KEY) catch .empty;

        const check_key_bits: KEY.BitSet = comptime blk: {
            var bits: KEY.BitSet = .empty;
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

fn sysAttrEql(dir_fd: fd_t, attr: [:0]const u8, expect: []const u8) bool {
    var result = false;

    if (linux.openat(dir_fd, attr, .{ .ACCMODE = .RDONLY }, 0)) |attr_fd| {
        defer linux.close(attr_fd) catch |e| {
            log.warn("Failed to close sysfs attribute fd: '{s}', error: '{}'", .{ attr, e });
        };

        var attr_buf: [16]u8 = @splat(0);

        if (linux.read(attr_fd, attr_buf[0 .. attr_buf.len - 1])) |attr_value_optional_newline| {
            const attr_value = std.mem.trimEnd(u8, attr_value_optional_newline, "\n");
            result = std.mem.eql(u8, expect, attr_value);
        } else |e| {
            log.warn("Failed to read from attribute fd: '{s}', error: '{}'", .{ attr, e });
        }
    } else |e| switch (e) {
        error.FileDoesNotExist => {},
        else => log.warn("Failed to open sysfs attribute fd: '{s}', error: '{}'", .{ attr, e }),
    }

    return result;
}

pub fn reconcile(io: std.Io, dev_input_dir: *std.Io.Dir) !void {
    var it = dev_input_dir.iterateAssumeFirstIteration();

    while (try it.next(io)) |entry| {
        if (entry.kind == .character_device and std.mem.startsWith(u8, entry.name, "event")) {
            const event_id_str = std.mem.cutPrefix(u8, entry.name, "event").?;
            const event_id = try std.fmt.parseInt(u10, event_id_str, 10);

            try submitOpenFd(io, dev_input_dir.handle, entry.name, event_id);
        }
    }
}

fn newIoInFlightIndex() ?usize {
    var result: ?usize = null;

    for (&io_in_flight, 0..) |*entry, i| {
        if (entry.input_id == -1) {
            result = i;
            break;
        }
    }

    return result;
}

pub fn freeIoInFlightIndex(index: usize) void {
    io_in_flight[index] = .{
        .input_id = -1,
        .event_id = -1,
        .event_name = undefined,
        .event_name_len = 0,
    };
}

pub fn getIoInFlightIndexByEventId(event_id: u10) ?usize {
    var result: ?usize = null;

    for (&io_in_flight, 0..) |*in_flight, i| {
        if (in_flight.event_id == event_id) {
            result = i;
            break;
        }
    }

    return result;
}

pub fn submitOpenFd(io: std.Io, dev_input_dir_fd: linux.dirfd_t, event_name: []const u8, event_id: u10) !void {
    if (newIoInFlightIndex()) |in_flight_index| {
        errdefer freeIoInFlightIndex(in_flight_index);

        const in_flight = &io_in_flight[in_flight_index];
        var sys_link_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const sys_link = std.fmt.bufPrint(&sys_link_buf, "/sys/class/input/{s}", .{event_name}) catch unreachable;

        var dev_sys_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const dev_sys_path_len = std.Io.Dir.realPathFileAbsolute(io, sys_link, &dev_sys_path_buf) catch |e| switch (e) {
            error.FileNotFound => return error.DevSysPathMissing,
            else => return e,
        };

        const dev_sys_path = dev_sys_path_buf[0..dev_sys_path_len];

        const input_num_str_prefixed = std.fs.path.basename(std.fs.path.dirname(dev_sys_path).?);
        const input_num_str = std.mem.cutPrefix(u8, input_num_str_prefixed, "input").?;
        const input_id = try std.fmt.parseInt(u31, input_num_str, 10);

        assert(event_name.len + 1 <= in_flight.event_name.len);
        in_flight.* = .{
            .input_id = input_id,
            .event_id = event_id,
            .event_name_len = @intCast(event_name.len),
            .event_name = @splat(0),
        };
        @memcpy(in_flight.event_name[0..event_name.len], event_name);

        _ = io_uring.openat(
            in_flight_index,
            dev_input_dir_fd,
            in_flight.event_name[0..in_flight.event_name_len :0],
            .{ .ACCMODE = .RDWR, .NONBLOCK = true },
            0,
        ) catch |e| switch (e) {
            error.SubmissionQueueFull => {
                log.err("In flight entries out of sync with submission queue", .{});
                if (options.internal_build) @breakpoint();
            },
        };

        log.debug("Submitted for opening: '/dev/input/{s}'", .{in_flight.event_name});
    } else {
        log.err("Unable to queue open op for potential joystick, out of entries: '/dev/input/{s}'", .{event_name});
    }
}

pub fn submitCloseFd(fd: linux.fd_t) void {
    _ = io_uring.close(@bitCast(@as(isize, -1)), fd) catch unreachable;
}
