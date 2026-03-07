const std = @import("std");
const assert = std.debug.assert;

const wayland = @import("wayland");
const wl = wayland.wl;

// TODO: Allocations!
var connected = false;
var display: wl.Display = undefined;

pub fn display_connect(path_opt: ?[*:0]const u8) ?*wl.Display {
    assert(!connected);

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

    display = .{
        .proxy = .{
            .interface = &wl.Display.interface,
            .display = &display,
        },
        .fd = fd,
        .next_request_id = 1,
    };

    return &display;
}
