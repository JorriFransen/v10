const std = @import("std");
const log = std.log.scoped(.@"wayland-client");
const assert = std.debug.assert;
const options = @import("options");
const builtin = @import("builtin");

const linux = @import("linux");
const wayland = @import("wayland");
const wl = wayland.wl;

// TODO: Check passed versions
// TODO: Merge this file with generator

comptime {
    if (options.verbose_wayland and builtin.mode != .Debug) {
        @compileError("Option verbose_wayland requires debug mode");
    }
}

var glob_connected = false;
var glob_display: wl.Display = undefined;

const glob_display_listener = wl.Display.Listener{
    .@"error" = handleDisplayError,
    .deleteId = handleDeleteId,
};

pub const Message = struct {
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

    pub fn getIntArg(this: *const Message, arg_offset: *usize) i32 {
        return @bitCast(this.getUIntArg(arg_offset));
    }

    pub fn getUIntArg(this: *const Message, arg_offset: *usize) u32 {
        assert(arg_offset.* < this.payload.len);
        const result = this.payload[arg_offset.*];
        arg_offset.* += 1;
        return result;
    }

    pub fn getObjectArg(this: *const Message, arg_offset: *usize, display: *wl.Display) ?*wl.Object {
        const id = this.getUIntArg(arg_offset);
        if (id < 1) return null;
        return getObject(display, id);
    }

    pub fn getNewIdArg(this: *const Message, arg_offset: *usize, display: *wl.Display, interface: *const wayland.Interface, version: u32) ?*wl.Object {
        _ = .{ this, arg_offset, display };

        const server_id = this.getUIntArg(arg_offset);

        for (&glob_display.server_object_ids, 0..) |*id, idx| {
            if (id.* == 0) {
                id.* = server_id;
                const result = &glob_display.server_objects[idx];
                result.* = .{ .proxy = .{
                    .id = server_id,
                    .version = version,
                    .interface = interface,
                    .display = display,
                    .freelist_node = .{},
                    .listeners = .{},
                } };
                return result;
            }
        }

        log.err("Out of server objects", .{});
        @panic("Out of server objects");
    }

    pub fn getFixedArg(this: *const Message, arg_offset: *usize) wayland.Fixed {
        return .{ .value = @bitCast(this.getUIntArg(arg_offset)) };
    }

    pub fn getStringArg(this: *const Message, arg_offset: *usize) []const u8 {
        const length = this.getUIntArg(arg_offset);

        const arg_size = @sizeOf(@TypeOf(this.payload[0]));
        const arg_count = (length + arg_size - 1) / arg_size;
        assert(arg_offset.* < this.payload.len);
        assert(arg_offset.* + arg_count <= this.payload.len);

        const result = @as([]const u8, @ptrCast(this.payload[arg_offset.*..]))[0 .. length - 1];

        arg_offset.* += arg_count;

        return result;
    }

    pub fn getArrayArg(this: *const Message, arg_offset: *usize) wayland.Array {
        const length = this.getUIntArg(arg_offset);
        assert(length % @sizeOf(u32) == 0);

        const arg_size = @sizeOf(@TypeOf(this.payload[0]));
        const arg_count = length / arg_size;
        assert(arg_offset.* < this.payload.len);
        assert(arg_offset.* + length <= this.payload.len);

        const result: []u32 = this.payload[arg_offset.* .. arg_offset.* + arg_count];

        arg_offset.* += arg_count;

        return result;
    }

    pub fn getFDArg(this: *const Message, fd_offset: *usize) linux.fd_t {
        assert(fd_offset.* < this.fds.len);
        const result = this.fds[fd_offset.*];
        fd_offset.* += 1;
        return result;
    }
};

pub fn displayConnect(path_opt: ?[*:0]const u8, environ_opt: ?*const std.process.Environ) ?*wl.Display {
    assert(!glob_connected);

    var sock_addr = std.mem.zeroes(linux.sockaddr.un);
    const fd = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM, 0) catch unreachable; // TODO: Handle error

    var result: ?*wl.Display = null;

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

            for (glob_display.server_object_ids[0..], glob_display.server_objects[0..]) |*id, *server_obj| {
                id.* = 0;
                server_obj.proxy = .{ .id = 0, .version = 0, .display = &glob_display, .interface = undefined, .freelist_node = .{} };
            }

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

    verbose("display_roundtrip(id = {}) ...", .{display.proxy.id});

    const sync_callback = display.sync();

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

    verbose("display_roundtrip(id = {}) dispatched: {}\n", .{ display.proxy.id, dispatched_count });

    return dispatched_count;
}

fn displayRoundtripSyncDoneHandler(data: ?*anyopaque, _: ?*wl.Callback, _: u32) void {
    const done_ptr: *bool = @ptrCast(data);
    done_ptr.* = true;
}

pub fn displayDispatch(display: *wl.Display) isize {
    return displayDispatchTimeout(display, 0);
}

fn displayDispatchTimeout(display: *wl.Display, first_timeout: c_int) isize {
    assert(display == &glob_display);

    verbose("display_dispatch(id = {}) ...", .{display.proxy.id});

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

                            assert(header.op < object.proxy.interface.events.len);
                            // TODO: Store fd_count in the generated interface, so we can just pop that amount here. OR, pop them on demand in the trampolines
                            for (object.proxy.interface.events[header.op].signature) |arg_type| {
                                if (arg_type == .h) {
                                    assert(fd_dispatch_index < display.receive_fds_used); // TODO: report?
                                    fds[fd_count] = display.receive_fds_buf[fd_dispatch_index];
                                    fd_count += 1;
                                    fd_dispatch_index += 1;
                                }
                            }

                            const message: Message = .{
                                .header = header,
                                .payload = payload,
                                .fds = fds[0..fd_count],
                            };

                            wayland.dispatch(display, &message, object);
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

    verbose("display_dispatch(id = {}) -> dispatched = {}", .{ display.proxy.id, result });

    return result;
}

pub fn displayFlush(display: *wl.Display) void {
    var iov = linux.iovec{ .base = &display.send_payload_buf, .len = display.send_payload_used };

    verbose("display_flush(id = {}) ...", .{display.proxy.id});

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

    verbose("display_flush(id = {}) payload bytes = {}, fds = {}", .{ display.proxy.id, payload_size, fds_count });
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

    while (proxy.listeners.popFirst()) |node| {
        display.free_listeners.prepend(node);
    }

    if (proxy.id < 0xff000000) {
        assert(proxy.id < glob_display.objects.len);
        assert(proxy.id != 1);

        display.free_objects.prepend(&proxy.freelist_node);
    } else {
        for (&glob_display.server_object_ids, 0..) |*server_id, idx| {
            if (proxy.id == server_id.*) {
                server_id.* = 0;
                glob_display.server_objects[idx].proxy = .{
                    .id = 0,
                    .version = 0,
                    .display = &glob_display,
                    .interface = undefined,
                    .freelist_node = .{},
                };
            }
        }
    }
}

pub fn proxyMarshalArrayFlags(proxy: *wl.Proxy, op: u32, interface: ?*const wayland.Interface, version: u32, args: []const wayland.Argument) ?*wl.Object {
    assert(glob_connected);
    const display = proxy.display;

    assert(proxy.interface.methods.len > op);

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

    // TODO: Check arg types (emit more types in interfaces?)
    for (args) |arg| {
        arg_type_switch_blk: switch (arg) {
            .i => |i| message.addArg(&payload_used, @bitCast(i)),
            .u => |u| message.addArg(&payload_used, u),
            .f => |f| message.addArg(&payload_used, @bitCast(f)),
            .s => |s| {
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
            .@"?s" => |s_opt| continue :arg_type_switch_blk .{ .s = if (s_opt) |s| s else "" },
            .o => |o| continue :arg_type_switch_blk .{ .u = o.proxy.id },
            .@"?o" => |o_opt| continue :arg_type_switch_blk .{ .u = if (o_opt) |o| o.proxy.id else 0 },
            .n => {
                assert(interface != null);
                const new_proxy = proxyCreate(display, interface.?, version); // TODO: Is this the right version
                result = new_proxy;
                continue :arg_type_switch_blk .{ .u = new_proxy.id };
            },
            .a => |a| {
                message.addArg(&payload_used, @intCast(a.len));

                var remaining = a.len;
                while (remaining >= 4) : (remaining -= 4) {
                    message.addArg(
                        &payload_used,
                        std.mem.bytesAsValue(u32, a[a.len - remaining .. a.len - remaining + 4]).*,
                    );
                }

                if (remaining > 0) {
                    var last_u32: u32 = 0;
                    for (a[a.len - remaining ..], 0..) |b, bi| {
                        last_u32 |= @as(u32, b) << @as(u5, @intCast((bi * 8)));
                    }
                    message.addArg(&payload_used, last_u32);
                }
            },
            .h => message.addFD(&fds_used, arg.h),
        }
    }

    if (options.verbose_wayland) {
        var print_buf: [1024]u8 = undefined;
        var used: usize = 0;

        var p = std.fmt.bufPrint(print_buf[used..], "  -> {s}.{s}(id = {}", .{ proxy.interface.name, proxy.interface.methods[op].name, proxy.id }) catch unreachable;
        used += p.len;

        var return_id = false;
        for (args) |arg| {
            if (arg == .n) {
                return_id = true;
                continue;
            }

            p = switch (arg) {
                .o => |o| std.fmt.bufPrint(print_buf[used..], ", id = {}", .{o.proxy.id}) catch unreachable,
                .@"?o" => |o| std.fmt.bufPrint(print_buf[used..], ", id = {}", .{if (o) |obj| obj.proxy.id else 0}) catch unreachable,
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

        if (return_id) {
            p = std.fmt.bufPrint(print_buf[used..], " -> id = {}", .{result.?.id}) catch unreachable;
            used += p.len;
        }

        verbose("{s}", .{print_buf[0..used]});
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

    const proxy = &getObject(display, id).proxy;
    assert(proxy.id == id);

    proxyDestroy(proxy);
}

fn getObject(display: *wl.Display, id: u32) *wl.Object {
    assert(display == &glob_display);
    assert(id != 0);

    if (id < 0xff000000) {
        assert(id <= display.objects.len);
        if (id == 1) return @ptrCast(display);
        return &display.objects[id - 1];
    } else {
        for (glob_display.server_object_ids, 0..) |server_id, idx| {
            if (id == server_id) return &display.server_objects[idx];
        }
        @panic("Server side id object not found");
    }
}

const verbose_log = std.log.scoped(.verbose_wayland);
pub inline fn verbose(comptime fmt: []const u8, args: anytype) void {
    if (options.verbose_wayland) verbose_log.debug(fmt, args);
}
