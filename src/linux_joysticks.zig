const std = @import("std");
const log = std.log.scoped(.linux_joystick);

const options = @import("options");

const core = @import("core");
const TimeStamp = core.time.TimeStamp;
const assert = core.assert;
const fs = core.fs;
const linux = core.os.linux;
const math = core.math;
const mem = core.mem;

const ABS = linux.ABS;
const EV = linux.EV;
const FF = linux.FF;
const InputEvent = linux.InputEvent;
const KEY = linux.KEY;
const fd_t = linux.fd_t;

const linux_v10 = @import("linux_v10.zig");

const wait_settle_ms_max = 200;

pub const Joystick = struct {
    fd: linux.fd_t,
    state: State,
    kind: Kind,
    event_id: i11 = -1,
    input_id: u31,
    capabilities: Capabilities,

    axis: [axis_count]f32 = @splat(0),
    buttons: Buttons = .empty,

    // cached rumble event
    rumble_strong: u16 = 0,
    rumble_weak: u16 = 0,
    rumble_event_id: i16 = -1,

    map: Map,
    axis_meta: [axis_count]AxisMeta = @splat(.{ .available = false }),

    open_timestamp: TimeStamp,
    sync_report_count: u8,

    const State = enum(u2) {
        inactive,
        wait_settle,
        active,
    };

    const Kind = enum(u1) {
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

    pub const InitError = error{ DevSysPathMissing, ReadlinkFailed };

    fn init(this: *Joystick, sys_class_input_dir_fd: linux.dirfd_t, event_name: [:0]const u8, event_id: i11, input_id: u31, fd: fd_t, fd_open_ts: TimeStamp) InitError!void {
        assert(event_id >= 0);

        var dev_sys_path_rel_buf: [fs.max_path_bytes]u8 = undefined;
        const dev_sys_path_rel_len = linux.readlinkat(sys_class_input_dir_fd, event_name, &dev_sys_path_rel_buf) catch |e| switch (e) {
            error.NOENT => return error.DevSysPathMissing,
            else => {
                log.err("Readlink failed: '/sys/class/input/{s}', error: '{}'", .{ event_name, e });
                return error.ReadlinkFailed;
            },
        };
        const dev_sys_path_rel_link = dev_sys_path_rel_buf[0..dev_sys_path_rel_len];

        log.debug("dev_sys_path_rel_link      : '{s}'", .{dev_sys_path_rel_link});

        var driver_link_rel_buf: [fs.max_path_bytes]u8 = undefined;
        const driver_link_rel = std.fmt.bufPrintSentinel(&driver_link_rel_buf, "{s}/device/driver", .{
            std.fs.path.dirname(dev_sys_path_rel_link).?,
        }, 0) catch unreachable;

        log.debug("driver link rel: '{s}'", .{driver_link_rel});

        const driver_name: []const u8 = blk: {
            var driver_path_buf: [fs.max_path_bytes]u8 = undefined;
            const driver_path_len = linux.readlinkat(sys_class_input_dir_fd, driver_link_rel, &driver_path_buf) catch |e| switch (e) {
                error.NOENT => {
                    log.err("Joystick driver link does not exist: '/sys/class/input/{s}'", .{driver_link_rel});
                    break :blk "";
                },
                else => {
                    log.err("Readlink failed: '/sys/class/input/{s}', error: '{}'", .{ event_name, e });
                    return error.ReadlinkFailed;
                },
            };

            const driver_path = driver_path_buf[0..driver_path_len];
            log.debug("driver path    : '{s}'", .{driver_path});
            break :blk if (driver_path_len > 0) std.fs.path.basename(driver_path) else "";
        };

        log.debug("driver name    : '{s}'", .{driver_name});

        const kind: Kind, var map: Map =
            if (std.mem.eql(u8, driver_name, "xpad") or std.mem.eql(u8, driver_name, "xboxdrv"))
                .{ .xbox, xbox_map }
            else
                .{ .default, default_map };

        const usb_iface_sys_path_rel_link = if (fs.dirnameN(dev_sys_path_rel_link, 3)) |p| fs.stackPathZ(p) else "";

        log.debug("usb_iface_sys_path_rel_link: '{s}'", .{usb_iface_sys_path_rel_link});

        if (linux.openat(sys_class_input_dir_fd, usb_iface_sys_path_rel_link, .{ .DIRECTORY = true, .CLOEXEC = true }, 0)) |usb_iface| {
            defer linux.close(usb_iface);

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

    fn deinit(this: *Joystick) void {
        this.* = .{
            .fd = -1,
            .state = .inactive,
            .kind = undefined,
            .event_id = -1,
            .input_id = undefined,
            .map = undefined,
            .capabilities = .{},
            .open_timestamp = .zero,
            .sync_report_count = 0,
        };
    }

    fn updateState(this: *Joystick) void {
        if (this.state == .wait_settle) {
            if (this.open_timestamp.ns() + (wait_settle_ms_max * std.time.ns_per_ms) < TimeStamp.now(.monotonic).ns()) {
                this.activate();
                assert(this.state == .active);
            }
        }
    }

    fn handleEvent(this: *Joystick, event: *const InputEvent) void {
        switch (event.type) {
            .ABS => {
                inline for (std.meta.fields(Axis)) |field| {
                    const mapped_abs_axis = @field(this.map.axis, field.name);

                    if (event.code == @intFromEnum(mapped_abs_axis)) {
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
                inline for (std.meta.fields(Button)) |field| {
                    const mapped_key: KEY = @field(this.map.buttons, field.name);

                    if (event.code == @intFromEnum(mapped_key)) {
                        const button = @field(Button, field.name);
                        this.setButtonState(button, event.value != 0);
                        break;
                    }
                }
            },

            .SYN => {
                if (event.code == @intFromEnum(linux.SYN.REPORT) and this.state == .wait_settle) {
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

    fn activate(this: *Joystick) void {
        assert(this.state == .wait_settle);
        this.state = .active;

        // Query current state - this is technically only required if this joystick has been in the ready_list before init.

        if (this.capabilities.button) {
            const key_bits: KEY.BitSet = linux.ioctl_EVIOCGKEY(this.fd) catch .empty;

            inline for (std.meta.fields(Button)) |field| {
                const button: Button = @enumFromInt(field.value);
                const mapped_key: KEY = @field(this.map.buttons, field.name);

                this.setButtonState(button, key_bits.isSet(@intFromEnum(mapped_key)));
            }
        }

        if (this.capabilities.axis) {
            const abs_bits: ABS.BitSet = linux.ioctl_EVIOCGBIT(this.fd, ABS) catch .empty;

            inline for (std.meta.fields(Axis)) |field| {
                const axis: Axis = @enumFromInt(field.value);
                const mapped_abs: ABS = @field(this.map.axis, field.name);

                this.axis[field.value] = if (abs_bits.isSet(@intFromEnum(mapped_abs)))
                    if (linux.ioctl_EVIOCGABS(this.fd, mapped_abs)) |abs_info|
                        this.normalizedAxis(axis, abs_info.value)
                    else |_|
                        0
                else
                    0;
            }
        }

        log.info("Joystick activated: '/dev/input/event{}'", .{this.event_id});
    }

    pub const SetRumbleError = error{ EventWriteFailed, IoctlFailed };

    pub fn setRumble(this: *Joystick, strong: f32, weak: f32) SetRumbleError!void {
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
                    const write_len = linux.write(this.fd, @ptrCast(&stop_event)) catch |e| {
                        log.err("Rumble stop event write failed, error: '{}'", .{e});
                        return error.EventWriteFailed;
                    };
                    if (write_len != @sizeOf(InputEvent)) {
                        log.err("Rumble stop event write invalid write length, expected: {}, got: {}", .{ @sizeOf(InputEvent), write_len });
                        return error.EventWriteFailed;
                    }

                    linux.ioctl_EVIOCRMFF(this.fd, @intCast(this.rumble_event_id)) catch |e| {
                        log.err("Rumble ioctl EVIOCRMFF failed, error: '{}'", .{e});
                        return error.IoctlFailed;
                    };

                    this.rumble_event_id = -1;
                } else {
                    var rumble_event = linux.FfEffect{
                        .type = .RUMBLE,
                        .id = this.rumble_event_id,
                        .u = .{ .rumble = .{ .strong_magnitude = this.rumble_strong, .weak_magnitude = this.rumble_weak } },
                        .replay = .{ .length = 0, .delay = 0 },
                    };

                    linux.ioctl_EVIOCSFF(this.fd, &rumble_event) catch |e| {
                        log.err("Rumble ioctl EVIOCSFF failed, error: '{}'", .{e});
                        return error.IoctlFailed;
                    };

                    if (this.rumble_event_id != rumble_event.id) {
                        this.rumble_event_id = rumble_event.id;

                        const play_event = InputEvent{ .type = .FF, .code = @intCast(rumble_event.id), .value = 1 };
                        const write_len = linux.write(this.fd, @ptrCast(&play_event)) catch |e| {
                            log.err("Rumble start event write failed, error: '{}'", .{e});
                            return error.EventWriteFailed;
                        };

                        if (write_len != @sizeOf(InputEvent)) {
                            log.err("Rumble start event write invalid write length, expected: {}, got: {}", .{ @sizeOf(InputEvent), write_len });
                            return error.EventWriteFailed;
                        }
                    }
                }
            }
        }
    }

    pub inline fn getButtonState(this: *const Joystick, button: Button) bool {
        return this.buttons.isSet(@intFromEnum(button));
    }

    inline fn setButtonState(this: *Joystick, button: Button, state: bool) void {
        this.buttons.setValue(@intFromEnum(button), state);
    }

    fn normalizedAxis(this: *const Joystick, axis: Axis, raw: i32) f32 {
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

pub fn System(comptime joystick_count: usize) type {
    return struct {
        const Context = @This();

        const joystick_slot_count = joystick_count;
        const io_uring_entry_count = joystick_count * 32;
        const inotify_pollfd_idx = 0;
        const first_joystick_pollfd_idx = 1;

        dev_input_dir_fd: linux.dirfd_t,
        sys_class_input_dir_fd: linux.dirfd_t,

        joysticks: [joystick_slot_count]Joystick = @splat(.{
            .fd = -1,
            .state = .inactive,
            .kind = undefined,
            .input_id = undefined,
            .capabilities = .{},
            .map = undefined,
            .open_timestamp = .zero,
            .sync_report_count = 0,
        }),

        inotify_fd: linux.fd_t,
        inotify_wd: c_int,

        wait_que: [joystick_count * 8]WaitQueueEntry = undefined,
        wait_que_len: usize = 0,

        poll_fds: [joystick_slot_count + first_joystick_pollfd_idx]linux.pollfd = @splat(.{
            .fd = -1,
            .events = undefined,
            .revents = undefined,
        }),

        io_uring: std.os.linux.IoUring,
        io_in_flight_count: u32 = 0,
        io_open_in_flight: [io_uring_entry_count]IoOpenInFlight = @splat(.{
            .event_id = -1,
            .input_id = undefined,
            ._event_name = undefined,
            .event_name_len = 0,
        }),

        pub const InitError = error{ OpenFailed, IoUringInitFailed, InotifyInitFailed, InotifyWatchFailed };

        pub fn init() InitError!Context {
            var result: Context = .{
                .dev_input_dir_fd = -1,
                .sys_class_input_dir_fd = -1,
                .inotify_fd = -1,
                .inotify_wd = -1,
                .io_uring = undefined,
            };

            result.dev_input_dir_fd = linux.open("/dev/input", .{ .DIRECTORY = true, .CLOEXEC = true }, 0) catch |e| {
                log.err("Failed to open '/dev/input', error: '{}'", .{e});
                return error.OpenFailed;
            };
            errdefer linux.close(result.dev_input_dir_fd);

            result.sys_class_input_dir_fd = linux.open("/sys/class/input", .{ .DIRECTORY = true, .CLOEXEC = true }, 0) catch |e| {
                log.err("Failed to open '/sys/class/input', error: '{}'", .{e});
                return error.OpenFailed;
            };
            errdefer linux.close(result.sys_class_input_dir_fd);

            result.io_uring = std.os.linux.IoUring.init(io_uring_entry_count, 0) catch |e| {
                log.err("IO Uring init failed, error: '{}'", .{e});
                return error.IoUringInitFailed;
            };
            errdefer result.io_uring.deinit();

            result.reconcile() catch |e| {
                log.err("Joystick initial scan (reconcile) failed, error: '{}'", .{e});
            };

            _ = result.io_uring.submit() catch |e| {
                log.err("io_uring submit failed, error: '{}'", .{e});
            };
            result.inotify_fd = linux.inotify_init1(.{ .CLOEXEC = true, .NONBLOCK = true }) catch |e| {
                log.err("Failed to open inotify fd, error: '{}'", .{e});
                return error.InotifyInitFailed;
            };
            errdefer linux.close(result.inotify_fd);

            result.inotify_wd = linux.inotify_add_watch(
                result.inotify_fd,
                "/dev/input",
                .{ .CREATE = true, .ATTRIB = true, .MOVED_FROM = true, .MOVED_TO = true, .DELETE = true },
            ) catch |e| {
                log.err("Failed to add inotify watch '/dev/input', error: '{}'", .{e});
                return error.InotifyWatchFailed;
            };
            errdefer linux.inotify_rm_watch(result.inotify_fd, result.inotify_wd) catch |e| {
                log.err("Failed to remove inotify watch '/dev/input', error: '{}'", .{e});
            };

            result.poll_fds[0] = .{ .fd = result.inotify_fd, .events = .{ .IN = true }, .revents = undefined };

            return result;
        }

        pub fn deinit(this: *Context) void {
            linux.close(this.dev_input_dir_fd);
            this.dev_input_dir_fd = -1;

            linux.close(this.sys_class_input_dir_fd);
            this.sys_class_input_dir_fd = -1;

            this.flushIoUring();
            this.io_uring.deinit();

            _ = linux.inotify_rm_watch(this.inotify_fd, this.inotify_wd) catch |e| {
                log.err("Failed to remove inotify watch '/dev/input', error: '{}'", .{e});
            };
            this.inotify_wd = -1;

            linux.close(this.inotify_fd);
            this.inotify_fd = -1;
        }

        pub fn update(this: *Context) void {
            var cqes: [io_uring_entry_count]std.os.linux.io_uring_cqe = undefined;
            while (true) {
                const n = this.io_uring.copy_cqes(&cqes, 0) catch break;
                if (n == 0) break;

                this.io_in_flight_count -= n;

                for (cqes[0..n]) |cqe| {
                    const user_data: isize = @bitCast(cqe.user_data);

                    if (user_data >= 0) {
                        const in_flight_index: usize = @intCast(user_data);

                        const in_flight = &this.io_open_in_flight[in_flight_index];
                        const event_name = in_flight.eventName();

                        const err = cqe.err();
                        if (err == .SUCCESS) {
                            log.debug("uring finished opening: '/dev/input/{s}'", .{event_name});

                            const open_ts = TimeStamp.now(.monotonic);
                            const fd: linux.fd_t = cqe.res;

                            if (in_flight.flags.close_on_complete or
                                this.eventIdMatchesRegisteredOrWaiting(in_flight.event_id) or !eventFdIsJoystick(fd))
                            {
                                _ = this.submitCloseFd(fd);
                            } else {
                                if (!(this.register(
                                    in_flight.eventName(),
                                    in_flight.event_id,
                                    in_flight.input_id,
                                    fd,
                                    open_ts,
                                ) catch |e| blk: {
                                    _ = this.submitCloseFd(fd);
                                    log.err("Failed to add joystick '/dev/input/{s}', error: '{}'", .{ event_name, e });
                                    break :blk false;
                                })) {
                                    if (!this.waitQueuePush(.{
                                        .fd = fd,
                                        .fd_open_ts = open_ts,
                                        .event_id = @intCast(in_flight.event_id),
                                        .input_id = in_flight.input_id,
                                    })) {
                                        _ = this.submitCloseFd(fd);
                                        log.err("Out of joystick slots, dropping '/dev/input/{s}", .{in_flight._event_name});
                                    }
                                }
                            }
                        } else {
                            if (err == .ACCES and in_flight.flags.retry_pending and !in_flight.flags.close_on_complete) {
                                in_flight.flags.retry_pending = false;

                                log.debug("Open failed, retry: '/dev/input/{s}', error: '{}'", .{ event_name, err });

                                this.submitOpenFd(event_name, in_flight.event_id) catch |e| {
                                    log.err("Failed to submit joystick for open: '/dev/input/{s}', error: '{}'", .{ event_name, e });
                                };
                            } else {
                                log.debug("Open failed: '/dev/input/{s}', error: '{}'", .{ event_name, err });
                            }
                        }

                        this.freeIoInFlightIndex(in_flight_index);
                    } else {
                        log.debug("uring finished closing, result: {}, error: {}", .{ cqe.res, cqe.err() });
                        // close, ignore
                    }
                }
            }

            const poll_rc: c_int = linux.poll(&this.poll_fds, 0) catch |e| blk: {
                switch (e) {
                    error.INTR => {},
                    else => log.err("Poll failed, error: '{}'", .{e}),
                }
                break :blk 0;
            };

            if (poll_rc > 0) for (&this.poll_fds, 0..) |*pollfd, pollfd_idx| {
                if (@as(u16, @bitCast(pollfd.revents)) == 0) continue;

                if (pollfd_idx == inotify_pollfd_idx) {
                    if (pollfd.revents.IN) {
                        const buf_len = 16 * (@sizeOf(linux.InotifyEvent) + linux.NAME_MAX + 1);
                        var buf: [buf_len]u8 align(@alignOf(linux.InotifyEvent)) = undefined;

                        while (linux.read(this.inotify_fd, &buf)) |bytes_read| {
                            var i: usize = 0;
                            while (i < bytes_read.len) {
                                const rem = bytes_read[i..];
                                assert(rem.len >= @sizeOf(linux.InotifyEvent));

                                const event: *const linux.InotifyEvent = @ptrCast(@alignCast(rem.ptr));
                                i += @sizeOf(linux.InotifyEvent) + event.len;

                                if (event.mask.Q_OVERFLOW) {
                                    this.reconcile() catch |e| {
                                        log.err("reconcile after Q_OVERFLOW failed, error: '{}'", .{e});
                                        continue;
                                    };
                                }

                                if (event.wd != this.inotify_wd) continue;
                                if (event.len == 0) continue;

                                assert(rem.len - @sizeOf(linux.InotifyEvent) >= event.len);
                                if (rem.len - @sizeOf(linux.InotifyEvent) >= event.len) {
                                    const event_num_str = std.mem.cutPrefix(u8, event.name(), "event") orelse continue;
                                    const event_id = std.fmt.parseInt(u10, event_num_str, 10) catch continue;

                                    if (event.mask.CREATE or event.mask.MOVED_TO or event.mask.ATTRIB) {
                                        log.debug("inotyfy add mask: {}", .{event.mask});
                                        if (this.eventIdMatchesRegisteredOrWaiting(event_id)) {
                                            // skip
                                        } else if (this.getIoInFlightIndexByEventId(event_id)) |in_flight_index| {
                                            this.io_open_in_flight[in_flight_index].flags.retry_pending = true;
                                            log.debug("already in flight, allow retry: '/dev/input/event{}'", .{event_id});
                                        } else {
                                            this.submitOpenFd(event.name(), event_id) catch |e| {
                                                const report = switch (e) {
                                                    error.DevSysPathMissing => !event.mask.ATTRIB,
                                                    else => true,
                                                };

                                                if (report) {
                                                    log.err("Failed to submit potential joystick for io_uring open: '/dev/input/{s}', error: '{}'", .{ event.name(), e });
                                                }
                                            };
                                        }
                                    } else if (event.mask.DELETE or event.mask.MOVED_FROM) {
                                        if (this.unregister(event_id)) |fd| {
                                            _ = this.submitCloseFd(fd);
                                        }
                                    }
                                }
                            }
                        } else |e| switch (e) {
                            error.AGAIN => {},
                            else => log.err("Failed to read inotify events, error: '{}'", .{e}),
                        }
                    }

                    if (pollfd.revents.ERR or pollfd.revents.HUP or pollfd.revents.NVAL) {
                        log.err("inotify poll error: revents: {}", .{pollfd.revents});
                    }
                } else {
                    assert(pollfd_idx >= first_joystick_pollfd_idx);
                    assert(pollfd_idx < (joystick_count + first_joystick_pollfd_idx));

                    if (pollfd.fd < 0) continue;

                    const jid = pollfd_idx - first_joystick_pollfd_idx;
                    if (this.joysticks[jid].state == .inactive) continue;

                    if (pollfd.revents.IN) {
                        var events: [16]linux.InputEvent = undefined;
                        while (linux.read(pollfd.fd, std.mem.sliceAsBytes(&events))) |bytes_read| {
                            const num_events = bytes_read.len / @sizeOf(linux.InputEvent);
                            for (events[0..num_events]) |*event| {
                                const joystick = &this.joysticks[jid];
                                joystick.handleEvent(event);
                            }
                        } else |e| switch (e) {
                            error.AGAIN => {},
                            else => log.err("Failed to read joystick events, jid: {}, error: '{}'", .{ jid, e }),
                        }
                    }

                    if (pollfd.revents.ERR or pollfd.revents.HUP or pollfd.revents.NVAL) {
                        log.err("joystick poll error: revents: {}", .{pollfd.revents});
                    }
                }
            };

            _ = this.io_uring.submit() catch |e| {
                log.err("io_uring submit failed, error: '{}'", .{e});
            };

            for (&this.joysticks) |*js| {
                js.updateState();
            }
        }

        fn flushIoUring(this: *Context) void {
            for (&this.joysticks, 0..) |*js, ji| if (js.state != .inactive) {
                _ = this.submitCloseFd(js.fd);
                this.unregisterFromSlot(ji);
            };

            for (this.wait_que[0..this.wait_que_len]) |*entry| {
                _ = this.submitCloseFd(entry.fd);
            }
            this.wait_que_len = 0;

            _ = this.io_uring.submit() catch |e| {
                log.err("io_uring submit failed, error: '{}'", .{e});
            };

            var cqes: [io_uring_entry_count]std.os.linux.io_uring_cqe = undefined;
            while (this.io_in_flight_count > 0) {
                const n = this.io_uring.copy_cqes(&cqes, this.io_in_flight_count) catch break;
                if (n == 0) break;

                this.io_in_flight_count -= n;

                var closes_submitted: u32 = 0;

                for (cqes[0..n]) |cqe| {
                    const user_data: isize = @bitCast(cqe.user_data);

                    const err = cqe.err();

                    if (user_data >= 0) {
                        // open completed

                        const in_flight_index: usize = @intCast(user_data);

                        const in_flight = &this.io_open_in_flight[in_flight_index];
                        const event_name = in_flight.eventName();

                        if (err != .SUCCESS) {
                            log.err("io_uring fd open failed: '/dev/input/{s}', error: '{}'", .{ event_name, err });
                        } else {
                            const fd: linux.fd_t = cqe.res;
                            if (this.submitCloseFd(fd)) {
                                closes_submitted += 1;
                            }
                        }
                    } else {
                        // close completed
                        if (err != .SUCCESS) {
                            log.err("io_uring joystick fd close failed, error: '{}'", .{err});
                        }
                    }
                }

                if (closes_submitted > 0) {
                    _ = this.io_uring.submit() catch |e| {
                        log.err("io_uring submit failed, error: '{}'", .{e});
                    };
                }
            }
        }

        fn reconcile(this: *Context) fs.DirIterator.Error!void {
            const PresentDevice = struct {
                input_id: u31,
                event_id: u10,
                event_name_buf: [10]u8,
                event_name_len: u8,
            };

            var sys_path_rel_buf: [fs.max_path_bytes]u8 = undefined;

            var present: [io_uring_entry_count]PresentDevice = undefined;
            var present_len: usize = 0;

            var it = try fs.DirIterator.init(.{ .handle = this.dev_input_dir_fd }, .{});

            while (try it.next()) |entry| {
                if (entry.type != .char) continue;

                const event_id_str = std.mem.cutPrefix(u8, entry.name, "event") orelse continue;
                const event_id = std.fmt.parseInt(u10, event_id_str, 10) catch continue;

                const sys_path_rel_len = linux.readlinkat(this.sys_class_input_dir_fd, entry.name, &sys_path_rel_buf) catch |e| {
                    switch (e) {
                        error.NOTDIR, error.BADF => unreachable,
                        else => log.err("reconcile readlink failed on: '/sys/class/input/{s}', error: '{}'", .{ entry.name, e }),
                    }
                    continue;
                };
                const sys_path_rel_sys_link = sys_path_rel_buf[0..sys_path_rel_len];

                const sys_path_dirname_rel_sys_link = std.fs.path.dirname(sys_path_rel_sys_link) orelse continue;
                const input_id_str = std.mem.cutPrefix(u8, std.fs.path.basename(sys_path_dirname_rel_sys_link), "input") orelse continue;
                const input_id = std.fmt.parseInt(u31, input_id_str, 10) catch continue;

                if (present_len < present.len) {
                    const p = &present[present_len];
                    present_len += 1;
                    assert(entry.name.len + 1 <= p.event_name_buf.len);

                    p.* = .{
                        .input_id = input_id,
                        .event_id = event_id,
                        .event_name_buf = @splat(0),
                        .event_name_len = @intCast(entry.name.len),
                    };

                    @memcpy(p.event_name_buf[0..entry.name.len], entry.name);
                } else {
                    log.err("reconcile overflow (>{}), dropping: '/dev/input/{s}' and additional entries", .{ present.len, entry.name });
                    continue;
                }
            }

            for (&this.joysticks, 0..) |*js, ji| if (js.state != .inactive) {
                var found = false;
                for (present[0..present_len]) |*p| {
                    if (js.input_id == p.input_id) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    _ = this.submitCloseFd(js.fd);
                    this.unregisterFromSlot(ji);
                }
            };

            {
                var qi: usize = 0;
                while (qi < this.wait_que_len) {
                    const ready_entry = &this.wait_que[qi];

                    var found = false;
                    for (present[0..present_len]) |*p| {
                        if (ready_entry.input_id == p.input_id) {
                            found = true;
                            break;
                        }
                    }

                    if (found) {
                        qi += 1;
                    } else {
                        _ = this.submitCloseFd(ready_entry.fd);
                        this.waitQueueOrderedRemove(qi);
                    }
                }
            }

            for (&this.io_open_in_flight) |*in_flight| if (in_flight.event_id != -1) {
                var found = false;
                for (present[0..present_len]) |*p| {
                    if (in_flight.input_id == p.input_id) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    in_flight.flags.close_on_complete = true;
                    in_flight.flags.retry_pending = false;
                }
            };

            for (present[0..present_len]) |*p| {
                const found: bool = for (&this.joysticks) |*js| {
                    if (js.state != .inactive and js.input_id == p.input_id) break true;
                } else for (this.wait_que[0..this.wait_que_len]) |*ready_entry| {
                    if (ready_entry.input_id == p.input_id) break true;
                } else for (&this.io_open_in_flight) |*in_flight| {
                    if (in_flight.input_id == p.input_id) break true;
                } else false;

                if (!found) {
                    const event_name = p.event_name_buf[0..p.event_name_len :0];

                    this.submitOpenFd(event_name, p.event_id) catch |e| {
                        log.err("Failed to submit open for '/dev/input/{s}', error: {}", .{ event_name, e });
                        continue;
                    };
                }
            }

            while (this.wait_que_len > 0) {
                const index_opt: ?usize = for (&this.joysticks, 0..) |*js, ji| {
                    if (js.state == .inactive) {
                        break ji;
                    }
                } else null;

                if (index_opt) |ji| {
                    const entry = this.waitQueuePop().?;

                    var event_name_buf: [10]u8 = undefined;
                    const event_name = std.fmt.bufPrintSentinel(&event_name_buf, "event{}", .{entry.event_id}, 0) catch unreachable;
                    this.registerInSlot(event_name, entry.event_id, entry.input_id, entry.fd, entry.fd_open_ts, ji) catch |e| {
                        _ = this.waitQueuePush(entry);
                        log.err("Failed to add joystick '/dev/input/{s}', error: '{}'", .{ event_name, e });
                    };
                } else break;
            }
        }

        fn newIoInFlightIndex(this: *Context) ?usize {
            var result: ?usize = null;

            for (&this.io_open_in_flight, 0..) |*entry, i| {
                if (entry.event_id == -1) {
                    result = i;
                    break;
                }
            }

            return result;
        }

        fn freeIoInFlightIndex(this: *Context, index: usize) void {
            this.io_open_in_flight[index] = .{
                .event_id = -1,
                .input_id = undefined,
                ._event_name = undefined,
                .event_name_len = 0,
            };
        }

        fn getIoInFlightIndexByEventId(this: *Context, event_id: i11) ?usize {
            assert(event_id >= 0);

            var result: ?usize = null;

            for (&this.io_open_in_flight, 0..) |*in_flight, i| {
                if (in_flight.event_id == event_id) {
                    result = i;
                    break;
                }
            }

            return result;
        }

        fn submitOpenFd(this: *Context, event_name: [:0]const u8, event_id: i11) !void {
            assert(event_id >= 0);

            if (this.newIoInFlightIndex()) |in_flight_index| {
                errdefer this.freeIoInFlightIndex(in_flight_index);

                const in_flight = &this.io_open_in_flight[in_flight_index];

                var dev_sys_path_rel_buf: [fs.max_path_bytes]u8 = undefined;
                const dev_sys_path_rel_len = linux.readlinkat(this.sys_class_input_dir_fd, event_name, &dev_sys_path_rel_buf) catch |e| switch (e) {
                    error.NOENT => return error.DevSysPathMissing,
                    else => return e,
                };
                const dev_sys_path_rel_link = dev_sys_path_rel_buf[0..dev_sys_path_rel_len];

                const input_num_str_prefixed = std.fs.path.basename(std.fs.path.dirname(dev_sys_path_rel_link).?);
                const input_num_str = std.mem.cutPrefix(u8, input_num_str_prefixed, "input").?;
                const input_id = try std.fmt.parseInt(u31, input_num_str, 10);

                assert(event_name.len + 1 <= in_flight._event_name.len);
                in_flight.* = .{
                    .input_id = input_id,
                    .event_id = event_id,
                    .event_name_len = @intCast(event_name.len),
                    ._event_name = @splat(0),
                };
                @memcpy(in_flight._event_name[0..event_name.len], event_name);

                if (this.io_uring.openat(
                    in_flight_index,
                    this.dev_input_dir_fd,
                    in_flight.eventName(),
                    .{ .ACCMODE = .RDWR, .NONBLOCK = true },
                    0,
                )) |cqe| {
                    cqe.flags |= std.os.linux.IOSQE_ASYNC;
                    this.io_in_flight_count += 1;
                } else |e| switch (e) {
                    error.SubmissionQueueFull => {
                        this.freeIoInFlightIndex(in_flight_index);
                        log.err("In flight entries out of sync with submission queue", .{});
                        if (options.internal_build) @breakpoint();
                    },
                }

                log.debug("Submitted for opening: '/dev/input/{s}'", .{in_flight.eventName()});
            } else {
                log.err("Unable to queue open op for potential joystick, out of entries: '/dev/input/{s}'", .{event_name});
            }
        }

        fn submitCloseFd(this: *Context, fd: linux.fd_t) bool {
            var result = false;

            if (this.io_uring.close(@bitCast(@as(isize, -1)), fd)) |sqe| {
                sqe.flags |= std.os.linux.IOSQE_ASYNC;
                this.io_in_flight_count += 1;
                result = true;
            } else |submit_error| {
                log.err("io_uring close submit failed, error: '{}'", .{submit_error});
                log.warn("Calling blocking/sync close", .{});
                linux.close(fd);
            }

            return result;
        }

        fn register(this: *Context, event_name: [:0]const u8, event_id: i11, input_id: u31, fd: linux.fd_t, fd_open_ts: TimeStamp) Joystick.InitError!bool {
            assert(event_id >= 0);

            var result = false;

            for (&this.joysticks, 0..) |*js, ji| {
                if (js.state == .inactive) {
                    try this.registerInSlot(event_name, event_id, input_id, fd, fd_open_ts, ji);
                    result = true;
                    break;
                }
            }

            return result;
        }

        fn registerInSlot(this: *Context, event_name: [:0]const u8, event_id: i11, input_id: u31, fd: linux.fd_t, fd_open_ts: TimeStamp, slot_index: usize) Joystick.InitError!void {
            assert(slot_index < this.joysticks.len);

            const js = &this.joysticks[slot_index];
            assert(js.state == .inactive);

            log.info("Adding joystick: '/dev/input/event{}' (slot index: {})", .{ event_id, slot_index });

            assert(this.poll_fds[first_joystick_pollfd_idx + slot_index].fd == -1);

            try Joystick.init(js, this.sys_class_input_dir_fd, event_name, event_id, input_id, fd, fd_open_ts);

            this.poll_fds[first_joystick_pollfd_idx + slot_index] = .{
                .fd = @intCast(js.fd),
                .events = .{ .IN = true },
                .revents = undefined,
            };
        }

        fn unregister(this: *Context, event_id: i11) ?linux.fd_t {
            assert(event_id >= 0);

            var result: ?linux.fd_t = null;

            for (&this.joysticks, 0..) |*js, ji| {
                if (js.event_id == event_id) {
                    assert(js.state != .inactive);

                    log.info("Removing joystick: '/dev/input/event{}'", .{event_id});

                    result = js.fd;

                    this.unregisterFromSlot(ji);

                    if (this.waitQueuePop()) |entry| {
                        var event_name_buf: [10]u8 = undefined;
                        const event_name = std.fmt.bufPrintSentinel(&event_name_buf, "event{}", .{entry.event_id}, 0) catch unreachable;
                        this.registerInSlot(event_name, entry.event_id, entry.input_id, entry.fd, entry.fd_open_ts, ji) catch |e| {
                            _ = this.waitQueuePush(entry);
                            log.err("Failed to add joystick '/dev/input/event{}', error: '{}'", .{ event_id, e });
                        };
                    }

                    break;
                }
            } else for (&this.io_open_in_flight) |*in_flight| {
                if (in_flight.event_id == event_id) {
                    in_flight.flags.close_on_complete = true;
                    in_flight.flags.retry_pending = false;

                    break;
                }
            } else for (this.wait_que[0..this.wait_que_len], 0..) |*entry, entry_index| {
                if (entry.event_id == event_id) {
                    result = entry.fd;
                    this.waitQueueOrderedRemove(entry_index);

                    break;
                }
            }

            return result;
        }

        fn unregisterFromSlot(this: *Context, slot_index: usize) void {
            assert(slot_index < this.joysticks.len);

            const js = &this.joysticks[slot_index];
            assert(js.state != .inactive);

            assert(this.poll_fds[first_joystick_pollfd_idx + slot_index].fd == js.fd);

            js.deinit();

            const js_pollfd = &this.poll_fds[first_joystick_pollfd_idx + slot_index];
            js_pollfd.* = .{ .fd = -1, .events = undefined, .revents = undefined };
        }

        fn eventIdMatchesRegisteredOrWaiting(this: *Context, event_id: i11) bool {
            assert(event_id >= 0);

            var result = false;

            for (&this.joysticks) |*js| {
                if (js.state != .inactive and js.event_id == event_id) {
                    result = true;
                    break;
                }
            } else for (this.wait_que[0..this.wait_que_len]) |*ready_entry| {
                if (ready_entry.event_id == event_id) {
                    result = true;
                    break;
                }
            }

            return result;
        }

        fn waitQueuePush(this: *Context, entry: WaitQueueEntry) bool {
            var result = false;

            if (this.wait_que_len < this.wait_que.len) {
                this.wait_que[this.wait_que_len] = entry;
                this.wait_que_len += 1;
                result = true;
            }

            return result;
        }

        fn waitQueuePop(this: *Context) ?WaitQueueEntry {
            var result: ?WaitQueueEntry = null;

            if (this.wait_que_len > 0) {
                result = this.wait_que[0];

                this.wait_que_len -= 1;
                @memmove(this.wait_que[0..this.wait_que_len], this.wait_que[1..][0..this.wait_que_len]);
            }

            return result;
        }

        fn waitQueueOrderedRemove(this: *Context, index: usize) void {
            assert(index < this.wait_que_len);
            if (index < this.wait_que_len) {
                const rem_len = this.wait_que_len - (index + 1);
                if (rem_len > 0) {
                    @memmove(this.wait_que[index..][0..rem_len], this.wait_que[index + 1 ..][0..rem_len]);
                }

                this.wait_que_len -= 1;
            }
        }
    };
}

const WaitQueueEntry = struct {
    fd: linux.fd_t,
    fd_open_ts: TimeStamp,
    event_id: u10,
    input_id: u31,
};

const IoOpenInFlight = struct {
    event_id: i11 = -1,
    input_id: u31,
    flags: Flags = .{},
    _event_name: [10]u8,
    event_name_len: u8,

    const Flags = packed struct(u2) {
        retry_pending: bool = false,
        close_on_complete: bool = false,
    };

    inline fn eventName(this: *const IoOpenInFlight) [:0]const u8 {
        return this._event_name[0..this.event_name_len :0];
    }
};

fn eventFdIsJoystick(fd: fd_t) bool {
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

    if (linux.openat(dir_fd, attr, .{ .CLOEXEC = true }, 0)) |attr_fd| {
        defer linux.close(attr_fd);

        var attr_buf: [16]u8 = @splat(0);

        if (linux.read(attr_fd, attr_buf[0 .. attr_buf.len - 1])) |attr_value_optional_newline| {
            const attr_value = std.mem.trimEnd(u8, attr_value_optional_newline, "\n");
            result = std.mem.eql(u8, expect, attr_value);
        } else |e| {
            log.warn("Failed to read from attribute fd: '{s}', error: '{}'", .{ attr, e });
        }
    } else |e| switch (e) {
        error.NOENT => {},
        else => log.warn("Failed to open sysfs attribute fd: '{s}', error: '{}'", .{ attr, e }),
    }

    return result;
}
