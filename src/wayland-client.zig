const std = @import("std");
const log = std.log.scoped(.@"wayland-client");
const assert = std.debug.assert;

const linux = @import("linux");
const wayland = @import("wayland");
const wl = wayland.wl;

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
    buf_used: usize = 0,
    current_arg_offset: usize = 0,

    pub fn addArg(this: *Message, arg: u32) void {
        assert(this.buf_used < this.data.buf.len);
        this.data.buf[this.buf_used] = arg;
        this.buf_used += 1;
    }

    pub fn send(this: *Message, display: *wl.Display) !void {
        const header_size = @sizeOf(Header);
        const total_size = header_size + this.buf_used * @sizeOf(@TypeOf(this.data.buf[0]));
        this.data.header.size = @intCast(total_size);
        const send_buf = std.mem.asBytes(&this.data)[0..total_size];

        log.debug("{}", .{this.data.header});
        log.debug("{any}", .{this.data.buf[0..8]});
        const written = try linux.write(display.fd, send_buf);
        assert(written == total_size); // TODO: Handle partial write
    }

    pub fn getIntArg(this: *Message) i32 {
        _ = this;
        unreachable;
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

    pub fn getStringArg(this: *Message) []const u8 {
        const length = this.getUIntArg();
        const result = @as([]const u8, @ptrCast(this.data.buf[this.current_arg_offset..]))[0..length];
        this.current_arg_offset += result.len / @sizeOf(@TypeOf(this.data.buf[0]));
        log.debug("strlen: {}", .{result.len});
        return result[0 .. result.len - 1];
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

            _ = readAndDispatch(&glob_display);
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
    log.debug("sync_callback_opt: {}", .{sync_callback_opt.?});
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

    while (true) {
        var pollfd: linux.pollfd = .{ .fd = display.fd, .events = linux.POLL.IN, .revents = undefined };
        const poll_rc = linux.poll(@ptrCast(&pollfd), 0) catch unreachable;
        if (poll_rc <= 0) break;
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
    log.debug("incoming message: {}", .{message.data.header});

    const object = &glob_objects[message.data.header.id];
    log.debug("matched obj: {any}", .{object});
    assert(object.proxy.id == message.data.header.id);

    // Handle wl_display.error, wl_display.delete_id
    for (glob_listeners[0..glob_listener_count]) |*listener| {
        if (listener.id == object.proxy.id) {
            dispatch(display, object, message, listener);
            break;
        }
    }
}

fn dispatch(display: *wl.Display, object: *wl.Object, message: *Message, listener: *const Listener) void {
    _ = display;

    assert(message.data.header.op < listener.implementation.len);
    const sig = std.mem.span(object.proxy.interface.events.?[message.data.header.op].signature);

    if (std.mem.eql(u8, sig, "u")) {
        trampoline_u(object, listener, message);
    } else if (std.mem.eql(u8, sig, "usu")) {
        trampoline_usu(object, listener, message);
    } else if (std.mem.eql(u8, sig, "ous")) {
        trampoline_ous(object, listener, message);
    } else {
        log.err("Unhandled dispatch signature: {s}", .{sig});
        unreachable;
    }
}

fn trampoline_u(object: *wl.Object, listener: *const Listener, message: *Message) void {
    assert(message.data.header.op < listener.implementation.len);
    const HandlerType = *const fn (?*anyopaque, ?*wl.Proxy, u32) void;
    const handler: HandlerType = @ptrCast(listener.implementation[message.data.header.op]);

    message.current_arg_offset = 0;
    const arg1 = message.getUIntArg();
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

    assert(interface != null);

    assert(proxy.interface.method_count > op);
    const method = proxy.interface.methods.?[op];
    const sig = std.mem.span(method.signature);
    assert(sig.len == args.len); // TODO: Smarter verification (nullable)

    var result: ?*wl.Proxy = null;
    if (sig[0] == 'n') {
        var new_proxy = proxy_create(interface.?, version); // TODO: Is this the right version
        new_proxy.display = display;
        result = new_proxy;
    }

    var message: Message = .{ .data = .{ .header = .{ .id = proxy.id, .op = @intCast(op) } } };

    var i: usize = 0;
    while (i < sig.len) : (i += 1) {
        const sig_char = sig[i]; // TODO: Nullable (?)
        const arg = args[i];
        switch (sig_char) {
            'n' => message.addArg(result.?.id),
            'u' => message.addArg(arg.u),
            else => {
                log.err("Unhandled sig char: {c}", .{sig_char});
                unreachable;
            },
        }
    }

    log.debug("sending message: {s}.{s}", .{ proxy.interface.name, proxy.interface.methods.?[op].name });
    message.send(display) catch {
        log.err("message.send failed", .{});
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
