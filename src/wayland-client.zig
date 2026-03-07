const std = @import("std");
const assert = std.debug.assert;

const linux = @import("linux");
const wayland = @import("wayland");
const wl = wayland.wl;

// TODO: Allocations!
var glob_connected = false;
var glob_display: wl.Display = undefined;

pub fn display_connect(path_opt: ?[*:0]const u8) ?*wl.Display {
    assert(!glob_connected);

    var sock_addr = std.mem.zeroes(std.c.sockaddr.un);
    const fd = std.c.socket(std.c.AF.UNIX, std.c.SOCK.STREAM, 0);
    assert(fd >= 0);

    const path: [:0]const u8 = if (path_opt) |path| std.mem.span(path) else blk: {
        // TODO: Construct from XDG_RUNTIME_DIR
        break :blk "/run/user/1000/wayland-0";
    };

    sock_addr.family = std.c.AF.UNIX;
    assert(path.len <= sock_addr.path.len);
    @memcpy(sock_addr.path[0..path.len], path);
    const r = std.c.connect(fd, @ptrCast(&sock_addr), @sizeOf(@TypeOf(sock_addr)));
    assert(r == 0);

    glob_display = .{
        .proxy = .{
            .interface = &wl.Display.interface,
            .display = &glob_display,
            .id = 0,
            .version = wl.Display.interface.version,
        },
        .fd = fd,
        .next_object_id = 1,
    };

    glob_connected = true;

    return &glob_display;
}

pub fn proxy_marshal_array_flags(proxy: *wl.Proxy, op: u32, interface: *const wayland.Interface, version: u32, flags: u32, args: []const wayland.Argument) ?*wl.Object {
    _ = .{ proxy, op, interface, version, flags, args };

    const display = proxy.display;

    assert(proxy.interface.method_count > op);
    const method = proxy.interface.methods.?[op];
    const sig = std.mem.span(method.signature);
    assert(sig.len == args.len); // TODO: Smarter verification (nullable)

    var new_id: u32 = 0;
    const new_object: ?*wl.Object = null;
    if (sig[0] == 'n') {
        new_id = display.next_object_id;
        display.next_object_id += 1;

        // TODO: Allocate/init new proxy
    }

    send(display, proxy.id);
    send(display, op);

    var i: usize = 0;
    while (i < sig.len) : (i += 1) {
        const sig_char = sig[i]; // TODO: Nullable (?)
        const arg = args[i];
        if (sig_char == 'n') send(display, new_id);
        send(display, arg);
    }

    return new_object;
}

pub fn send(display: *wl.Display, value: anytype) void {
    _ = display;

    const T = @TypeOf(value);
    const info = @typeInfo(T);
    switch (info) {
        else => @compileError("Unsupported type"),
    }
}
