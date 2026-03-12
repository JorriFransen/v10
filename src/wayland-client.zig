const std = @import("std");
const log = std.log.scoped(.@"wayland-client");
const assert = std.debug.assert;

const linux = @import("linux");
const wayland = @import("wayland");
const wl = wayland.wl;

// TODO: Replace wayland.Array with slice/cast array types on dispatch
var glob_connected = false;
var glob_display: wl.Display = undefined;

var glob_display_listener = wl.Display.Listener{
    .@"error" = handleDisplayError,
    .deleteId = handleDeleteId,
};

const Message = struct {
    const max_fd_count: usize = 16;
    const Header = extern struct {
        id: u32,
        op: u16,
        size: u16 = undefined,
    };

    header: *Header,
    payload: []u32,
    fds: []linux.fd_t,

    pub fn addArg(this: *Message, offset: *usize, arg: u32) void {
        assert(offset.* < this.payload.len);
        this.payload[offset.*] = arg;
        offset.* += 1;
    }

    pub fn addFD(this: *Message, offset: *usize, fd: linux.fd_t) void {
        assert(offset.* < this.fds.len);
        this.fds[offset.*] = fd;
        offset.* += 1;
    }

    pub fn getIntArg(this: *Message, arg_offset: *usize) i32 {
        return @bitCast(this.getUIntArg(arg_offset));
    }

    pub fn getUIntArg(this: *Message, arg_offset: *usize) u32 {
        assert(arg_offset.* < this.payload.len);
        const result = this.payload[arg_offset.*];
        arg_offset.* += 1;
        return result;
    }

    pub fn getObjectArg(this: *Message, arg_offset: *usize, display: *wl.Display) ?*wl.Object {
        const id = this.getUIntArg(arg_offset);
        assert(id <= display.objects.len);
        return getObject(display, id);
    }

    pub fn getFixedArg(this: *Message, arg_offset: *usize) wayland.Fixed {
        return .{ .value = @bitCast(this.getUIntArg(arg_offset)) };
    }

    pub fn getStringArg(this: *Message, arg_offset: *usize) []const u8 {
        const length = this.getUIntArg(arg_offset);

        const arg_size = @sizeOf(@TypeOf(this.payload[0]));
        const arg_count = (length + arg_size - 1) / arg_size;
        assert(arg_offset.* < this.payload.len);
        assert(arg_offset.* + arg_count <= this.payload.len);

        const result = @as([]const u8, @ptrCast(this.payload[arg_offset.*..]))[0 .. length - 1];

        arg_offset.* += arg_count;

        return result;
    }

    pub fn getArrayArg(this: *Message, arg_offset: *usize) wayland.Array {
        const length = this.getUIntArg(arg_offset);

        const arg_size = @sizeOf(@TypeOf(this.payload[0]));
        const arg_count = (length + arg_size - 1) / arg_size;
        assert(arg_offset.* < this.payload.len);
        assert(arg_offset.* + length <= this.payload.len);

        const result = @as([]u8, @ptrCast(this.payload[arg_offset.*..]))[0..length];

        arg_offset.* += arg_count;

        return .{ .size = result.len, .data = result.ptr };
    }

    pub fn getFDArg(this: *Message, fd_offset: *usize) linux.fd_t {
        assert(fd_offset.* < this.fds.len);
        const result = this.fds[fd_offset.*];
        fd_offset.* += 1;
        return result;
    }
};

pub fn displayConnect(path_opt: ?[*:0]const u8) ?*wl.Display {
    assert(!glob_connected);

    // TODO: Move socket to linux.zig
    var sock_addr = std.mem.zeroes(std.c.sockaddr.un);
    const fd = std.c.socket(std.c.AF.UNIX, std.c.SOCK.STREAM, 0);
    assert(fd >= 0);

    var result: ?*wl.Display = null;

    if (linux.fcntl(fd, linux.F.GETFL, 0)) |flags| {
        var socket_flags: linux.O = @bitCast(flags);
        socket_flags.NONBLOCK = true;
        if (linux.fcntl(fd, linux.F.SETFL, @as(u32, @bitCast(socket_flags)))) |_| {
            const path: [:0]const u8 = if (path_opt) |path| std.mem.span(path) else blk: {
                // TODO: Construct from XDG_RUNTIME_DIR
                break :blk "/run/user/1000/wayland-0";
            };

            sock_addr.family = std.c.AF.UNIX;
            assert(path.len <= sock_addr.path.len);
            @memcpy(sock_addr.path[0..path.len], path);
            const r = std.c.connect(fd, @ptrCast(&sock_addr), @sizeOf(@TypeOf(sock_addr)));
            assert(r == 0);

            // TODO: Is this the right version to pass?

            glob_display = .{
                .fd = fd,
                .proxy = undefined,
            };
            result = &glob_display;

            glob_display.objects[0].proxy = .{ .id = 1, .version = 0, .display = &glob_display, .interface = &wl.Display.interface, .freelist_node = .{} };
            glob_display.free_objects = .{ .first = &glob_display.objects[0].proxy.freelist_node };

            var last_node = glob_display.free_objects.first.?;
            for (glob_display.objects[1..], 2..) |*obj, id| {
                obj.proxy = .{ .id = @intCast(id), .version = 0, .display = &glob_display, .interface = undefined, .freelist_node = .{} };
                last_node.insertAfter(&obj.proxy.freelist_node);
                last_node = &obj.proxy.freelist_node;
            }
            last_node.next = null;

            const display_proxy = proxyCreate(&glob_display, &wl.Display.interface, wl.Display.interface.version);
            glob_display.proxy = display_proxy.*;

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

pub fn displayDisconnect(display: *wl.Display) void {
    linux.close(display.fd) catch unreachable;
}

pub fn displayRoundtrip(display: *wl.Display) usize {
    var dispatched_count: usize = 0;

    log.debug("display_roundtrip(id = {})", .{display.proxy.id});

    const sync_callback_opt = display.sync();

    if (sync_callback_opt) |sync_callback| {
        var done = false;
        const display_roundtrip_done_listener = wl.Callback.Listener{
            .done = &displayRoundtripSyncDoneHandler,
        };
        sync_callback.addListener(&display_roundtrip_done_listener, &done);
        displayFlush(display);

        while (!done) {
            const dc = displayDispatchTimeout(display, -1);
            if (dc < 0) break;
            dispatched_count += @intCast(dc);
        }
    } else {
        log.err("display_roundtrip unable to setup sync callback", .{});
    }

    log.debug("display_roundtrip(id = {}) -> {}\n", .{ display.proxy.id, dispatched_count });

    return dispatched_count;
}

fn displayRoundtripSyncDoneHandler(data: ?*anyopaque, _: ?*wl.Callback, _: u32) void {
    log.debug("done handler", .{});
    const done_ptr: *bool = @ptrCast(data);
    done_ptr.* = true;
}

pub fn displayDispatch(display: *wl.Display) isize {
    return displayDispatchTimeout(display, 0);
}

fn displayDispatchTimeout(display: *wl.Display, first_timeout: c_int) isize {
    assert(display == &glob_display);

    log.debug("display_dispatch(id = {})", .{display.proxy.id});

    var result: isize = 0;

    var timeout = first_timeout;
    var pollfd: linux.pollfd = .{ .fd = display.fd, .events = linux.POLL.IN, .revents = undefined };
    // TODO: Handle error
    while (linux.poll(@ptrCast(&pollfd), timeout) catch unreachable > 0) {
        if (timeout < 0) timeout = 0;

        if (pollfd.revents & linux.POLL.IN != 0) {
            const receive_buf_available = display.receive_payload_buf[display.receive_payload_used..];

            var control_buf: [linux.CMSG_SPACE(Message.max_fd_count * @sizeOf(linux.fd_t))]u8 align(@alignOf(linux.cmsghdr)) = undefined;
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
                var fd_dispatch_index: usize = 0;

                while (true) {
                    const receive_remaining = display.receive_payload_buf[current_offset..display.receive_payload_used];

                    if (receive_remaining.len >= @sizeOf(Message.Header)) {
                        const header: *Message.Header = @ptrCast(@alignCast(receive_remaining.ptr));
                        if (receive_remaining.len >= header.size) {
                            const payload_ptr: [*]u32 = @ptrCast(@as([*]Message.Header, @ptrCast(header)) + 1);
                            const payload: []u32 = payload_ptr[0 .. header.size - @sizeOf(Message.Header)];

                            const object = getObject(display, header.id);
                            assert(object.proxy.id == header.id);

                            var fds: [Message.max_fd_count]linux.fd_t = undefined;
                            var fd_count: usize = 0;

                            assert(header.op < object.proxy.interface.event_count);
                            for (object.proxy.interface.events.?[header.op].signature) |c| {
                                if (c == 'h') {
                                    assert(fd_dispatch_index < display.receive_fds_used);
                                    fds[fd_count] = display.receive_fds_buf[fd_dispatch_index];
                                    fd_count += 1;
                                    fd_dispatch_index += 1;
                                }
                            }

                            var message: Message = .{
                                .header = header,
                                .payload = payload,
                                .fds = fds[0..fd_count],
                            };

                            dispatch(display, &message, object);
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

                const remaining_fd_count = display.receive_fds_used - fd_dispatch_index;
                @memmove(display.receive_fds_buf[0..remaining_fd_count], display.receive_fds_buf[fd_dispatch_index..display.receive_fds_used]);
                display.receive_fds_used = remaining_fd_count;
                fd_dispatch_index = 0;
            } else |e| {
                log.warn("recvmsg error: {}", .{e});
                result = -1;
            }
        } else {
            log.warn("readAndDispatch poll error", .{});
            result = -1;
        }
    }

    log.debug("display_dispatch(id = {}) -> {}", .{ display.proxy.id, result });

    return result;
}

fn dispatch(display: *wl.Display, message: *Message, object: *wl.Object) void {
    assert(display == &glob_display);

    const sig = object.proxy.interface.events.?[message.header.op].signature;

    var listener_node = object.proxy.listeners.first;
    while (listener_node) |node| {
        const next = node.next;

        const listener: *wayland.RegisteredListener = @fieldParentPtr("node", node);

        if (sig.len == 0) {
            trampoline_(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "u")) {
            trampoline_u(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "i")) {
            trampoline_i(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "o")) {
            trampoline_o(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "s")) {
            trampoline_s(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "a")) {
            trampoline_a(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "ii")) {
            trampoline_ii(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "uu")) {
            trampoline_uu(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "ui")) {
            trampoline_ui(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "uo")) {
            trampoline_uo(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "uff")) {
            trampoline_uff(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "uuf")) {
            trampoline_uuf(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "uoa")) {
            trampoline_uoa(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "usu")) {
            trampoline_usu(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "uhu")) {
            trampoline_uhu(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "ous")) {
            trampoline_ous(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "iia")) {
            trampoline_iia(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "uuuu")) {
            trampoline_uuuu(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "uiii")) {
            trampoline_uiii(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "uoff")) {
            trampoline_uoff(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "uuuuu")) {
            trampoline_uuuuu(display, object, listener, message);
        } else if (std.mem.eql(u8, sig, "iiiiissi")) {
            trampoline_iiiiissi(display, object, listener, message);
        } else {
            log.err("Unhandled dispatch signature: '{s}'", .{sig});
            unreachable;
        }

        listener_node = next;
    }
}

pub fn displayFlush(display: *wl.Display) void {
    var iov = linux.iovec{ .base = &display.send_payload_buf, .len = display.send_payload_used };

    log.debug("display_flush(id = {})", .{display.proxy.id});

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
        var control: []u8 = if (display.send_fds_used > 0) control_buf[0..linux.CMSG_SPACE(fds_byte_size)] else &.{};

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

    log.debug("display_flush(id = {}) -> payload bytes: {}, fds: {}", .{ display.proxy.id, payload_size, fds_count });
}

fn trampoline_(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    handler(listener.user_data, @ptrCast(object));
}

fn trampoline_u(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getUIntArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_i(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, i32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getIntArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_o(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, ?*wl.Object) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getObjectArg(&arg_offset, display);
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_s(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, []const u8) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getStringArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_a(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, wayland.Array) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getArrayArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_ii(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, i32, i32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getIntArg(&arg_offset);
    const arg2 = message.getIntArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2);
}

fn trampoline_uu(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getUIntArg(&arg_offset);
    const arg2 = message.getUIntArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2);
}

fn trampoline_ui(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, i32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getUIntArg(&arg_offset);
    const arg2 = message.getIntArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2);
}

fn trampoline_uo(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, ?*wl.Object) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getUIntArg(&arg_offset);
    const arg2 = message.getObjectArg(&arg_offset, display);
    handler(listener.user_data, @ptrCast(object), arg1, arg2);
}

fn trampoline_uff(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, wayland.Fixed, wayland.Fixed) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getUIntArg(&arg_offset);
    const arg2 = message.getFixedArg(&arg_offset);
    const arg3 = message.getFixedArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_uuf(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, u32, wayland.Fixed) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getUIntArg(&arg_offset);
    const arg2 = message.getUIntArg(&arg_offset);
    const arg3 = message.getFixedArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_uoa(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, ?*wl.Object, wayland.Array) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getUIntArg(&arg_offset);
    const arg2 = message.getObjectArg(&arg_offset, display);
    const arg3: wayland.Array = message.getArrayArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_usu(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, []const u8, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getUIntArg(&arg_offset);
    const arg2 = message.getStringArg(&arg_offset);
    const arg3 = message.getUIntArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_uhu(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, fd: linux.fd_t, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;
    var fd_offset: usize = 0;

    const arg1 = message.getUIntArg(&arg_offset);
    const arg2 = message.getFDArg(&fd_offset);
    const arg3 = message.getUIntArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_ous(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, ?*wl.Object, u32, []const u8) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getObjectArg(&arg_offset, display);
    const arg2 = message.getUIntArg(&arg_offset);
    const arg3 = message.getStringArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_iia(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, i32, i32, wayland.Array) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getIntArg(&arg_offset);
    const arg2 = message.getIntArg(&arg_offset);
    const arg3 = message.getArrayArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_uuuu(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, u32, u32, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getUIntArg(&arg_offset);
    const arg2 = message.getUIntArg(&arg_offset);
    const arg3 = message.getUIntArg(&arg_offset);
    const arg4 = message.getUIntArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3, arg4);
}

fn trampoline_uiii(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, i32, i32, i32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getUIntArg(&arg_offset);
    const arg2 = message.getIntArg(&arg_offset);
    const arg3 = message.getIntArg(&arg_offset);
    const arg4 = message.getIntArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3, arg4);
}

fn trampoline_uoff(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, ?*wl.Object, wayland.Fixed, wayland.Fixed) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getUIntArg(&arg_offset);
    const arg2 = message.getObjectArg(&arg_offset, display);
    const arg3 = message.getFixedArg(&arg_offset);
    const arg4 = message.getFixedArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3, arg4);
}

fn trampoline_uuuuu(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, u32, u32, u32, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getUIntArg(&arg_offset);
    const arg2 = message.getUIntArg(&arg_offset);
    const arg3 = message.getUIntArg(&arg_offset);
    const arg4 = message.getUIntArg(&arg_offset);
    const arg5 = message.getUIntArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3, arg4, arg5);
}

fn trampoline_iiiiissi(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, i32, i32, i32, i32, i32, []const u8, []const u8, i32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);

    var arg_offset: usize = 0;

    const arg1 = message.getIntArg(&arg_offset);
    const arg2 = message.getIntArg(&arg_offset);
    const arg3 = message.getIntArg(&arg_offset);
    const arg4 = message.getIntArg(&arg_offset);
    const arg5 = message.getIntArg(&arg_offset);
    const arg6 = message.getStringArg(&arg_offset);
    const arg7 = message.getStringArg(&arg_offset);
    const arg8 = message.getIntArg(&arg_offset);
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8);
}

pub fn proxyCreate(display: *wl.Display, interface: *const wayland.Interface, version: u32) *wl.Proxy {
    assert(display == &glob_display);
    assert(display.free_objects.first != null);

    const result: *wl.Proxy = @fieldParentPtr("freelist_node", display.free_objects.popFirst().?);
    const id = result.id;

    result.* = .{
        .id = id,
        .version = version,
        .interface = interface,
        .display = display,
        .freelist_node = .{},
        .listeners = .{},
    };

    return result;
}

pub fn proxyDestroy(proxy: *wl.Proxy) void {
    const display = proxy.display;
    assert(display == &glob_display);
    assert(proxy.id != 1);

    while (proxy.listeners.popFirst()) |node| {
        display.free_listeners.prepend(node);
    }

    display.free_objects.prepend(&proxy.freelist_node);
}

pub fn proxyMarshalArrayFlags(proxy: *wl.Proxy, op: u32, interface: ?*const wayland.Interface, version: u32, flags: u32, args: []const wayland.Argument) ?*wl.Object {
    _ = .{ proxy, op, interface, version, flags, args };

    assert(glob_connected);
    const display = proxy.display;

    assert(proxy.interface.method_count > op);
    const method = proxy.interface.methods.?[op];
    const sig = method.signature;

    var result: ?*wl.Proxy = null;

    var msg_buf: [128 + (@sizeOf(Message.Header) / @sizeOf(u32))]u32 align(@alignOf(Message.Header)) = undefined;
    const header: *Message.Header = @ptrCast(&msg_buf);
    const payload_buf: []u32 = @ptrCast(@as([]Message.Header, @ptrCast(&msg_buf))[1..]);
    var fd_buf: [Message.max_fd_count]linux.fd_t = undefined;

    header.* = .{
        .id = proxy.id,
        .op = @intCast(op),
    };

    var message: Message = .{ .header = header, .payload = payload_buf, .fds = &fd_buf };

    var payload_used: usize = 0;
    var fds_used: usize = 0;

    var si: usize = 0;
    var ai: usize = 0;
    while (si < sig.len) : ({
        si += 1;
        ai += 1;
    }) {
        const sig_char = sig[si];
        var arg = args[ai];
        blk: switch (sig_char) {
            'n' => {
                assert(interface != null);
                const new_proxy = proxyCreate(display, interface.?, version); // TODO: Is this the right version
                result = new_proxy;
                arg.u = new_proxy.id;
                continue :blk 'u';
            },

            'u', 'i' => message.addArg(&payload_used, arg.u),

            '?' => {
                assert(si + 1 < sig.len);
                si += 1;
                assert(sig[si] == 'o');
                arg.u = if (arg.o) |o| o.proxy.id else 0;
                continue :blk 'u';
            },

            'o' => {
                if (arg.o) |o| {
                    arg.u = o.proxy.id;
                    continue :blk 'u';
                } else {
                    @panic("Non nullable pointer is null");
                }
            },

            's' => {
                const s = std.mem.span(arg.s) orelse "";
                message.addArg(&payload_used, @intCast(s.len + 1));
                var remaining = s.len;
                while (remaining >= 4) : (remaining -= 4) {
                    message.addArg(
                        &payload_used,
                        std.mem.bytesAsValue(u32, s[s.len - remaining .. s.len - remaining + 4]).*,
                    );
                }
                var last_u32: u32 = 0;

                for (s[s.len - remaining ..], 0..) |c, ci| {
                    last_u32 |= @as(u32, c) << @as(u5, @intCast((ci) * 8));
                }
                message.addArg(&payload_used, last_u32);
            },

            'h' => message.addFD(&fds_used, arg.h),

            else => {
                log.err("Unhandled sig char: {c}", .{sig_char});
                unreachable;
            },
        }
    }

    const header_size = @sizeOf(Message.Header);
    const total_size = header_size + (payload_used * @sizeOf(@TypeOf(payload_buf[0])));
    header.size = @intCast(total_size);
    const payload = std.mem.asBytes(&msg_buf)[0..total_size];
    const fds = fd_buf[0..fds_used];

    const payload_rem = display.send_payload_buf.len - display.send_payload_used;

    if (payload_rem < payload.len or display.send_fds_used > 0) {
        displayFlush(display);
        assert(payload.len <= display.send_payload_buf.len);
    }

    const payload_offset = display.send_payload_used;
    const fd_offset = display.send_fds_used;

    @memcpy(display.send_payload_buf[payload_offset .. payload_offset + payload.len], payload);
    display.send_payload_used += payload.len;

    if (fds.len > 0) {
        @memcpy(display.send_fds_buf[fd_offset .. fd_offset + fds.len], fds);
        display.send_fds_used += fds.len;

        displayFlush(display);
    }

    return @ptrCast(result);
}

pub fn proxyAddListener(proxy: *wl.Proxy, implementation: []const *const fn () void, user_data: ?*anyopaque) void {
    const display = proxy.display;
    assert(display == &glob_display);

    assert(display.free_listeners.first != null);

    const listener: *wayland.RegisteredListener = @fieldParentPtr("node", display.free_listeners.popFirst().?);
    listener.* = .{
        .user_data = user_data,
        .implementation = implementation,
    };

    proxy.listeners.prepend(&listener.node);
}

fn handleDisplayError(user_data: ?*anyopaque, display: ?*wl.Display, object_id: ?*wl.Object, code: u32, message: []const u8) void {
    _ = .{ user_data, display, object_id, code, message };
    log.err("Wayland error: {s}", .{message});
    @panic(message);
}

fn handleDeleteId(_: ?*anyopaque, display_opt: ?*wl.Display, id: u32) void {
    const display = display_opt.?;
    assert(display == &glob_display);

    assert(id != 1);
    assert(id <= display.objects.len);

    var proxy = &getObject(display, id).proxy;
    assert(proxy.id == id);

    proxyDestroy(proxy);
}

fn getObject(display: *wl.Display, id: u32) *wl.Object {
    assert(display == &glob_display);
    assert(id != 0);
    assert(id <= display.objects.len);
    if (id == 1) return @ptrCast(display);
    return &display.objects[id - 1];
}
