const std = @import("std");
const log = std.log.scoped(.@"wayland-client");
const assert = std.debug.assert;

const linux = @import("linux");
const wayland = @import("wayland");
const wl = wayland.wl;

// TODO: Replace wayland.Array with slice/cast array types on dispatch
// TODO: Adding multiple listeners
var glob_connected = false;
var glob_display: wl.Display = undefined;

var glob_display_listener = wl.Display.Listener{
    .@"error" = handle_display_error,
    .delete_id = handle_delete_id,
};

const Message = struct {
    const max_fd_count: usize = 16;

    const Header = extern struct {
        id: u32,
        op: u16,
        size: u16 = undefined,
    };
    const Data = extern struct {
        header: Header,
        buf: [64]u32 = std.mem.zeroes([64]u32),
    };

    fds_used: usize = 0,
    buf_used: usize = 0,
    current_arg_offset: usize = 0,
    fds: [max_fd_count]linux.fd_t = std.mem.zeroes([max_fd_count]linux.fd_t),
    data: Data align(4),

    pub fn addArg(this: *Message, arg: u32) void {
        assert(this.buf_used < this.data.buf.len);
        this.data.buf[this.buf_used] = arg;
        this.buf_used += 1;
    }

    pub fn addFD(this: *Message, fd: linux.fd_t) void {
        // this.addArg(0);

        assert(this.fds_used < this.fds.len);
        this.fds[this.fds_used] = fd;
        this.fds_used += 1;
    }

    pub fn send(this: *Message, display: *wl.Display) !void {
        const header_size = @sizeOf(Header);
        const total_size = header_size + this.buf_used * @sizeOf(@TypeOf(this.data.buf[0]));
        this.data.header.size = @intCast(total_size);
        const send_buf = std.mem.asBytes(&this.data)[0..total_size];

        var iov = linux.iovec{ .base = send_buf.ptr, .len = send_buf.len };

        const fds_byte_size = @sizeOf(linux.fd_t) * this.fds_used;
        var control_buf: [linux.CMSG_SPACE(this.fds.len * @sizeOf(linux.fd_t))]u8 align(@alignOf(linux.cmsghdr)) = undefined;
        var control: []u8 = if (this.fds_used > 0) control_buf[0..linux.CMSG_SPACE(fds_byte_size)] else &.{};

        var msg = linux.msghdr{
            .name = null,
            .namelen = 0,
            .iov = @ptrCast(&iov),
            .iovlen = 1,
            .control = control.ptr,
            .controllen = control.len,
            .flags = 0,
        };

        if (this.fds_used > 0) {
            var cmsg: *linux.cmsghdr = linux.CMSG_FIRSTHDR(&msg).?;
            cmsg.level = linux.SOL.SOCKET;
            cmsg.type = linux.SCM.RIGHTS;
            cmsg.len = linux.CMSG_LEN(fds_byte_size);
            @memcpy(linux.CMSG_DATA(cmsg), @as([]u8, @ptrCast(this.fds[0..this.fds_used])));
        }

        const written = try linux.sendmsg(display.fd, &msg, linux.MSG.NOSIGNAL);
        assert(written == total_size); // TODO: Handle partial write
    }

    pub fn getIntArg(this: *Message) i32 {
        return @bitCast(this.getUIntArg());
    }

    pub fn getUIntArg(this: *Message) u32 {
        const result = this.data.buf[this.current_arg_offset];
        this.current_arg_offset += 1;
        return result;
    }

    pub fn getObjectArg(this: *Message, display: *wl.Display) ?*wl.Object {
        const id = this.getUIntArg();
        assert(id <= display.objects.len);
        return getObject(display, id);
    }

    pub fn getFixedArg(this: *Message) wayland.Fixed {
        return .{ .value = @bitCast(this.getUIntArg()) };
    }

    // TODO: Use getArrayArg
    pub fn getStringArg(this: *Message) []const u8 {
        const length = this.getUIntArg();
        const result = @as([]const u8, @ptrCast(this.data.buf[this.current_arg_offset..]))[0 .. length - 1];

        const arg_size = @sizeOf(@TypeOf(this.data.buf[0]));
        this.current_arg_offset += (length + arg_size - 1) / arg_size;

        return result;
    }

    pub fn getArrayArg(this: *Message) wayland.Array {
        const length = this.getUIntArg();
        const result = @as([]u8, @ptrCast(this.data.buf[this.current_arg_offset..]))[0..length];

        const arg_size = @sizeOf(@TypeOf(this.data.buf[0]));
        this.current_arg_offset += (length + arg_size - 1) / arg_size;

        return .{ .size = result.len, .alloc = result.len, .data = result.ptr };
    }

    pub fn getFDArg(this: *Message) linux.fd_t {
        const result = this.fds[this.fds_used];
        this.fds_used += 1;
        return result;
    }
};

pub fn display_connect(path_opt: ?[*:0]const u8) ?*wl.Display {
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

            const display_proxy = proxy_create(&glob_display, &wl.Display.interface, wl.Display.interface.version);
            glob_display.proxy = display_proxy.*;

            glob_display.free_listeners = .{ .first = &glob_display.listeners[0].node };
            var last_listener_node = glob_display.free_listeners.first.?;
            for (glob_display.listeners[1..]) |*listener| {
                last_listener_node.insertAfter(&listener.node);
                last_listener_node = &listener.node;
            }
            last_listener_node.next = null;

            glob_connected = true;

            glob_display.add_listener(&glob_display_listener, null);
        } else |e| {
            log.err("display_connect fcntl failed, error: {}", .{e});
        }
    } else |e| {
        log.err("display_connect fcntl failed, error: {}", .{e});
    }

    return result;
}

pub fn display_disconnect(display: *wl.Display) void {
    linux.close(display.fd) catch unreachable;
}

pub fn display_roundtrip(display: *wl.Display) usize {
    var dispatched_count: usize = 0;

    const sync_callback_opt = display.sync();
    if (sync_callback_opt) |sync_callback| {
        var done = false;
        const display_roundtrip_done_listener = wl.Callback.Listener{
            .done = &displayRoundtripSyncDoneHandler,
        };
        sync_callback.add_listener(&display_roundtrip_done_listener, &done);
        // TODO: Remove this listener? I believe the callback is implicitly freed?

        while (!done) {
            const dc = readAndDispatch(display);
            if (dc < 0) break;
            dispatched_count += @intCast(dc);
        }
    } else {
        log.err("display_roundtrip unable to setup sync callback", .{});
    }

    return dispatched_count;
}

fn displayRoundtripSyncDoneHandler(data: ?*anyopaque, _: ?*wl.Callback, _: u32) void {
    const done_ptr: *bool = @ptrCast(data);
    done_ptr.* = true;
}

pub fn display_dispatch(display: *wl.Display) isize {
    assert(display == &glob_display);
    return readAndDispatch(display);
}

pub fn display_flush(display: *wl.Display) void {
    _ = display;
    // TODO:
}

fn readAndDispatch(display: *wl.Display) isize {
    var result: isize = 0;

    var pollfd: linux.pollfd = .{ .fd = display.fd, .events = linux.POLL.IN, .revents = undefined };
    while (linux.poll(@ptrCast(&pollfd), 0) catch unreachable > 0) {
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
                while (true) {
                    const receive_remaining = display.receive_payload_buf[current_offset..display.receive_payload_used];

                    if (receive_remaining.len >= @sizeOf(Message.Header)) {
                        const header: *Message.Header = @ptrCast(@alignCast(receive_remaining.ptr));
                        if (receive_remaining.len >= header.size) {
                            assert(header.size <= @sizeOf(Message.Data));
                            const message_data: *align(4) Message.Data = @ptrCast(@alignCast(header));

                            var message: Message = .{
                                .data = message_data.*,
                                .current_arg_offset = 0,
                                .fds_used = 0,
                            };

                            const object = getObject(display, message.data.header.id);
                            assert(object.proxy.id == message.data.header.id);

                            assert(message.data.header.op < object.proxy.interface.event_count);
                            for (object.proxy.interface.events.?[message.data.header.op].signature) |c| {
                                if (c == 'h') {
                                    assert(display.fd_dispatch_index < display.receive_fds_used);
                                    message.fds[message.fds_used] = display.receive_fds_buf[display.fd_dispatch_index];
                                    message.fds_used += 1;
                                    display.fd_dispatch_index += 1;
                                }
                            }

                            tryDispatch(display, &message, object);
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

    return result;
}

fn tryDispatch(display: *wl.Display, message: *Message, object: *wl.Object) void {
    assert(display == &glob_display);

    var listener_node = object.proxy.listeners.first;
    while (listener_node) |node| {
        const next = node.next;

        const listener: *wayland.RegisteredListener = @fieldParentPtr("node", node);
        dispatch(display, object, message, listener);

        listener_node = next;
    }
}

fn dispatch(display: *wl.Display, object: *wl.Object, message: *Message, listener: *const wayland.RegisteredListener) void {
    assert(message.data.header.op < listener.implementation.len);
    const sig = object.proxy.interface.events.?[message.data.header.op].signature;

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
}

fn trampoline_(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    handler(listener.user_data, @ptrCast(object));
}

fn trampoline_u(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_i(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, i32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getIntArg();
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_o(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, ?*wl.Object) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getObjectArg(display);
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_s(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, []const u8) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getStringArg();
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_a(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, wayland.Array) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getArrayArg();
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_ii(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, i32, i32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getIntArg();
    const arg2 = message.getIntArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2);
}

fn trampoline_uu(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    const arg2 = message.getUIntArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2);
}

fn trampoline_ui(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, i32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    const arg2 = message.getIntArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2);
}

fn trampoline_uo(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, ?*wl.Object) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    const arg2 = message.getObjectArg(display);
    handler(listener.user_data, @ptrCast(object), arg1, arg2);
}

fn trampoline_uff(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, wayland.Fixed, wayland.Fixed) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    const arg2 = message.getFixedArg();
    const arg3 = message.getFixedArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_uuf(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, u32, wayland.Fixed) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    const arg2 = message.getUIntArg();
    const arg3 = message.getFixedArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_uoa(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, ?*wl.Object, wayland.Array) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    const arg2 = message.getObjectArg(display);
    const arg3 = message.getArrayArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_usu(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, []const u8, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    const arg2 = message.getStringArg();
    const arg3 = message.getUIntArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_uhu(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, fd: linux.fd_t, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    const arg2 = message.getFDArg();
    const arg3 = message.getUIntArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_ous(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, ?*wl.Object, u32, []const u8) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getObjectArg(display);
    const arg2 = message.getUIntArg();
    const arg3 = message.getStringArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_iia(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, i32, i32, wayland.Array) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getIntArg();
    const arg2 = message.getIntArg();
    const arg3 = message.getArrayArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_uuuu(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, u32, u32, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    const arg2 = message.getUIntArg();
    const arg3 = message.getUIntArg();
    const arg4 = message.getUIntArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3, arg4);
}

fn trampoline_uiii(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, i32, i32, i32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    const arg2 = message.getIntArg();
    const arg3 = message.getIntArg();
    const arg4 = message.getIntArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3, arg4);
}

fn trampoline_uoff(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, ?*wl.Object, wayland.Fixed, wayland.Fixed) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    const arg2 = message.getObjectArg(display);
    const arg3 = message.getFixedArg();
    const arg4 = message.getFixedArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3, arg4);
}

fn trampoline_uuuuu(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, u32, u32, u32, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    const arg2 = message.getUIntArg();
    const arg3 = message.getUIntArg();
    const arg4 = message.getUIntArg();
    const arg5 = message.getUIntArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3, arg4, arg5);
}

fn trampoline_iiiiissi(display: *wl.Display, object: *wl.Object, listener: *const wayland.RegisteredListener, message: *Message) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, i32, i32, i32, i32, i32, []const u8, []const u8, i32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getIntArg();
    const arg2 = message.getIntArg();
    const arg3 = message.getIntArg();
    const arg4 = message.getIntArg();
    const arg5 = message.getIntArg();
    const arg6 = message.getStringArg();
    const arg7 = message.getStringArg();
    const arg8 = message.getIntArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8);
}

pub fn proxy_create(display: *wl.Display, interface: *const wayland.Interface, version: u32) *wl.Proxy {
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

pub fn proxy_destroy(proxy: *wl.Proxy) void {
    const display = proxy.display;
    assert(display == &glob_display);
    assert(proxy.id != 1);

    while (proxy.listeners.popFirst()) |node| {
        display.free_listeners.prepend(node);
    }

    display.free_objects.prepend(&proxy.freelist_node);
}

pub fn proxy_marshal_array_flags(proxy: *wl.Proxy, op: u32, interface: ?*const wayland.Interface, version: u32, flags: u32, args: []const wayland.Argument) ?*wl.Object {
    _ = .{ proxy, op, interface, version, flags, args };

    assert(glob_connected);
    const display = proxy.display;

    assert(proxy.interface.method_count > op);
    const method = proxy.interface.methods.?[op];
    const sig = method.signature;

    var result: ?*wl.Proxy = null;

    var message: Message = .{ .data = .{ .header = .{ .id = proxy.id, .op = @intCast(op) } } };

    var si: usize = 0;
    var ai: usize = 0;
    while (si < sig.len) : ({
        si += 1;
        ai += 1;
    }) {
        const sig_char = sig[si]; // TODO: Nullable (?)
        const arg = args[ai];
        switch (sig_char) {
            'n' => {
                assert(interface != null);
                var new_proxy = proxy_create(display, interface.?, version); // TODO: Is this the right version
                result = new_proxy;
                message.addArg(new_proxy.id);
            },

            'u', 'i' => message.addArg(arg.u),

            '?' => {
                si += 1;
                assert(sig[si] == 'o');
                const id = if (arg.o) |o| o.proxy.id else 0;
                message.addArg(id);
            },

            'o' => {
                if (arg.o) |o| message.addArg(o.proxy.id) else {
                    @panic("Non nullable pointer is null");
                }
            },

            's' => {
                const s = std.mem.span(arg.s) orelse "";
                message.addArg(@intCast(s.len + 1));
                var remaining = s.len;
                while (remaining >= 4) : (remaining -= 4) {
                    message.addArg(std.mem.bytesAsValue(u32, s[s.len - remaining .. s.len - remaining + 4]).*);
                }
                var last_u32: u32 = 0;

                for (s[s.len - remaining ..], 0..) |c, ci| {
                    last_u32 |= @as(u32, c) << @as(u5, @intCast((ci) * 8));
                }
                message.addArg(last_u32);
            },

            'h' => message.addFD(arg.h),

            else => {
                log.err("Unhandled sig char: {c}", .{sig_char});
                unreachable;
            },
        }
    }

    message.send(display) catch |e| {
        log.err("message.send failed, error: {}", .{e});
        log.err("reading and dispatching errors...", .{});
        glob_connected = false;
        _ = readAndDispatch(display);
        @panic("Wayland error");
    };

    return @ptrCast(result);
}

pub fn proxy_add_listener(proxy: *wl.Proxy, implementation: []const *const fn () void, user_data: ?*anyopaque) void {
    const display = proxy.display;
    assert(display == &glob_display);

    assert(display.free_listeners.first != null);

    const listener: *wayland.RegisteredListener = @fieldParentPtr("node", display.free_listeners.popFirst().?);
    listener.* = .{
        .user_data = user_data,
        .implementation = implementation,
    };

    proxy.listeners.prepend(&listener.node);

    log.debug("proxy_add_listener: id: {}, proxy: {s}", .{ proxy.id, proxy.interface.name });
}

fn handle_display_error(user_data: ?*anyopaque, display: ?*wl.Display, object_id: ?*wl.Object, code: u32, message: []const u8) void {
    _ = .{ user_data, display, object_id, code, message };
    log.err("Wayland error: {s}", .{message});
    @panic(message);
}

fn handle_delete_id(_: ?*anyopaque, display_opt: ?*wl.Display, id: u32) void {
    const display = display_opt.?;
    assert(display == &glob_display);

    assert(id != 1);
    assert(id <= display.objects.len);

    var proxy = &getObject(display, id).proxy;
    assert(proxy.id == id);

    proxy_destroy(proxy);
}

fn getObject(display: *wl.Display, id: u32) *wl.Object {
    assert(display == &glob_display);
    assert(id != 0);
    assert(id <= display.objects.len);
    if (id == 1) return @ptrCast(display);
    return &display.objects[id - 1];
}
