const std = @import("std");
const log = std.log.scoped(.@"wayland-client");
const assert = std.debug.assert;

const linux = @import("linux");
const wayland = @import("wayland");
const wl = wayland.wl;

// TODO: Replace wayland.Array with slice/cast array types on dispatch
// TODO: Adding multiple listeners
// TODO: Allocations!
var glob_connected = false;
var glob_display: wl.Display = undefined;
var glob_next_object_id: u32 = 1;
var glob_objects: [32]wl.Object = std.mem.zeroes([32]wl.Object);

var glob_listener_count: usize = 0;
var glob_listeners: [32]Listener = std.mem.zeroes([32]Listener);

var glob_display_listener = wl.Display.Listener{
    .@"error" = handle_display_error,
    .delete_id = handle_delete_id,
};

const Message = struct {
    const Header = extern struct {
        id: u32,
        op: u16,
        size: u16 = undefined,
    };
    const Data = extern struct {
        header: Header,
        buf: [32]u32 = std.mem.zeroes([32]u32),
    };

    data: Data align(4),
    fds: [16]linux.fd_t = std.mem.zeroes([16]linux.fd_t),
    fds_used: usize = 0,
    buf_used: usize = 0,
    current_arg_offset: usize = 0,

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

        log.debug("-> {}", .{this.data.header});
        log.debug("-> {any} (dwords)", .{this.data.buf[0..this.buf_used]});
        log.debug("-> {any} (bytes)", .{@as([]u8, @ptrCast(this.data.buf[0..this.buf_used]))});

        // const written = try linux.write(display.fd, send_buf);
        // assert(written == total_size); // TODO: Handle partial write

        var iov = linux.iovec{ .base = send_buf.ptr, .len = send_buf.len };

        const fds_byte_size = @sizeOf(linux.fd_t) * this.fds_used;
        var control_buf: [this.fds.len * @sizeOf(linux.fd_t) + (2 * @sizeOf(linux.cmsghdr))]u8 align(@alignOf(linux.cmsghdr)) = undefined;
        const control_size = linux.CMSG_SPACE(fds_byte_size);
        const control = control_buf[0..control_size];

        var msg = linux.msghdr{
            .name = null,
            .namelen = 0,
            .iov = @ptrCast(&iov),
            .iovlen = 1,
            .control = control.ptr,
            .controllen = control.len,
            .flags = 0,
        };

        var cmsg: *linux.cmsghdr = linux.CMSG_FIRSTHDR(&msg).?;
        cmsg.level = linux.SOL.SOCKET;
        cmsg.type = linux.SCM.RIGHTS;
        cmsg.len = linux.CMSG_LEN(fds_byte_size);
        log.debug("ctrl bytes: {any}", .{control});

        @memcpy(linux.CMSG_DATA(cmsg), @as([]u8, @ptrCast(this.fds[0..this.fds_used])));

        log.debug("fds: {any}", .{this.fds[0..this.fds_used]});
        log.debug("ctrl bytes: {any}\n", .{control});

        const written = try linux.sendmsg(display.fd, &msg, linux.MSG.NOSIGNAL);
        assert(written == total_size); // TODO: Handle partial write
    }

    pub fn getIntArg(this: *Message) i32 {
        return @intCast(this.getUIntArg());
    }

    pub fn getUIntArg(this: *Message) u32 {
        const result = this.data.buf[this.current_arg_offset];
        this.current_arg_offset += 1;
        return result;
    }

    pub fn getObjectArg(this: *Message) ?*wl.Object {
        const id = this.getUIntArg();
        assert(id <= glob_objects.len);
        return &glob_objects[id];
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
};

const Listener = struct {
    id: u32,
    user_data: ?*anyopaque,
    implementation: []const *const fn () void,
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
            const new_proxy = proxy_create(&wl.Display.interface, wl.Display.interface.version);
            new_proxy.display = &glob_display;

            glob_display = .{
                .proxy = new_proxy.*,
                .fd = fd,
            };
            result = &glob_display;
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
            dispatched_count += readAndDispatch(display);
        }
    } else {
        log.err("display_roundtrip unable to setup sync callback", .{});
    }

    return dispatched_count;
}

fn displayRoundtripSyncDoneHandler(data: ?*anyopaque, callback: ?*wl.Callback, callback_data: u32) void {
    log.debug("sync done, callback: {}, data: {}", .{ callback.?, callback_data });
    const done_ptr: *bool = @ptrCast(data);
    done_ptr.* = true;
}

pub fn display_dispatch(display: *wl.Display) usize {
    _ = display;
    unreachable;
}

pub fn display_flush(display: *wl.Display) void {
    _ = display;
    unreachable;
}

fn readAndDispatch(display: *wl.Display) usize {
    var dispatched_count: usize = 0;

    var pollfd: linux.pollfd = .{ .fd = display.fd, .events = linux.POLL.IN, .revents = undefined };
    while (linux.poll(@ptrCast(&pollfd), 0) catch unreachable > 0) {
        if (pollfd.revents & linux.POLL.IN != 0) {
            const receive_buf_available = display.receive_buf[display.receive_used..];
            const read_buf = linux.read(display.fd, receive_buf_available) catch unreachable;
            display.receive_used += read_buf.len;

            var current_offset: usize = 0;
            while (true) {
                const receive_remaining = display.receive_buf[current_offset..display.receive_used];

                if (receive_remaining.len >= @sizeOf(Message.Header)) {
                    const header: *Message.Header = @alignCast(std.mem.bytesAsValue(Message.Header, receive_remaining));
                    if (receive_remaining.len >= header.size) {
                        assert(header.size <= @sizeOf(Message.Data));
                        const message_data: *align(4) Message.Data = @ptrCast(@alignCast(header));
                        var message: Message = .{ .data = message_data.*, .current_arg_offset = 0 };
                        tryDispatch(display, &message);
                        dispatched_count += 1;

                        current_offset += header.size;
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            }

            const remaining_byte_count = display.receive_used - current_offset;
            @memmove(display.receive_buf[0..remaining_byte_count], display.receive_buf[current_offset..display.receive_used]);
            display.receive_used = remaining_byte_count;
        } else {
            log.warn("readAndDispatch poll error", .{});
        }
    }

    return dispatched_count;
}

fn tryDispatch(display: *wl.Display, message: *Message) void {
    const object = &glob_objects[message.data.header.id];
    assert(object.proxy.id == message.data.header.id);

    log.debug("<- {s}.{s}", .{
        object.proxy.interface.name,
        if (object.proxy.interface.events) |ev| ev[message.data.header.op].name else "?",
    });
    log.debug("<- {}", .{message.data.header});
    const payload = message.data.buf[0..((message.data.header.size - @sizeOf(Message.Header)) / 4)];
    log.debug("<- {any} (dwords)", .{payload});
    log.debug("<- {any} (bytes)", .{@as([]u8, @ptrCast(payload))});

    // Handle wl_display.error, wl_display.delete_id
    for (glob_listeners[0..glob_listener_count]) |*listener| {
        if (listener.id == object.proxy.id) {
            dispatch(display, object, message, listener);
        }
    }
}

fn dispatch(display: *wl.Display, object: *wl.Object, message: *Message, listener: *const Listener) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const sig = std.mem.span(object.proxy.interface.events.?[message.data.header.op].signature);

    log.debug("dispatching signature: '{s}'", .{sig});

    if (sig.len == 0) {
        trampoline_(object, listener, message);
    } else if (std.mem.eql(u8, sig, "u")) {
        trampoline_u(object, listener, message);
    } else if (std.mem.eql(u8, sig, "i")) {
        trampoline_i(object, listener, message);
    } else if (std.mem.eql(u8, sig, "s")) {
        trampoline_s(object, listener, message);
    } else if (std.mem.eql(u8, sig, "a")) {
        trampoline_a(object, listener, message);
    } else if (std.mem.eql(u8, sig, "usu")) {
        trampoline_usu(object, listener, message);
    } else if (std.mem.eql(u8, sig, "ous")) {
        trampoline_ous(object, listener, message);
    } else if (std.mem.eql(u8, sig, "iia")) {
        trampoline_iia(object, listener, message);
    } else if (std.mem.eql(u8, sig, "uiii")) {
        trampoline_uiii(object, listener, message);
    } else if (std.mem.eql(u8, sig, "iiiiissi")) {
        trampoline_iiiiissi(object, listener, message);
    } else {
        log.err("Unhandled dispatch signature: '{s}'", .{sig});
        unreachable;
    }
}

fn trampoline_(object: *wl.Object, listener: *const Listener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    handler(listener.user_data, @ptrCast(object));
}

fn trampoline_u(object: *wl.Object, listener: *const Listener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_i(object: *wl.Object, listener: *const Listener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, i32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getIntArg();
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_s(object: *wl.Object, listener: *const Listener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, []const u8) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getStringArg();
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_a(object: *wl.Object, listener: *const Listener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, wayland.Array) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getArrayArg();
    handler(listener.user_data, @ptrCast(object), arg1);
}

fn trampoline_usu(object: *wl.Object, listener: *const Listener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32, []const u8, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
    const arg2 = message.getStringArg();
    const arg3 = message.getUIntArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_ous(object: *wl.Object, listener: *const Listener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, ?*wl.Object, u32, []const u8) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getObjectArg();
    const arg2 = message.getUIntArg();
    const arg3 = message.getStringArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_iia(object: *wl.Object, listener: *const Listener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, i32, i32, wayland.Array) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getIntArg();
    const arg2 = message.getIntArg();
    const arg3 = message.getArrayArg();
    handler(listener.user_data, @ptrCast(object), arg1, arg2, arg3);
}

fn trampoline_uiii(object: *wl.Object, listener: *const Listener, message: *Message) void {
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

fn trampoline_iiiiissi(object: *wl.Object, listener: *const Listener, message: *Message) void {
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

pub fn proxy_create(interface: *const wayland.Interface, version: u32) *wl.Proxy {
    assert(glob_next_object_id < glob_objects.len);
    const result: *wl.Proxy = @ptrCast(&glob_objects[glob_next_object_id]);
    result.* = .{
        .id = glob_next_object_id,
        .version = version,
        .interface = interface,
        .display = undefined,
    };
    glob_next_object_id += 1;
    return result;
}

pub fn proxy_destroy(proxy: *wl.Proxy) void {
    _ = proxy;
    // TODO:
}

pub fn proxy_marshal_array_flags(proxy: *wl.Proxy, op: u32, interface: ?*const wayland.Interface, version: u32, flags: u32, args: []const wayland.Argument) ?*wl.Object {
    _ = .{ proxy, op, interface, version, flags, args };

    const display = proxy.display;

    assert(proxy.interface.method_count > op);
    const method = proxy.interface.methods.?[op];
    const sig = std.mem.span(method.signature);
    assert(sig.len == args.len); // TODO: Smarter verification (nullable)

    var result: ?*wl.Proxy = null;

    var message: Message = .{ .data = .{ .header = .{ .id = proxy.id, .op = @intCast(op) } } };

    log.debug("marshal signature: {s}", .{sig});

    var i: usize = 0;
    while (i < sig.len) : (i += 1) {
        const sig_char = sig[i]; // TODO: Nullable (?)
        const arg = args[i];
        switch (sig_char) {
            'n' => {
                assert(interface != null);
                var new_proxy = proxy_create(interface.?, version); // TODO: Is this the right version
                new_proxy.display = display;
                result = new_proxy;
                message.addArg(new_proxy.id);
            },

            'u', 'i' => message.addArg(arg.u),
            'o' => message.addArg(arg.o.?.proxy.id),

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
                log.debug("last_u32: {x}", .{last_u32});
                log.debug("last_u32 bytes: {any}", .{std.mem.toBytes(last_u32)});
                message.addArg(last_u32);
            },

            'h' => message.addFD(arg.h),

            else => {
                log.err("Unhandled sig char: {c}", .{sig_char});
                unreachable;
            },
        }
    }

    log.debug("-> {s}.{s}", .{ proxy.interface.name, proxy.interface.methods.?[op].name });
    message.send(display) catch |e| {
        log.err("message.send failed, error: {}", .{e});
        log.err("reading and dispatching errors...", .{});
        _ = readAndDispatch(display);
        return null;
    };

    return @ptrCast(result);
}

pub fn proxy_add_listener(proxy: *wl.Proxy, implementation: []const *const fn () void, user_data: ?*anyopaque) void {
    assert(glob_listener_count < glob_listeners.len);

    glob_listeners[glob_listener_count] = .{
        .id = proxy.id,
        .user_data = user_data,
        .implementation = implementation,
    };

    glob_listener_count += 1;

    log.debug("proxy_add_listener: id: {}, proxy: {s}", .{ proxy.id, proxy.interface.name });
}

fn handle_display_error(user_data: ?*anyopaque, display: ?*wl.Display, object_id: ?*wl.Object, code: u32, message: []const u8) void {
    _ = .{ user_data, display, object_id, code, message };
    log.err("Wayland error: {s}", .{message});
    @panic(message);
}

fn handle_delete_id(user_data: ?*anyopaque, display: ?*wl.Display, id: u32) void {
    _ = .{ user_data, display, id };
    // TODO:
    // unreachable;
}
