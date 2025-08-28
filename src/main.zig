const std = @import("std");
const log = std.log.scoped(.main);
const win32 = @import("win32.zig");

pub fn wWinMain(
    h_instance: win32.HINSTANCE,
    h_prev_instance: ?win32.HINSTANCE,
    lp_cmd_line: win32.PWSTR,
    n_cmd_show: c_int,
) c_int {
    _ = h_instance;
    _ = h_prev_instance;
    _ = lp_cmd_line;
    _ = n_cmd_show;

    log.debug("Hello Windows!", .{});

    _ = win32.MessageBoxA(null, "HI!", "cap", win32.MB_OK);

    return 0;
}
