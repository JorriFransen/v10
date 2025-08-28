const std = @import("std");
const log = std.log.scoped(.main);
const win32 = std.os.windows;

const HINSTANCE = win32.HINSTANCE;
const PWSTR = win32.PWSTR;

pub fn wWinMain(h_instance: HINSTANCE, h_prev_instance: ?HINSTANCE, lp_cmd_line: PWSTR, n_cmd_show: c_int) c_int {
    _ = h_instance;
    _ = h_prev_instance;
    _ = lp_cmd_line;
    _ = n_cmd_show;

    log.debug("Hello Windows!", .{});

    return 0;
}
