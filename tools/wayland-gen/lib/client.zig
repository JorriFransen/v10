const std = @import("std");
const log = std.log.scoped(.@"wayland-client");
const assert = std.debug.assert;
const options = @import("options");

const builtin = @import("builtin");

const linux = @import("linux");

const core = @import("wayland.zig");
const trampolines = @import("trampolines.zig");
const Signature = trampolines.Signature;

pub const Display = core.Display;

comptime {
    if (options.verbose_wayland and builtin.mode != .Debug) {
        @compileError("Option verbose_wayland requires debug mode");
    }
}

const message_max_fd_count: usize = 16;

var glob_connected = false;
var glob_display: Display = undefined;

const glob_display_listener = Display.Listener{
    .@"error" = handleDisplayError,
    .deleteId = handleDeleteId,
};

pub const Object = struct {
    id: u32,
    version: u32,
    interface: *const Interface,
    freelist_node: std.SinglyLinkedList.Node = .{},
    listeners: std.SinglyLinkedList = .{},
    zombie: bool,
};

pub const Interface = struct {
    name: []const u8,
    version: u32,
    requests: []const Interface.Message,
    events: []const Interface.Message,

    pub const Message = struct {
        name: []const u8,
        object_types: []const *const Interface,
        fd_count: u24,
        signature: Signature,
        is_destructor: bool,
    };
};

pub const RegisteredListener = struct {
    user_data: ?*anyopaque,
    node: std.SinglyLinkedList.Node = .{},
    implementation: []const *const fn () void,
};

pub const Fixed = extern struct {
    value: i32,

    pub fn toDouble(fixed: Fixed) f64 {
        return @as(f64, @floatFromInt(fixed.value)) / 256;
    }

    pub fn toInt(fixed: Fixed) c_int {
        return @divTrunc(@as(c_int, @intCast(fixed.value)), 256);
    }
};

pub const Argument = union(enum) {
    i: i32,
    u: u32,
    f: Fixed,
    s: []const u8,
    @"?s": ?[]const u8,
    o: *Object,
    @"?o": ?*Object,
    n: u32,
    a: []u32,
    h: linux.fd_t,
};

const MessageHeader = extern struct {
    id: u32,
    op: u16,
    size: u16 = undefined,
};

pub fn displayConnect(path_opt: ?[*:0]const u8, environ_opt: ?*const std.process.Environ) ?*Display {
    assert(!glob_connected);

    var sock_addr = std.mem.zeroes(linux.sockaddr.un);
    const fd = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM, 0) catch unreachable; // TODO: Handle error

    var result: ?*Display = null;

    if (linux.fcntl(fd, linux.F.GETFL, 0)) |flags| {
        var socket_flags: linux.O = @bitCast(flags);
        socket_flags.NONBLOCK = true;
        if (linux.fcntl(fd, linux.F.SETFL, @as(u32, @bitCast(socket_flags)))) |_| {
            if (path_opt) |cpath| {
                const path = std.mem.span(cpath);
                assert(path.len <= sock_addr.path.len);
                @memcpy(sock_addr.path[0..path.len], path);
            } else if (environ_opt) |environ| {
                const xdg_runtime_dir = environ.getPosix("XDG_RUNTIME_DIR") orelse "/run/user/1000";
                const wayland_display = environ.getPosix("WAYLAND_DISPLAY") orelse "wayland-0";

                const fmt = std.fs.path.fmtJoin(&.{ xdg_runtime_dir, wayland_display });
                _ = std.fmt.bufPrintSentinel(&sock_addr.path, "{f}", .{fmt}, 0) catch {
                    log.err("Failed to construct wayland socket path from env", .{});
                    return null;
                };
            } else {
                const path = "/run/user/1000/wayland-0";
                @memcpy(sock_addr.path[0..path.len], path);
            }

            sock_addr.family = linux.AF.UNIX;
            const r = linux.connect(fd, @ptrCast(&sock_addr), @sizeOf(@TypeOf(sock_addr))) catch unreachable; // TODO: Handle error
            assert(r == 0);

            glob_display = .{
                .fd = fd,
                .object = undefined,
            };
            result = &glob_display;

            glob_display.objects[0] = .{
                .id = 1,
                .version = Display.interface.version,
                .interface = &Display.interface,
                .freelist_node = .{},
                .zombie = false,
            };
            glob_display.free_objects = .{ .first = &glob_display.objects[0].freelist_node };

            var last_node = glob_display.free_objects.first.?;
            for (glob_display.objects[1..], 2..) |*obj, id| {
                obj.* = .{
                    .id = @intCast(id),
                    .version = 0,
                    .interface = undefined,
                    .freelist_node = .{},
                    .zombie = false,
                };
                last_node.insertAfter(&obj.freelist_node);
                last_node = &obj.freelist_node;
            }
            last_node.next = null;

            for (glob_display.server_objects[0..]) |*server_obj| {
                server_obj.* = .{
                    .id = 0,
                    .version = 0,
                    .interface = undefined,
                    .freelist_node = .{},
                    .zombie = false,
                };
            }

            const display_object = createClientObject(&Display.interface, Display.interface.version);
            glob_display.object = display_object.*;

            glob_display.free_listeners = .{ .first = &glob_display.listeners[0].node };
            var last_listener_node = glob_display.free_listeners.first.?;
            for (glob_display.listeners[1..]) |*listener| {
                last_listener_node.insertAfter(&listener.node);
                last_listener_node = &listener.node;
            }
            last_listener_node.next = null;

            glob_connected = true;

            glob_display.addListener(&glob_display_listener, null);
        } else |e| {
            log.err("display_connect fcntl failed, error: {}", .{e});
        }
    } else |e| {
        log.err("display_connect fcntl failed, error: {}", .{e});
    }

    return result;
}

pub fn displayDisconnect(display: *Display) void {
    linux.close(display.fd) catch unreachable;
}

pub fn displayRoundtrip(display: *Display) usize {
    var dispatched_count: usize = 0;

    verbose("display_roundtrip(id = {}) ...", .{display.object.id});

    const sync_callback = display.sync();

    var done = false;
    const display_roundtrip_done_listener = core.Callback.Listener{
        .done = &displayRoundtripSyncDoneHandler,
    };
    sync_callback.addListener(&display_roundtrip_done_listener, &done);
    displayFlush(display);

    while (!done) {
        const dc = displayDispatchTimeout(display, -1);
        if (dc < 0) break;
        dispatched_count += @intCast(dc);
    }

    verbose("display_roundtrip(id = {}) dispatched: {}\n", .{ display.object.id, dispatched_count });

    return dispatched_count;
}

fn displayRoundtripSyncDoneHandler(data: ?*anyopaque, _: ?*core.Callback, _: u32) void {
    const done_ptr: *bool = @ptrCast(data);
    done_ptr.* = true;
}

pub fn displayDispatch(display: *Display) isize {
    return displayDispatchTimeout(display, 0);
}

pub fn displayDispatchTimeout(display: *Display, first_timeout: c_int) isize {
    assert(display == &glob_display);

    verbose("display_dispatch(id = {}, timeout = {}) ...", .{ display.object.id, first_timeout });

    var result: isize = 0;

    var timeout = first_timeout;
    var pollfd: linux.pollfd = .{ .fd = display.fd, .events = linux.POLL.IN, .revents = undefined };
    // TODO: Handle error
    while (linux.poll(@ptrCast(&pollfd), timeout) catch unreachable > 0) {
        if (timeout != 0) timeout = 0;

        if (pollfd.revents & linux.POLL.IN != 0) {
            const receive_buf_available = display.receive_payload_buf[display.receive_payload_used..];

            var control_buf: [linux.CMSG_SPACE(message_max_fd_count * @sizeOf(linux.fd_t))]u8 align(@alignOf(linux.cmsghdr)) = undefined;
            _ = &control_buf;

            var iov: linux.iovec = .{ .base = receive_buf_available.ptr, .len = receive_buf_available.len };
            var msg: linux.msghdr = .{
                .iov = @ptrCast(&iov),
                .iovlen = 1,
                .name = null,
                .namelen = 0,
                .control = &control_buf,
                .controllen = control_buf.len,
                .flags = 0,
            };

            if (linux.recvmsg(display.fd, &msg, 0)) |bytes_read| {
                assert(msg.flags & linux.MSG.TRUNC == 0);
                assert(msg.flags & linux.MSG.CTRUNC == 0);
                const read_buf = receive_buf_available[0..bytes_read];
                display.receive_payload_used += read_buf.len;

                if (msg.controllen > 0) {
                    var cmsg: ?*linux.cmsghdr = linux.CMSG_FIRSTHDR(&msg);
                    while (cmsg) |m| : (cmsg = linux.CMSG_NXTHDR(&msg, m)) {
                        if (m.level == linux.SOL.SOCKET and m.type == linux.SCM.RIGHTS) {
                            const fd_count = (m.len - linux.CMSG_LEN(0)) / @sizeOf(linux.fd_t);
                            const fds = @as([]linux.fd_t, @ptrCast(@alignCast(linux.CMSG_DATA(m))));
                            assert(fds.len == fd_count);

                            const offset = display.receive_fds_used;
                            assert(display.receive_fds_buf.len - offset > fds.len);
                            @memcpy(display.receive_fds_buf[offset .. offset + fds.len], fds);
                            display.receive_fds_used += fds.len;
                        }
                    }
                }

                var current_offset: usize = 0;
                display.fd_dispatch_index = 0;

                while (true) {
                    const receive_remaining = display.receive_payload_buf[current_offset..display.receive_payload_used];

                    if (receive_remaining.len >= @sizeOf(MessageHeader)) {
                        const header: *MessageHeader = @ptrCast(@alignCast(receive_remaining.ptr));
                        if (receive_remaining.len >= header.size) {
                            const payload_ptr: [*]u32 = @ptrCast(@as([*]MessageHeader, @ptrCast(header)) + 1);
                            display.current_receive_payload = payload_ptr[0 .. header.size - @sizeOf(MessageHeader)];
                            display.current_payload_offset = 0;

                            const object = getObject(display, header.id);
                            assert(object.id == header.id);

                            trampolines.dispatch(object, header.op);
                            result += 1;

                            current_offset += header.size;
                        } else {
                            break;
                        }
                    } else {
                        break;
                    }
                }

                const remaining_byte_count = display.receive_payload_used - current_offset;
                @memmove(display.receive_payload_buf[0..remaining_byte_count], display.receive_payload_buf[current_offset..display.receive_payload_used]);
                display.receive_payload_used = remaining_byte_count;

                const remaining_fd_count = display.receive_fds_used - display.fd_dispatch_index;
                @memmove(display.receive_fds_buf[0..remaining_fd_count], display.receive_fds_buf[display.fd_dispatch_index..display.receive_fds_used]);
                display.receive_fds_used = remaining_fd_count;
                display.fd_dispatch_index = 0;
            } else |e| {
                log.warn("recvmsg error: {}", .{e});
                result = -1;
            }
        } else {
            log.warn("readAndDispatch poll error", .{});
            result = -1;
        }
    }

    verbose("display_dispatch(id = {}) -> dispatched = {}", .{ display.object.id, result });

    return result;
}

pub fn dispatchIntArg() i32 {
    return @bitCast(dispatchUIntArg());
}

pub fn dispatchUIntArg() u32 {
    assert(glob_display.current_payload_offset < glob_display.current_receive_payload.len);
    const result = glob_display.current_receive_payload[glob_display.current_payload_offset];
    glob_display.current_payload_offset += 1;
    return result;
}

pub fn dispatchObjectArg() ?*Object {
    const id = dispatchUIntArg();
    if (id < 1) return null;
    return getObject(&glob_display, id);
}

pub fn dispatchNewIdArg(interface: *const Interface, version: u32) *Object {
    const server_id = dispatchUIntArg();
    var result: ?*Object = null;

    // Check for matching zombie
    for (&glob_display.server_objects) |*obj| {
        if (obj.id == server_id) {
            if (obj.zombie) {
                result = obj;
                break;
            } else @panic("Server managed id collision");
        }
    }

    if (result == null) {
        // Check for unused object
        for (&glob_display.server_objects) |*obj| {
            if (obj.id == 0) {
                result = obj;
                break;
            }
        }

        if (result == null) {
            // Reuse zombie object
            for (&glob_display.server_objects) |*obj| {
                if (obj.zombie) {
                    result = obj;
                    break;
                }
            }
        }
    }

    if (result) |obj| {
        obj.* = .{
            .id = server_id,
            .version = version,
            .interface = interface,
            .freelist_node = .{},
            .listeners = .{},
            .zombie = false,
        };
        return obj;
    }

    log.err("Out of server objects", .{});
    @panic("Out of server objects");
}

pub fn dispatchFixedArg() Fixed {
    return .{ .value = @bitCast(dispatchUIntArg()) };
}

pub fn dispatchStringArg() []const u8 {
    const length = dispatchUIntArg();

    const arg_size = @sizeOf(@TypeOf(glob_display.current_receive_payload[0]));
    const arg_count = (length + arg_size - 1) / arg_size;
    assert(glob_display.current_payload_offset < glob_display.current_receive_payload.len);
    assert(glob_display.current_payload_offset + arg_count <= glob_display.current_receive_payload.len);

    const result = @as([]const u8, @ptrCast(glob_display.current_receive_payload[glob_display.current_payload_offset..]))[0 .. length - 1];

    glob_display.current_payload_offset += arg_count;

    return result;
}

pub fn dispatchArrayArg() []u32 {
    const length = dispatchUIntArg();
    assert(length % @sizeOf(u32) == 0);

    const arg_size = @sizeOf(@TypeOf(glob_display.current_receive_payload[0]));
    const arg_count = length / arg_size;
    assert(glob_display.current_payload_offset < glob_display.current_receive_payload.len);
    assert(glob_display.current_payload_offset + length <= glob_display.current_receive_payload.len);

    const result: []u32 = glob_display.current_receive_payload[glob_display.current_payload_offset .. glob_display.current_payload_offset + arg_count];

    glob_display.current_payload_offset += arg_count;

    return result;
}

pub fn dispatchFDArg() linux.fd_t {
    assert(glob_display.fd_dispatch_index < glob_display.receive_fds_used);

    const result = glob_display.receive_fds_buf[glob_display.fd_dispatch_index];
    glob_display.fd_dispatch_index += 1;
    return result;
}

pub fn displayFlush(display: *Display) void {
    var iov = linux.iovec{ .base = &display.send_payload_buf, .len = display.send_payload_used };

    verbose("display_flush(id = {}) ...", .{display.object.id});

    const payload_size = display.send_payload_used;
    const fds_count = display.send_fds_used;

    var msg = linux.msghdr{
        .name = null,
        .namelen = 0,
        .iov = @ptrCast(&iov),
        .iovlen = 1,
        .control = null,
        .controllen = 0,
        .flags = 0,
    };

    if (display.send_fds_used > 0) {
        const fds_byte_size = @sizeOf(linux.fd_t) * display.send_fds_used;
        var control_buf: [linux.CMSG_SPACE(display.send_fds_buf.len * @sizeOf(linux.fd_t))]u8 align(@alignOf(linux.cmsghdr)) = undefined;
        const control: []u8 = if (display.send_fds_used > 0) control_buf[0..linux.CMSG_SPACE(fds_byte_size)] else &.{};

        msg.control = control.ptr;
        msg.controllen = control.len;

        var cmsg: *linux.cmsghdr = linux.CMSG_FIRSTHDR(&msg).?;
        cmsg.level = linux.SOL.SOCKET;
        cmsg.type = linux.SCM.RIGHTS;
        cmsg.len = linux.CMSG_LEN(fds_byte_size);
        @memcpy(linux.CMSG_DATA(cmsg), @as([]u8, @ptrCast(display.send_fds_buf[0..display.send_fds_used])));

        // This should never result in partial writes when control is attached
        const written = linux.sendmsg(display.fd, &msg, linux.MSG.NOSIGNAL) catch |e| {
            log.err("message send failed, error: {}", .{e});
            log.err("reading and dispatching errors...", .{});
            glob_connected = false;
            _ = displayDispatch(display);
            @panic("Wayland error");
        };

        assert(written == display.send_payload_used);
    } else {
        const written = linux.sendmsg(display.fd, &msg, linux.MSG.NOSIGNAL) catch |e| {
            log.err("message send failed, error: {}", .{e});
            log.err("reading and dispatching errors...", .{});
            glob_connected = false;
            _ = displayDispatch(display);
            @panic("Wayland error");
        };

        assert(written == display.send_payload_used);
    }

    display.send_payload_used = 0;
    display.send_fds_used = 0;

    verbose("display_flush(id = {}) payload bytes = {}, fds = {}", .{ display.object.id, payload_size, fds_count });
}

pub inline fn createClientObject(interface: *const Interface, version: u32) *Object {
    assert(glob_display.free_objects.first != null);

    const result: *Object = @fieldParentPtr("freelist_node", glob_display.free_objects.popFirst().?);
    const id = result.id;

    result.* = .{
        .id = id,
        .version = version,
        .interface = interface,
        .freelist_node = .{},
        .listeners = .{},
        .zombie = false,
    };

    return result;
}

pub inline fn destroyClientObject(object: *Object) void {
    assert(object.id < 0xff000000);

    assert(object.id < glob_display.objects.len);
    assert(object.id != 1);

    glob_display.free_objects.prepend(&object.freelist_node);
}

pub inline fn markZombieObject(object: *Object) void {
    assert(!object.zombie);

    while (object.listeners.popFirst()) |node| {
        glob_display.free_listeners.prepend(node);
    }

    object.zombie = true;
}

pub fn marshalRequest(object: *Object, op: u32, args: []const Argument) void {
    assert(glob_connected);

    if (object.zombie) @panic("Calling request on zombie object");

    assert(object.interface.requests.len > op);

    var msg_buf: [128 + (@sizeOf(MessageHeader) / @sizeOf(u32))]u32 align(@alignOf(MessageHeader)) = undefined;
    const header: *MessageHeader = @ptrCast(&msg_buf);
    const payload_buf: []u32 = @ptrCast(@as([]MessageHeader, @ptrCast(&msg_buf))[1..]);
    var fd_buf: [message_max_fd_count]linux.fd_t = undefined;

    header.* = .{
        .id = object.id,
        .op = @intCast(op),
    };

    var payload_used: usize = 0;
    var fds_used: usize = 0;

    // TODO: Check arg types (emit more types in interfaces?)
    for (args) |arg| {
        arg_type_switch_blk: switch (arg) {
            .i => |i| marshalArg(payload_buf, &payload_used, @bitCast(i)),
            .u => |u| marshalArg(payload_buf, &payload_used, u),
            .f => |f| marshalArg(payload_buf, &payload_used, @bitCast(f)),
            .s => |s| {
                marshalArg(payload_buf, &payload_used, @intCast(s.len + 1));
                var remaining = s.len;
                while (remaining >= 4) : (remaining -= 4) {
                    marshalArg(
                        payload_buf,
                        &payload_used,
                        std.mem.bytesAsValue(u32, s[s.len - remaining .. s.len - remaining + 4]).*,
                    );
                }
                var last_u32: u32 = 0;

                for (s[s.len - remaining ..], 0..) |c, ci| {
                    last_u32 |= @as(u32, c) << @as(u5, @intCast((ci) * 8));
                }
                marshalArg(payload_buf, &payload_used, last_u32);
            },
            .@"?s" => |s_opt| {
                if (s_opt) |s| {
                    continue :arg_type_switch_blk .{ .s = s };
                } else {
                    marshalArg(payload_buf, &payload_used, 0);
                }
            },
            .o => |o| continue :arg_type_switch_blk .{ .u = o.id },
            .@"?o" => |o_opt| continue :arg_type_switch_blk .{ .u = if (o_opt) |o| o.id else 0 },
            .n => |n| continue :arg_type_switch_blk .{ .u = n },
            .a => |a| {
                marshalArg(payload_buf, &payload_used, @intCast(a.len));

                var remaining = a.len;
                while (remaining >= 4) : (remaining -= 4) {
                    marshalArg(
                        payload_buf,
                        &payload_used,
                        std.mem.bytesAsValue(u32, a[a.len - remaining .. a.len - remaining + 4]).*,
                    );
                }

                if (remaining > 0) {
                    var last_u32: u32 = 0;
                    for (a[a.len - remaining ..], 0..) |b, bi| {
                        last_u32 |= @as(u32, b) << @as(u5, @intCast((bi * 8)));
                    }
                    marshalArg(payload_buf, &payload_used, last_u32);
                }
            },
            .h => {
                assert(fds_used < fd_buf.len);
                fd_buf[fds_used] = arg.h;
                fds_used += 1;
            },
        }
    }

    if (options.verbose_wayland) {
        var print_buf: [1024]u8 = undefined;
        var used: usize = 0;

        var p = std.fmt.bufPrint(print_buf[used..], "  -> {s}.{s}(id = {}", .{ object.interface.name, object.interface.requests[op].name, object.id }) catch unreachable;
        used += p.len;

        var return_id: ?u32 = null;
        for (args) |arg| {
            if (arg == .n) {
                return_id = arg.n;
                continue;
            }

            p = switch (arg) {
                .o => |o| std.fmt.bufPrint(print_buf[used..], ", id = {}", .{o.id}) catch unreachable,
                .@"?o" => |o| std.fmt.bufPrint(print_buf[used..], ", id = {}", .{if (o) |obj| obj.id else 0}) catch unreachable,
                .i => |i| std.fmt.bufPrint(print_buf[used..], ", {}", .{i}) catch unreachable,
                .u => |u| std.fmt.bufPrint(print_buf[used..], ", {}", .{u}) catch unreachable,
                .h => |h| std.fmt.bufPrint(print_buf[used..], ", fd = {}", .{h}) catch unreachable,
                .f => |f| std.fmt.bufPrint(print_buf[used..], ", {}", .{f.toDouble()}) catch unreachable,
                .s => |s| std.fmt.bufPrint(print_buf[used..], ", '{s}'", .{s}) catch unreachable,
                .@"?s" => |so| std.fmt.bufPrint(print_buf[used..], ", '{s}'", .{if (so) |s| s else ""}) catch unreachable,
                .n => |n| std.fmt.bufPrint(print_buf[used..], ", new-id = {}", .{n}) catch unreachable,
                .a => |a| std.fmt.bufPrint(print_buf[used..], ", {any}", .{a}) catch unreachable,
            };
            used += p.len;
        }
        p = std.fmt.bufPrint(print_buf[used..], ")", .{}) catch unreachable;
        used += p.len;

        if (return_id) |id| {
            p = std.fmt.bufPrint(print_buf[used..], " -> id = {}", .{id}) catch unreachable;
            used += p.len;
        }

        verbose("{s}", .{print_buf[0..used]});
    }

    const header_size = @sizeOf(MessageHeader);
    const total_size = header_size + (payload_used * @sizeOf(@TypeOf(payload_buf[0])));
    header.size = @intCast(total_size);
    const payload = std.mem.asBytes(&msg_buf)[0..total_size];
    const fds = fd_buf[0..fds_used];

    const payload_rem = glob_display.send_payload_buf.len - glob_display.send_payload_used;

    if (payload_rem < payload.len or glob_display.send_fds_used > 0) {
        displayFlush(&glob_display);
        assert(payload.len <= glob_display.send_payload_buf.len);
    }

    const payload_offset = glob_display.send_payload_used;
    const fd_offset = glob_display.send_fds_used;

    @memcpy(glob_display.send_payload_buf[payload_offset .. payload_offset + payload.len], payload);
    glob_display.send_payload_used += payload.len;

    if (fds.len > 0) {
        @memcpy(glob_display.send_fds_buf[fd_offset .. fd_offset + fds.len], fds);
        glob_display.send_fds_used += fds.len;

        displayFlush(&glob_display);
    }
}

pub fn marshalArg(buf: []u32, offset: *usize, arg: u32) void {
    assert(offset.* < buf.len);
    buf[offset.*] = arg;
    offset.* += 1;
}

pub fn proxyAddListener(object: *Object, implementation: []const *const fn () void, user_data: ?*anyopaque) void {
    assert(glob_display.free_listeners.first != null);

    const listener: *RegisteredListener = @fieldParentPtr("node", glob_display.free_listeners.popFirst().?);
    listener.* = .{
        .user_data = user_data,
        .implementation = implementation,
    };

    object.listeners.prepend(&listener.node);
}

fn handleDisplayError(user_data: ?*anyopaque, display: ?*Display, object_id: ?*Object, code: u32, message: []const u8) void {
    _ = .{ user_data, display, object_id, code, message };
    log.err("Wayland error: {s}", .{message});
    @panic(message);
}

fn handleDeleteId(_: ?*anyopaque, display: *Display, id: u32) void {
    assert(display == &glob_display);

    assert(id != 1);
    assert(id <= glob_display.objects.len);

    const object = getObject(&glob_display, id);
    assert(object.id == id);

    destroyClientObject(object);
}

fn getObject(display: *Display, id: u32) *Object {
    assert(display == &glob_display);
    assert(id != 0);

    if (id < 0xff000000) {
        assert(id <= display.objects.len);
        if (id == 1) return @ptrCast(display);
        return &display.objects[id - 1];
    } else {
        for (&display.server_objects) |*server_obj| {
            if (id == server_obj.id) return server_obj;
        }
        @panic("Server side id object not found");
    }
}

const verbose_log = std.log.scoped(.verbose_wayland);
pub inline fn verbose(comptime fmt: []const u8, args: anytype) void {
    if (options.verbose_wayland) verbose_log.debug(fmt, args);
}
